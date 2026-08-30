use crate::{helper::url::canonical_helper_url_list, types::VotingError};

/// A non-empty configured helper fleet with one canonical identity per helper.
///
/// Construction is the only canonicalization boundary. Downstream tracking
/// and quorum code therefore cannot accidentally treat equivalent URL
/// spellings as distinct configured helpers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct ConfiguredHelperFleet {
    urls: Vec<String>,
}

impl ConfiguredHelperFleet {
    /// Canonicalizes a complete trust-boundary fleet.
    ///
    /// Rejects an empty fleet, malformed helper URLs, and distinct spellings
    /// that canonicalize to the same helper identity.
    pub(super) fn new(configured_urls: &[String]) -> Result<Self, VotingError> {
        if configured_urls.is_empty() {
            return Err(VotingError::InvalidInput {
                message: "configured_server_urls must not be empty".to_string(),
            });
        }
        let urls = canonical_helper_url_list(configured_urls)?;
        if urls.len() != configured_urls.len() {
            return Err(VotingError::InvalidInput {
                message: "configured_server_urls must contain distinct canonical helpers"
                    .to_string(),
            });
        }
        Ok(Self { urls })
    }

    pub(super) fn urls(&self) -> &[String] {
        &self.urls
    }

    pub(super) fn len(&self) -> usize {
        self.urls.len()
    }

    pub(super) fn contains(&self, url: &str) -> bool {
        self.urls.iter().any(|candidate| candidate == url)
    }
}
