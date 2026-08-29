//! Canonical helper-server identity.

use url::{Host, Url};

use crate::types::VotingError;

/// Returns the stable base URL used for helper identity and persistence.
///
/// Helper bases may include a mount path, but not credentials, a query, or a
/// fragment. The returned form has a normalized origin, no default port, no
/// trailing slash, and canonical percent escapes in the path, so equivalent
/// configuration spellings cannot bypass delivery-history checks. Escapes for
/// unreserved ASCII characters are decoded; all other escapes use uppercase
/// hexadecimal digits and remain escaped.
///
/// This is the identity contract for every share delivery and persistence
/// API: a URL this function rejects is rejected by those APIs with
/// [`VotingError::InvalidInput`]. Validate helper configuration with it
/// before submitting shares over the network.
pub fn canonicalize_helper_base_url(value: &str) -> Result<String, VotingError> {
    let trimmed = value.trim();
    let mut url = Url::parse(trimmed).map_err(|error| VotingError::InvalidInput {
        message: format!("invalid helper server url {trimmed:?}: {error}"),
    })?;
    if !matches!(url.scheme(), "http" | "https") {
        return Err(VotingError::InvalidInput {
            message: format!("helper server url must be http or https, got {trimmed}"),
        });
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(VotingError::InvalidInput {
            message: "helper server url must not contain credentials".to_string(),
        });
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err(VotingError::InvalidInput {
            message: "helper server url must not contain a query or fragment".to_string(),
        });
    }

    if let Some(Host::Domain(domain)) = url.host() {
        if let Some(domain) = domain.strip_suffix('.') {
            let domain = domain.to_string();
            url.set_host(Some(&domain))
                .map_err(|error| VotingError::InvalidInput {
                    message: format!("invalid helper server host in {trimmed}: {error}"),
                })?;
        }
    }

    let default_port = match url.scheme() {
        "http" => Some(80),
        "https" => Some(443),
        _ => None,
    };
    if url.port() == default_port {
        url.set_port(None).map_err(|_| VotingError::InvalidInput {
            message: format!("invalid helper server port in {trimmed}"),
        })?;
    }

    let path = normalize_percent_escapes(url.path()).map_err(|_| VotingError::InvalidInput {
        message: format!("invalid percent escape in helper server path {trimmed:?}"),
    })?;
    url.set_path(&path);

    // Query and fragment components are forbidden above, so trimming the
    // serialized suffix cannot alter anything except redundant path slashes.
    Ok(url.as_str().trim_end_matches('/').to_string())
}

fn normalize_percent_escapes(path: &str) -> Result<String, ()> {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";

    let mut normalized = String::with_capacity(path.len());
    let mut remaining = path;
    while let Some(index) = remaining.find('%') {
        normalized.push_str(&remaining[..index]);

        let bytes = remaining.as_bytes();
        let high = bytes
            .get(index + 1)
            .copied()
            .and_then(hex_value)
            .ok_or(())?;
        let low = bytes
            .get(index + 2)
            .copied()
            .and_then(hex_value)
            .ok_or(())?;
        let value = (high << 4) | low;
        if value.is_ascii_alphanumeric() || matches!(value, b'-' | b'.' | b'_' | b'~') {
            normalized.push(char::from(value));
        } else {
            normalized.push('%');
            normalized.push(char::from(HEX[usize::from(high)]));
            normalized.push(char::from(HEX[usize::from(low)]));
        }
        remaining = &remaining[index + 3..];
    }
    normalized.push_str(remaining);
    Ok(normalized)
}

fn hex_value(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

/// Canonicalizes a helper URL list, deduplicating equivalent spellings.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] when any entry fails
/// [`canonicalize_helper_base_url`]; nothing is silently dropped.
pub fn canonical_helper_url_list(urls: &[String]) -> Result<Vec<String>, VotingError> {
    let mut canonical = Vec::with_capacity(urls.len());
    for url in urls {
        let url = canonicalize_helper_base_url(url)?;
        if !canonical.contains(&url) {
            canonical.push(url);
        }
    }
    Ok(canonical)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonicalizes_equivalent_helper_bases() {
        assert_eq!(
            canonicalize_helper_base_url(" HTTPS://Helper.Example:443/vote/// ").unwrap(),
            "https://helper.example/vote"
        );
        assert_eq!(
            canonicalize_helper_base_url("http://helper.example:80/").unwrap(),
            "http://helper.example"
        );
        assert_eq!(
            canonicalize_helper_base_url("http://helper.example./").unwrap(),
            "http://helper.example"
        );
    }

    #[test]
    fn preserves_non_default_ports_and_mount_paths() {
        assert_eq!(
            canonicalize_helper_base_url("https://helper.example:8443/vote").unwrap(),
            "https://helper.example:8443/vote"
        );
        assert_eq!(
            canonicalize_helper_base_url("https://helper.example/vote%20mount/").unwrap(),
            "https://helper.example/vote%20mount"
        );
    }

    #[test]
    fn normalizes_percent_escapes_without_decoding_reserved_characters() {
        assert_eq!(
            canonicalize_helper_base_url("https://helper.example/%7eoperator/%41").unwrap(),
            "https://helper.example/~operator/A"
        );
        assert_eq!(
            canonicalize_helper_base_url("https://helper.example/vote%2fmount/caf%c3%a9").unwrap(),
            "https://helper.example/vote%2Fmount/caf%C3%A9"
        );
        assert_ne!(
            canonicalize_helper_base_url("https://helper.example/vote%2fmount").unwrap(),
            canonicalize_helper_base_url("https://helper.example/vote/mount").unwrap()
        );
    }

    #[test]
    fn rejects_non_base_or_credentialed_urls() {
        for value in [
            "file:///tmp/helper",
            "https://user@example.com",
            "https://example.com?helper=1",
            "https://example.com/#fragment",
            "https://example.com/%",
            "https://example.com/%2",
            "https://example.com/%GG",
        ] {
            assert!(canonicalize_helper_base_url(value).is_err(), "{value}");
        }
    }

    #[test]
    fn canonical_list_deduplicates_equivalent_urls_and_rejects_invalid_entries() {
        let urls = vec![
            "HTTPS://Helper.Example:443/vote/".to_string(),
            "https://helper.example/vote".to_string(),
            "https://helper.example./vote".to_string(),
            "https://helper.example/%76ote".to_string(),
            "https://helper.example/vote%2fmount".to_string(),
            "https://helper.example/vote%2Fmount".to_string(),
            "https://other.example".to_string(),
        ];
        assert_eq!(
            canonical_helper_url_list(&urls).unwrap(),
            vec![
                "https://helper.example/vote".to_string(),
                "https://helper.example/vote%2Fmount".to_string(),
                "https://other.example".to_string(),
            ]
        );

        let invalid = vec![
            "https://helper.example".to_string(),
            "https://other.example?tenant=1".to_string(),
        ];
        assert!(canonical_helper_url_list(&invalid).is_err());
    }
}
