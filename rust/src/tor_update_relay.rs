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
    // Waits out a bootstrap rather than failing the updater's download.
    let client = crate::network_privacy::tor_client_for_route(true, || false)
        .await?
        .ok_or_else(|| "Tor is not enabled".to_string())?;

    // Respond to the native updater promptly while upstream resolution and
    // every body frame remain fail-closed on the embedded Tor client.
    let response_headers = relay_response_headers(&upstream, expected_length);
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
    let query = local.query().unwrap_or_default();
    let raw_upstream =
        query_parameter(query, "url")?.ok_or_else(|| "Missing Tor update URL".to_string())?;
    let upstream = Url::parse(&raw_upstream)
        .map_err(|error| format!("Invalid upstream update URL: {error}"))?;
    require_https(&upstream)?;
    let expected_length = query_parameter(query, "length")?
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

/// Reads one relay query parameter with plain percent-decoding.
/// Form-urlencoded decoding would rewrite a literal `+` as a space, and the
/// native producers leave `+` unescaped because it is a legal query character,
/// so an upstream URL carrying one would be corrupted before it is fetched.
fn query_parameter(query: &str, name: &str) -> Result<Option<String>, String> {
    let Some((_, value)) = query
        .split('&')
        .filter_map(|pair| pair.split_once('='))
        .find(|(key, _)| *key == name)
    else {
        return Ok(None);
    };
    percent_decode_utf8(value)
        .map(Some)
        .ok_or_else(|| format!("Invalid Tor update relay {name} parameter"))
}

fn content_disposition_header(upstream: &Url) -> Option<String> {
    require_https(upstream).ok()?;
    let encoded_filename = upstream.path_segments()?.next_back()?;
    let filename = percent_decode_utf8(encoded_filename)?;
    let lowercase = filename.to_ascii_lowercase();
    if filename.is_empty()
        || filename.trim() != filename
        || !filename.is_ascii()
        || filename.bytes().any(|byte| byte < b' ' || byte == 0x7f)
        || filename.contains(['"', '/', '\\'])
        || !(lowercase.ends_with(".dmg") || lowercase.ends_with(".delta"))
    {
        return None;
    }
    Some(format!(
        "Content-Disposition: attachment; filename=\"{filename}\"\r\n"
    ))
}

fn relay_response_headers(upstream: &Url, expected_length: Option<u64>) -> String {
    let framing_header = expected_length.map_or_else(
        || "Transfer-Encoding: chunked\r\n".to_string(),
        |length| format!("Content-Length: {length}\r\n"),
    );
    let content_disposition = content_disposition_header(upstream).unwrap_or_default();
    format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n{framing_header}{content_disposition}Cache-Control: no-store\r\nConnection: close\r\n\r\n"
    )
}

fn percent_decode_utf8(value: &str) -> Option<String> {
    let input = value.as_bytes();
    let mut output = Vec::with_capacity(input.len());
    let mut index = 0;
    while index < input.len() {
        if input[index] == b'%' {
            let high = hex_value(*input.get(index + 1)?)?;
            let low = hex_value(*input.get(index + 2)?)?;
            output.push((high << 4) | low);
            index += 3;
        } else {
            output.push(input[index]);
            index += 1;
        }
    }
    String::from_utf8(output).ok()
}

fn hex_value(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
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
                write_body_data(&mut stream, &data, expected_length, &mut total_bytes).await?;
            }
        }
    }
    finish_body(&mut stream, expected_length, total_bytes).await?;
    log::info!("network privacy: Tor update relay completed package stream ({total_bytes} bytes)");
    Ok(())
}

/// Writes one upstream frame downstream in the framing the relay announced.
/// The announced `Content-Length` is what the native updater trusts as the end
/// of the package, so an upstream that sends more must fail the transfer
/// instead of having its surplus bytes silently dropped by the updater.
async fn write_body_data(
    stream: &mut (impl AsyncWrite + Unpin),
    data: &[u8],
    expected_length: Option<u64>,
    total_bytes: &mut u64,
) -> Result<(), io::Error> {
    match expected_length {
        Some(expected_length) => {
            if total_bytes.saturating_add(data.len() as u64) > expected_length {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("Tor update body is longer than the expected {expected_length} bytes"),
                ));
            }
            stream.write_all(data).await?;
        }
        None => write_chunk(stream, data).await?,
    }
    *total_bytes += data.len() as u64;
    Ok(())
}

