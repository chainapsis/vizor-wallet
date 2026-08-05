//! Loopback-only streaming bridge from the embedded Tor client to native
//! desktop updaters.
//!
//! Sparkle cannot consume the embedded Arti client directly. The relay keeps
//! the native updater's HTTP contract while writing upstream response frames
//! straight to the loopback socket, without buffering an update archive on
//! disk or moving its bytes through Flutter Rust Bridge.

use std::{io, sync::OnceLock, time::Duration};

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use http::{header, Response, StatusCode, Uri};
use http_body_util::BodyExt;
use hyper::body::Incoming;
use rand::{rngs::OsRng, RngCore};
use tokio::{
    io::{AsyncReadExt, AsyncWrite, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    sync::{oneshot, Mutex},
    task::{JoinHandle, JoinSet},
};
use url::Url;
use zcash_client_backend::tor::{http::HttpError, Client as TorClient, Error as TorError};

const MAX_REQUEST_HEADER_BYTES: usize = 16 * 1024;
const LOCAL_REQUEST_TIMEOUT: Duration = Duration::from_secs(5);
const RESPONSE_BODY_TIMEOUT: Duration = Duration::from_secs(2 * 60 * 60);
const MAX_REDIRECTS: usize = 5;

struct RelayState {
    resource_url: String,
    shutdown: oneshot::Sender<()>,
    task: JoinHandle<()>,
}

static RELAY_STATE: OnceLock<Mutex<Option<RelayState>>> = OnceLock::new();

fn relay_state() -> &'static Mutex<Option<RelayState>> {
    RELAY_STATE.get_or_init(|| Mutex::new(None))
}

pub async fn start() -> Result<String, String> {
    let mut state = relay_state().lock().await;
    if let Some(state) = state.as_ref() {
        return Ok(state.resource_url.clone());
    }

    let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
        .await
        .map_err(|error| format!("Bind Tor update relay: {error}"))?;
    let port = listener
        .local_addr()
        .map_err(|error| format!("Read Tor update relay address: {error}"))?
        .port();
    let resource_path = format!("/{}/resource", random_token());
    let resource_url = format!("http://127.0.0.1:{port}{resource_path}");
    let (shutdown, shutdown_rx) = oneshot::channel();
    let task = tokio::spawn(run(listener, resource_path, shutdown_rx));

    *state = Some(RelayState {
        resource_url: resource_url.clone(),
        shutdown,
        task,
    });
    log::info!("network privacy: Tor update streaming relay started");
    Ok(resource_url)
}

pub async fn stop() {
    let state = relay_state().lock().await.take();
    if let Some(state) = state {
        let _ = state.shutdown.send(());
        let _ = state.task.await;
        log::info!("network privacy: Tor update streaming relay stopped");
    }
}

async fn run(listener: TcpListener, resource_path: String, mut shutdown: oneshot::Receiver<()>) {
    let mut connections = JoinSet::new();
    loop {
        tokio::select! {
            _ = &mut shutdown => break,
            accepted = listener.accept() => {
                match accepted {
                    Ok((stream, _)) => {
                        let resource_path = resource_path.clone();
                        connections.spawn(async move {
                            if let Err(error) = handle_connection(stream, &resource_path).await {
                                log::warn!("Tor update relay request failed: {error}");
                            }
                        });
                    }
                    Err(error) => {
                        log::warn!("Tor update relay accept failed: {error}");
                        break;
                    }
                }
            }
        }
    }
    connections.abort_all();
    while connections.join_next().await.is_some() {}
}

