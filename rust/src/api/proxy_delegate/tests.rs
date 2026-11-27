//! Boundary checks for the delegate ballot list's paging, with pages built
//! as the vote chain's REST API encodes them. zcash_voting's own tests
//! cover the rules behind the call.

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};

use super::*;

/// The round under test, as hex.
const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";

/// The kind of a refused call.
fn kind<T: std::fmt::Debug>(result: Result<T, ApiDelegateModeError>) -> ApiDelegateModeErrorKind {
    result.expect_err("the call is refused").kind
}

/// One ballot page as the REST API encodes it.
fn ballot_page(ballots: &[(u32, &[u32])], next_start_after: u32) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({
        "ballots": ballots
            .iter()
            .map(|(delegate_index, options)| serde_json::json!({
                "vote_round_id": BASE64.encode([1u8; 32]),
                "delegate_index": delegate_index,
                "options": options,
                "height": 12,
            }))
            .collect::<Vec<_>>(),
        "next_start_after": next_start_after,
    }))
    .unwrap()
}

/// Delegate `delegate_index`'s listed ballot of `options`.
fn listed(delegate_index: u32, options: &[u32]) -> ApiChainDelegateBallot {
    ApiChainDelegateBallot {
        delegate_index,
        options: options.to_vec(),
        height: 12,
    }
}

#[test]
fn ballot_pages_chain_by_their_last_delegate() {
    let page = |start_after, body: &[u8], index| {
        delegate_ballot_page(ROUND_ID.to_owned(), start_after, body.to_vec(), index)
    };
    let first = ballot_page(&[(2, &[0, 1]), (5, &[1, 1])], 5);
    let last = ballot_page(&[(9, &[1, 0])], 0);
    assert_eq!(
        page(0, &first, Some(9)).unwrap(),
        ApiDelegateBallotSearch {
            next_start_after: Some(5),
            ballot: None,
        }
    );
    assert_eq!(
        page(5, &last, Some(9)).unwrap(),
        ApiDelegateBallotSearch {
            next_start_after: None,
            ballot: Some(listed(9, &[1, 0])),
        }
    );
    assert_eq!(page(5, &last, None).unwrap().ballot, None);
    assert_eq!(page(0, b"{}", None).unwrap().next_start_after, None);
    for (start_after, body, why) in [
        (
            0,
            ballot_page(&[(2, &[0])], 7),
            "continues after another delegate",
        ),
        (
            9,
            last.clone(),
            "repeats a delegate at or below start_after",
        ),
        (0, b"not json".to_vec(), "does not parse"),
    ] {
        assert_eq!(
            kind(page(start_after, &body, None)),
            ApiDelegateModeErrorKind::ChainAnswer,
            "a page that {why}"
        );
    }
    assert_eq!(
        kind(delegate_ballot_page("01".to_owned(), 0, first, None)),
        ApiDelegateModeErrorKind::Other,
        "a round id that is not 32 bytes"
    );
}
