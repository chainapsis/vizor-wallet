use std::{
    collections::{HashMap, VecDeque},
    io::{Read, Write},
    net::{SocketAddr, TcpListener, TcpStream},
    sync::{
        atomic::{AtomicBool, AtomicUsize, Ordering},
        Arc, Condvar, Mutex,
    },
    thread::{self, JoinHandle},
    time::Duration,
};

#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq)]
pub enum Endpoint {
    Readiness,
    Submit,
    ShareStatus,
}

#[derive(Clone)]
pub enum Response {
    Json {
        status: u16,
        body: String,
        delay: Duration,
    },
    CloseAfterRequest {
        delay: Duration,
    },
    Stall {
        duration: Duration,
    },
    GatedJson {
        gate: Arc<ResponseGate>,
        status: u16,
        body: String,
    },
}

impl Response {
    pub fn ok() -> Self {
        Self::json(200, r#"{"status":"ok"}"#)
    }

    pub fn queued() -> Self {
        Self::json(200, r#"{"status":"queued"}"#)
    }

    pub fn duplicate() -> Self {
        Self::json(200, r#"{"status":"duplicate"}"#)
    }

    pub fn pending() -> Self {
        Self::json(200, r#"{"status":"pending"}"#)
    }

    pub fn confirmed() -> Self {
        Self::json(200, r#"{"status":"confirmed"}"#)
    }

    pub fn status(status: u16) -> Self {
        Self::json(status, "{}")
    }

    pub fn delayed(self, delay: Duration) -> Self {
        match self {
            Self::Json { status, body, .. } => Self::Json {
                status,
                body,
                delay,
            },
            other => other,
        }
    }

    fn json(status: u16, body: &str) -> Self {
        Self::Json {
            status,
            body: body.to_string(),
            delay: Duration::ZERO,
        }
    }
}

#[derive(Default)]
pub struct ResponseGate {
    released: Mutex<bool>,
    changed: Condvar,
}

impl ResponseGate {
    pub fn release(&self) {
        *self.released.lock().unwrap() = true;
        self.changed.notify_all();
    }

    fn wait(&self) {
        let mut released = self.released.lock().unwrap();
        while !*released {
            let (next, timeout) = self
                .changed
                .wait_timeout(released, Duration::from_secs(2))
                .unwrap();
            released = next;
            if timeout.timed_out() {
                break;
            }
        }
    }
}

#[derive(Clone, Debug)]
pub struct ObservedRequest {
    pub sequence: usize,
    pub method: String,
    pub path: String,
    pub body: Vec<u8>,
}

impl ObservedRequest {
    pub fn json(&self) -> serde_json::Value {
        serde_json::from_slice(&self.body).expect("observed request body must be JSON")
    }
}

struct ServerState {
    scripts: Mutex<HashMap<Endpoint, VecDeque<Response>>>,
    requests: Mutex<Vec<ObservedRequest>>,
    stop: AtomicBool,
    listener: Mutex<Option<JoinHandle<()>>>,
    connections: Mutex<Vec<JoinHandle<()>>>,
    sequence: Arc<AtomicUsize>,
    active_status: Arc<AtomicUsize>,
    max_active_status: Arc<AtomicUsize>,
}

pub struct HelperServer {
    address: SocketAddr,
    state: Arc<ServerState>,
}

impl HelperServer {
    pub fn url(&self) -> String {
        format!("http://{}", self.address)
    }

    pub fn enqueue(&self, endpoint: Endpoint, response: Response) {
        self.state
            .scripts
            .lock()
            .unwrap()
            .entry(endpoint)
            .or_default()
            .push_back(response);
    }

    pub fn enqueue_many(&self, endpoint: Endpoint, responses: impl IntoIterator<Item = Response>) {
        self.state
            .scripts
            .lock()
            .unwrap()
            .entry(endpoint)
            .or_default()
            .extend(responses);
    }

    pub fn requests(&self) -> Vec<ObservedRequest> {
        self.state.requests.lock().unwrap().clone()
    }

    pub fn request_count(&self, endpoint: Endpoint) -> usize {
        self.requests()
            .iter()
            .filter(|request| endpoint_for(&request.method, &request.path) == endpoint)
            .count()
    }

    pub fn stop(&self) {
        self.state.stop.store(true, Ordering::SeqCst);
        let _ = TcpStream::connect(self.address);
        if let Some(handle) = self.state.listener.lock().unwrap().take() {
            handle.join().unwrap();
        }
    }
}

pub struct HelperFleet {
    servers: Vec<HelperServer>,
    max_active_status: Arc<AtomicUsize>,
}

impl HelperFleet {
    pub fn new(count: usize) -> Self {
        let sequence = Arc::new(AtomicUsize::new(0));
        let active_status = Arc::new(AtomicUsize::new(0));
        let max_active_status = Arc::new(AtomicUsize::new(0));
        let servers = (0..count)
            .map(|_| {
                spawn_server(
                    Arc::clone(&sequence),
                    Arc::clone(&active_status),
                    Arc::clone(&max_active_status),
                )
            })
            .collect();
        Self {
            servers,
            max_active_status,
        }
    }

    pub fn server(&self, index: usize) -> &HelperServer {
        &self.servers[index]
    }

    pub fn urls(&self) -> Vec<String> {
        self.servers.iter().map(HelperServer::url).collect()
    }

    pub fn requests(&self) -> Vec<ObservedRequest> {
        let mut requests = self
            .servers
            .iter()
            .flat_map(HelperServer::requests)
            .collect::<Vec<_>>();
        requests.sort_by_key(|request| request.sequence);
        requests
    }

    pub fn post_requests(&self) -> Vec<ObservedRequest> {
        self.requests()
            .into_iter()
            .filter(|request| request.method == "POST")
            .collect()
    }

    pub fn max_concurrent_status_requests(&self) -> usize {
        self.max_active_status.load(Ordering::SeqCst)
    }
}

impl Drop for HelperFleet {
    fn drop(&mut self) {
        for server in &self.servers {
            server.state.stop.store(true, Ordering::SeqCst);
            let _ = TcpStream::connect(server.address);
        }
        for server in &self.servers {
            if let Some(handle) = server.state.listener.lock().unwrap().take() {
                let _ = handle.join();
            }
        }
        for server in &self.servers {
            for handle in server.state.connections.lock().unwrap().drain(..) {
                let _ = handle.join();
            }
        }
    }
}

fn spawn_server(
    sequence: Arc<AtomicUsize>,
    active_status: Arc<AtomicUsize>,
    max_active_status: Arc<AtomicUsize>,
) -> HelperServer {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let state = Arc::new(ServerState {
        scripts: Mutex::new(HashMap::new()),
        requests: Mutex::new(Vec::new()),
        stop: AtomicBool::new(false),
        listener: Mutex::new(None),
        connections: Mutex::new(Vec::new()),
        sequence,
        active_status,
        max_active_status,
    });
    let listener_state = Arc::clone(&state);
    let handle = thread::spawn(move || loop {
        let Ok((stream, _)) = listener.accept() else {
            break;
        };
        if listener_state.stop.load(Ordering::SeqCst) {
            break;
        }
        let connection_state = Arc::clone(&listener_state);
        let handle = thread::spawn(move || handle_connection(stream, connection_state));
        listener_state.connections.lock().unwrap().push(handle);
    });
    *state.listener.lock().unwrap() = Some(handle);
    HelperServer { address, state }
}

fn handle_connection(mut stream: TcpStream, state: Arc<ServerState>) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
    let Some((method, path, body)) = read_request(&mut stream) else {
        return;
    };
    let endpoint = endpoint_for(&method, &path);
    let sequence = state.sequence.fetch_add(1, Ordering::SeqCst);
    state.requests.lock().unwrap().push(ObservedRequest {
        sequence,
        method,
        path,
        body,
    });

    let tracks_concurrency = endpoint == Endpoint::ShareStatus;
    if tracks_concurrency {
        let active = state.active_status.fetch_add(1, Ordering::SeqCst) + 1;
        state.max_active_status.fetch_max(active, Ordering::SeqCst);
    }

    let response = state
        .scripts
        .lock()
        .unwrap()
        .entry(endpoint)
        .or_default()
        .pop_front()
        .unwrap_or_else(|| default_response(endpoint));
    write_response(&mut stream, response);

    if tracks_concurrency {
        state.active_status.fetch_sub(1, Ordering::SeqCst);
    }
}

fn read_request(stream: &mut TcpStream) -> Option<(String, String, Vec<u8>)> {
    let mut request = Vec::new();
    let mut chunk = [0u8; 4096];
    let header_end = loop {
        if let Some(index) = request.windows(4).position(|bytes| bytes == b"\r\n\r\n") {
            break index + 4;
        }
        let read = stream.read(&mut chunk).ok()?;
        if read == 0 {
            return None;
        }
        request.extend_from_slice(&chunk[..read]);
    };
    let headers = String::from_utf8_lossy(&request[..header_end]);
    let request_line = headers.lines().next()?;
    let mut parts = request_line.split_whitespace();
    let method = parts.next()?.to_string();
    let path = parts.next()?.to_string();
    let content_length = headers
        .lines()
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            name.eq_ignore_ascii_case("content-length")
                .then(|| value.trim().parse::<usize>().ok())
                .flatten()
        })
        .unwrap_or(0);
    while request.len() < header_end + content_length {
        let read = stream.read(&mut chunk).ok()?;
        if read == 0 {
            return None;
        }
        request.extend_from_slice(&chunk[..read]);
    }
    Some((
        method,
        path,
        request[header_end..header_end + content_length].to_vec(),
    ))
}

fn endpoint_for(method: &str, path: &str) -> Endpoint {
    if method == "POST" && path.ends_with("/shares") {
        Endpoint::Submit
    } else if path.contains("/share-status/") {
        Endpoint::ShareStatus
    } else {
        Endpoint::Readiness
    }
}

fn default_response(endpoint: Endpoint) -> Response {
    match endpoint {
        Endpoint::Readiness => Response::ok(),
        Endpoint::Submit => Response::queued(),
        Endpoint::ShareStatus => Response::pending(),
    }
}

fn write_response(stream: &mut TcpStream, response: Response) {
    match response {
        Response::Json {
            status,
            body,
            delay,
        } => {
            thread::sleep(delay);
            let reason = match status {
                200 => "OK",
                400 => "Bad Request",
                429 => "Too Many Requests",
                500 => "Internal Server Error",
                503 => "Service Unavailable",
                _ => "Response",
            };
            let response = format!(
                "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(response.as_bytes());
        }
        Response::CloseAfterRequest { delay } => thread::sleep(delay),
        Response::Stall { duration } => thread::sleep(duration),
        Response::GatedJson { gate, status, body } => {
            gate.wait();
            write_response(
                stream,
                Response::Json {
                    status,
                    body,
                    delay: Duration::ZERO,
                },
            );
        }
    }
}