async fn handle_connection(mut stream: TcpStream, resource_path: &str) -> Result<(), String> {
    let target = read_get_target(&mut stream).await?;
    let (upstream, expected_length) = parse_upstream(&target, resource_path)?;
    let upstream_host = upstream.host_str().unwrap_or("unknown").to_string();
    log::info!("network privacy: Tor update relay request started for {upstream_host}");
    let client = crate::network_privacy::tor_client_for_route(true)?
        .ok_or_else(|| "Tor is not enabled".to_string())?;

    // Sparkle's loopback URLSession has a 60-second request timeout. Send the
    // local response headers immediately; upstream resolution and every body
    // frame still remain fail-closed on the embedded Tor client.
    let framing_header = expected_length.map_or_else(
        || "Transfer-Encoding: chunked\r\n".to_string(),
        |length| format!("Content-Length: {length}\r\n"),
    );
    let response_headers = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n{framing_header}Cache-Control: no-store\r\nConnection: close\r\n\r\n"
    );
    stream
        .write_all(response_headers.as_bytes())
        .await
        .map_err(|error| format!("Write Tor update relay headers: {error}"))?;
    stream
        .flush()
        .await
        .map_err(|error| format!("Flush Tor update relay headers: {error}"))?;

    let (final_url, response) = open_final_response(&client, upstream).await?;
    log::info!(
        "network privacy: Tor update relay upstream resolved to {}",
        final_url.host_str().unwrap_or("unknown")
    );
    tokio::time::timeout(
        RESPONSE_BODY_TIMEOUT,
        stream_response_body(response.into_body(), stream, expected_length),
    )
    .await
    .map_err(|_| "Timed out streaming the Tor update response body".to_string())?
    .map_err(|error| error.to_string())?;
    Ok(())
}

async fn read_get_target(stream: &mut TcpStream) -> Result<String, String> {
    let request = tokio::time::timeout(LOCAL_REQUEST_TIMEOUT, async {
        let mut request = Vec::with_capacity(1024);
        let mut chunk = [0_u8; 1024];
        loop {
            let count = stream.read(&mut chunk).await?;
            if count == 0 {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "loopback request closed before its headers",
                ));
            }
            request.extend_from_slice(&chunk[..count]);
            if request.windows(4).any(|window| window == b"\r\n\r\n") {
                return Ok(request);
            }
            if request.len() > MAX_REQUEST_HEADER_BYTES {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "loopback request headers are too large",
                ));
            }
        }
    })
    .await
    .map_err(|_| "Timed out reading Tor update relay request".to_string())?
    .map_err(|error| format!("Read Tor update relay request: {error}"))?;

    let request = std::str::from_utf8(&request)
        .map_err(|error| format!("Invalid Tor update relay request: {error}"))?;
    let mut parts = request
        .lines()
        .next()
        .ok_or_else(|| "Missing Tor update relay request line".to_string())?
        .split_whitespace();
    let method = parts.next().unwrap_or_default();
    let target = parts.next().unwrap_or_default();
    let version = parts.next().unwrap_or_default();
    if method != "GET" || target.is_empty() || !version.starts_with("HTTP/1.") {
        return Err("Expected a loopback HTTP GET request".to_string());
    }
    Ok(target.to_string())
}

fn parse_upstream(target: &str, resource_path: &str) -> Result<(Url, Option<u64>), String> {
    let local = Url::parse(&format!("http://127.0.0.1{target}"))
        .map_err(|error| format!("Invalid Tor update relay URL: {error}"))?;
    if local.path() != resource_path {
        return Err("Unknown Tor update relay path".to_string());
    }
    let raw_upstream = local
        .query_pairs()
        .find_map(|(name, value)| (name == "url").then(|| value.into_owned()))
        .ok_or_else(|| "Missing Tor update URL".to_string())?;
    let upstream = Url::parse(&raw_upstream)
        .map_err(|error| format!("Invalid upstream update URL: {error}"))?;
    require_https(&upstream)?;
    let expected_length = local
        .query_pairs()
        .find_map(|(name, value)| (name == "length").then(|| value.into_owned()))
        .map(|value| {
            value
                .parse::<u64>()
                .map_err(|error| format!("Invalid expected update length: {error}"))
                .and_then(|length| {
                    (length > 0)
                        .then_some(length)
                        .ok_or_else(|| "Expected update length must be positive".to_string())
                })
        })
        .transpose()?;
    Ok((upstream, expected_length))
}

async fn open_final_response(
    client: &TorClient,
    mut current: Url,
) -> Result<(Url, Response<Incoming>), String> {
    for redirect_count in 0..=MAX_REDIRECTS {
        let uri: Uri = current
            .as_str()
            .parse()
            .map_err(|error| format!("Invalid upstream update URL: {error}"))?;
        let response = client
            .http_get(
                uri,
                |builder| builder.header(header::ACCEPT, "application/octet-stream"),
                |body| async move { Ok::<_, TorError>(body) },
                0,
                |_| None,
            )
            .await
            .map_err(|error| error.to_string())?;

        if is_redirect(response.status()) {
            if redirect_count == MAX_REDIRECTS {
                return Err("Too many Tor update redirects".to_string());
            }
            let location = response
                .headers()
                .get(header::LOCATION)
                .ok_or_else(|| "Tor update redirect is missing Location".to_string())?
                .to_str()
                .map_err(|error| format!("Invalid Tor update redirect: {error}"))?;
            current = current
                .join(location)
                .map_err(|error| format!("Invalid Tor update redirect: {error}"))?;
            require_https(&current)?;
            continue;
        }
        if !response.status().is_success() {
            return Err(format!(
                "Update server returned HTTP {}",
                response.status().as_u16()
            ));
        }
        return Ok((current, response));
    }
    Err("Too many Tor update redirects".to_string())
}

