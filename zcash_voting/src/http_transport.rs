#[cfg(feature = "client-tree-sync")]
use std::future::Future;

use anyhow::{Context, Result};
use bytes::Bytes;
use http::{Method, Request};
use http_body_util::{BodyExt, Full};
use hyper_rustls::HttpsConnector;
use hyper_util::{
    client::legacy::{connect::HttpConnector, Client},
    rt::TokioExecutor,
};

type RequestBody = Full<Bytes>;
type HyperClient = Client<HttpsConnector<HttpConnector>, RequestBody>;

struct HyperResponse {
    status: u16,
    #[cfg(feature = "client-pir")]
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

/// Direct Hyper/Rustls HTTP transport for client-side network requests.
///
/// `zcash_voting` keeps PIR and tree-sync fetching behind small transport
/// traits, but its client features include this adapter for consumers that want
/// direct cleartext/HTTPS traffic without providing their own transport.
pub struct HyperTransport {
    client: HyperClient,
    #[cfg(feature = "client-tree-sync")]
    runtime: BlockingRuntime,
}

impl HyperTransport {
    pub fn new() -> Self {
        #[cfg(feature = "client-tree-sync")]
        let runtime = BlockingRuntime::new();
        let mut connector = HttpConnector::new();
        connector.enforce_http(false);
        let https = hyper_rustls::HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_or_http()
            .enable_http1()
            .enable_http2()
            .wrap_connector(connector);
        let client = Client::builder(TokioExecutor::new()).build(https);

        Self {
            client,
            #[cfg(feature = "client-tree-sync")]
            runtime,
        }
    }

    async fn request(&self, method: Method, url: &str, body: Vec<u8>) -> Result<HyperResponse> {
        let request = Request::builder()
            .method(method)
            .uri(url)
            .body(Full::new(Bytes::from(body)))
            .context("build HTTP request")?;
        let response = self
            .client
            .request(request)
            .await
            .context("send HTTP request")?;
        let status = response.status().as_u16();
        #[cfg(feature = "client-pir")]
        let headers = response
            .headers()
            .iter()
            .filter_map(|(name, value)| {
                value
                    .to_str()
                    .ok()
                    .map(|value| (name.as_str().to_string(), value.to_string()))
            })
            .collect();
        let body = response
            .into_body()
            .collect()
            .await
            .context("read HTTP response body")?
            .to_bytes()
            .to_vec();

        Ok(HyperResponse {
            status,
            #[cfg(feature = "client-pir")]
            headers,
            body,
        })
    }
}

impl Default for HyperTransport {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(feature = "client-tree-sync")]
struct BlockingRuntime {
    inner: Option<tokio::runtime::Runtime>,
}

#[cfg(feature = "client-tree-sync")]
impl BlockingRuntime {
    fn new() -> Self {
        Self {
            inner: Some(
                tokio::runtime::Builder::new_multi_thread()
                    .enable_all()
                    .build()
                    .expect("create tree-sync HTTP runtime"),
            ),
        }
    }

    fn block_on<F: Future>(&self, future: F) -> F::Output {
        self.inner
            .as_ref()
            .expect("tree-sync HTTP runtime is unavailable")
            .block_on(future)
    }
}

#[cfg(feature = "client-tree-sync")]
impl Drop for BlockingRuntime {
    fn drop(&mut self) {
        if let Some(runtime) = self.inner.take() {
            runtime.shutdown_background();
        }
    }
}

#[cfg(feature = "client-pir")]
impl pir_client::Transport for HyperTransport {
    fn get<'a>(&'a self, url: &'a str) -> pir_client::TransportFuture<'a> {
        Box::pin(async move {
            self.request(Method::GET, url, Vec::new())
                .await
                .map(|response| pir_client::TransportResponse {
                    status: response.status,
                    headers: response.headers,
                    body: response.body,
                })
        })
    }

    fn post<'a>(&'a self, url: &'a str, body: Vec<u8>) -> pir_client::TransportFuture<'a> {
        Box::pin(async move {
            self.request(Method::POST, url, body).await.map(|response| {
                pir_client::TransportResponse {
                    status: response.status,
                    headers: response.headers,
                    body: response.body,
                }
            })
        })
    }
}

#[cfg(feature = "client-tree-sync")]
impl vote_commitment_tree_client::transport::Transport for HyperTransport {
    fn get(
        &self,
        url: &str,
    ) -> std::result::Result<
        vote_commitment_tree_client::transport::TransportResponse,
        vote_commitment_tree_client::transport::TransportError,
    > {
        self.runtime
            .block_on(async { self.request(Method::GET, url, Vec::new()).await })
            .map(
                |response| vote_commitment_tree_client::transport::TransportResponse {
                    status: response.status,
                    body: response.body,
                },
            )
            .map_err(|e| {
                vote_commitment_tree_client::transport::TransportError::Request(e.to_string())
            })
    }
}

#[cfg(all(test, feature = "client-tree-sync"))]
mod tests {
    use super::BlockingRuntime;

    #[test]
    fn blocking_runtime_drop_does_not_panic_inside_tokio_context() {
        let outer = tokio::runtime::Runtime::new().unwrap();
        let result = std::panic::catch_unwind(|| {
            outer.block_on(async {
                let runtime = BlockingRuntime::new();
                drop(runtime);
            });
        });

        assert!(result.is_ok());
    }
}
