use super::lwd;

/// Read-only funding lookup for sender usage explanations. Missing transactions
/// are inconclusive; only a matching raw transaction proves pending funding.
pub(crate) async fn gift_card_funding_reason(
    url: &str,
    funding_txids: &str,
    verified_height: u64,
) -> Result<String, String> {
    use zcash_primitives::transaction::Transaction;
    use zcash_protocol::consensus::BranchId;
    let mut client = lwd::open_lwd_channel_with_cancel(url, || false)
        .await
        .map_err(|e| e.to_string())?;
    let mut heights = Vec::new();
    for id in funding_txids
        .split(',')
        .map(str::trim)
        .filter(|id| !id.is_empty())
    {
        let mut hash = hex::decode(id).map_err(|_| "Invalid funding transaction ID")?;
        if hash.len() != 32 {
            return Err("Invalid funding transaction ID".into());
        }
        hash.reverse();
        let raw = match lwd::get_transaction(&mut client, hash.clone()).await {
            Ok(raw) => raw,
            Err(e) if e.code() == tonic::Code::NotFound => {
                heights.push(None);
                continue;
            }
            Err(e) => return Err(e.to_string()),
        };
        let tx = Transaction::read(&raw.data[..], BranchId::Sapling)
            .map_err(|e| format!("Invalid funding transaction response: {e}"))?;
        if tx.txid().as_ref() != hash.as_slice() {
            return Err("Funding transaction response ID mismatch".into());
        }
        heights.push(Some(raw.height));
    }
    funding_reason(&heights, verified_height).map(str::to_owned)
}

fn funding_reason(heights: &[Option<u64>], verified_height: u64) -> Result<&'static str, String> {
    if heights.is_empty() {
        return Ok("missingFundingInfo");
    }
    let mut pending = false;
    let mut missing = false;
    let mut beyond_scan = false;
    for height in heights {
        match height {
            None => missing = true,
            Some(0 | u64::MAX) => pending = true,
            Some(h) if *h <= u32::MAX as u64 => beyond_scan |= *h > verified_height,
            _ => return Err("Funding transaction height out of range".into()),
        }
    }
    Ok(if missing {
        "fundingNotObserved"
    } else if pending {
        "awaitingConfirmation"
    } else if beyond_scan {
        "scanIncomplete"
    } else {
        "fundingNotObserved"
    })
}

#[cfg(test)]
mod tests {
    use super::funding_reason;
    #[test]
    fn pending_requires_positive_evidence_for_every_funding_id() {
        assert_eq!(
            funding_reason(&[Some(0)], 100).unwrap(),
            "awaitingConfirmation"
        );
        assert_eq!(
            funding_reason(&[Some(u64::MAX), Some(90)], 100).unwrap(),
            "awaitingConfirmation"
        );
        assert_eq!(
            funding_reason(&[Some(0), None], 100).unwrap(),
            "fundingNotObserved"
        );
        assert_eq!(funding_reason(&[None], 100).unwrap(), "fundingNotObserved");
        assert_eq!(funding_reason(&[Some(101)], 100).unwrap(), "scanIncomplete");
        assert_eq!(
            funding_reason(&[Some(90)], 100).unwrap(),
            "fundingNotObserved"
        );
        assert_eq!(funding_reason(&[], 100).unwrap(), "missingFundingInfo");
        assert!(funding_reason(&[Some(u32::MAX as u64 + 1)], 100).is_err());
    }
}