async fn stream_response_body(
    mut body: Incoming,
    mut stream: TcpStream,
    expected_length: Option<u64>,
) -> Result<(), zcash_client_backend::tor::Error> {
    let mut total_bytes = 0_u64;
    let mut received_first_bytes = false;
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(HttpError::from)?;
        if let Ok(data) = frame.into_data() {
            if !data.is_empty() {
                if !received_first_bytes {
                    log::info!("network privacy: Tor update relay received first package bytes");
                    received_first_bytes = true;
                }
                total_bytes += data.len() as u64;
                if expected_length.is_some() {
                    stream.write_all(&data).await?;
                } else {
                    write_chunk(&mut stream, &data).await?;
                }
            }
        }
    }
    if let Some(expected_length) = expected_length {
        if total_bytes != expected_length {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                format!(
                    "Tor update body length mismatch: expected {expected_length}, received {total_bytes}"
                ),
            )
            .into());
        }
    } else {
        stream.write_all(b"0\r\n\r\n").await?;
    }
    stream.flush().await?;
    log::info!("network privacy: Tor update relay completed package stream ({total_bytes} bytes)");
    Ok(())
}

async fn write_chunk(writer: &mut (impl AsyncWrite + Unpin), data: &[u8]) -> Result<(), io::Error> {
    writer
        .write_all(format!("{:X}\r\n", data.len()).as_bytes())
        .await?;
    writer.write_all(data).await?;
    writer.write_all(b"\r\n").await
}

fn require_https(url: &Url) -> Result<(), String> {
    if url.scheme() != "https" || url.host_str().is_none() {
        return Err("Expected an HTTPS update URL".to_string());
    }
    Ok(())
}

fn is_redirect(status: StatusCode) -> bool {
    matches!(
        status,
        StatusCode::MOVED_PERMANENTLY
            | StatusCode::FOUND
            | StatusCode::SEE_OTHER
            | StatusCode::TEMPORARY_REDIRECT
            | StatusCode::PERMANENT_REDIRECT
    )
}

fn random_token() -> String {
    let mut bytes = [0_u8; 24];
    OsRng.fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

#[cfg(test)]
mod tests {
    use tokio::io::{duplex, AsyncReadExt};

    use super::{parse_upstream, write_chunk};

    #[test]
    fn relay_target_requires_the_secret_path_and_https() {
        let (upstream, expected_length) = parse_upstream(
            "/secret/resource?url=https%3A%2F%2Fcdn.example%2FVizor.dmg&length=321",
            "/secret/resource",
        )
        .unwrap();
        assert_eq!(upstream.as_str(), "https://cdn.example/Vizor.dmg");
        assert_eq!(expected_length, Some(321));
        assert!(parse_upstream(
            "/wrong/resource?url=https%3A%2F%2Fcdn.example%2FVizor.dmg",
            "/secret/resource",
        )
        .is_err());
        assert!(parse_upstream(
            "/secret/resource?url=http%3A%2F%2Fcdn.example%2FVizor.dmg",
            "/secret/resource",
        )
        .is_err());
        assert!(parse_upstream(
            "/secret/resource?url=https%3A%2F%2Fcdn.example%2FVizor.dmg&length=0",
            "/secret/resource",
        )
        .is_err());
    }

    #[tokio::test]
    async fn chunk_writer_emits_each_frame_without_waiting_for_completion() {
        let (mut writer, mut reader) = duplex(64);
        write_chunk(&mut writer, b"first").await.unwrap();

        let mut encoded = [0_u8; 10];
        reader.read_exact(&mut encoded).await.unwrap();
        assert_eq!(&encoded, b"5\r\nfirst\r\n");
    }
}