async fn finish_body(
    stream: &mut (impl AsyncWrite + Unpin),
    expected_length: Option<u64>,
    total_bytes: u64,
) -> Result<(), io::Error> {
    match expected_length {
        Some(expected_length) if total_bytes != expected_length => {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                format!(
                    "Tor update body length mismatch: expected {expected_length}, received {total_bytes}"
                ),
            ));
        }
        Some(_) => {}
        None => stream.write_all(b"0\r\n\r\n").await?,
    }
    stream.flush().await
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
    use url::Url;

    use super::{
        content_disposition_header, finish_body, parse_upstream, relay_response_headers,
        write_body_data, write_chunk,
    };

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

    #[test]
    fn relay_archive_disposition_preserves_safe_filename_extensions() {
        let dmg = Url::parse("https://cdn.example/Vizor%20Wallet.dmg?download=1").unwrap();
        assert!(relay_response_headers(&dmg, None)
            .contains("Content-Disposition: attachment; filename=\"Vizor Wallet.dmg\"\r\n"));

        let delta = Url::parse("https://cdn.example/Vizor-1.2.3.delta").unwrap();
        assert!(relay_response_headers(&delta, Some(321))
            .contains("Content-Disposition: attachment; filename=\"Vizor-1.2.3.delta\"\r\n"));
    }

    #[test]
    fn relay_archive_disposition_rejects_unsafe_filenames() {
        for raw_url in [
            "https://cdn.example/",
            "https://cdn.example/%2E%2E",
            "https://cdn.example/bad%0D%0AInjected.dmg",
            "https://cdn.example/bad%22name.dmg",
            "https://cdn.example/..%2Fsecret.dmg",
            "https://cdn.example/..%5Csecret.delta",
            "https://cdn.example/%FF.dmg",
            "https://cdn.example/release-notes.md",
        ] {
            let url = Url::parse(raw_url).unwrap();
            assert_eq!(
                content_disposition_header(&url),
                None,
                "unexpected safe filename for {raw_url}"
            );
        }
    }

    #[test]
    fn relay_target_preserves_a_plus_in_the_upstream_url() {
        let (upstream, expected_length) = parse_upstream(
            "/secret/resource?url=https://cdn.example/Vizor+1.2.3%2B456.dmg&length=7",
            "/secret/resource",
        )
        .unwrap();
        assert_eq!(upstream.as_str(), "https://cdn.example/Vizor+1.2.3+456.dmg");
        assert_eq!(expected_length, Some(7));
    }

    #[tokio::test]
    async fn chunk_writer_emits_each_frame_without_waiting_for_completion() {
        let (mut writer, mut reader) = duplex(64);
        write_chunk(&mut writer, b"first").await.unwrap();

        let mut encoded = [0_u8; 10];
        reader.read_exact(&mut encoded).await.unwrap();
        assert_eq!(&encoded, b"5\r\nfirst\r\n");
    }

    #[tokio::test]
    async fn relayed_body_stops_at_the_announced_content_length() {
        let (mut writer, mut reader) = duplex(64);
        let mut total_bytes = 0_u64;
        write_body_data(&mut writer, b"first", Some(6), &mut total_bytes)
            .await
            .unwrap();
        let error = write_body_data(&mut writer, b"second", Some(6), &mut total_bytes)
            .await
            .expect_err("over-long upstream body was relayed as a complete download");

        assert_eq!(error.kind(), std::io::ErrorKind::InvalidData);
        assert_eq!(total_bytes, 5);
        let mut relayed = [0_u8; 5];
        reader.read_exact(&mut relayed).await.unwrap();
        assert_eq!(&relayed, b"first");
    }

    #[tokio::test]
    async fn relayed_body_fails_when_the_upstream_stops_early() {
        let (mut writer, _reader) = duplex(64);

        let error = finish_body(&mut writer, Some(6), 5)
            .await
            .expect_err("truncated upstream body completed the transfer");

        assert_eq!(error.kind(), std::io::ErrorKind::UnexpectedEof);
        assert!(finish_body(&mut writer, Some(6), 6).await.is_ok());
    }
}
