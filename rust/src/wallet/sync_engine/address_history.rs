//! Address-local ordering with bounded concurrent network reads.
use std::collections::{BTreeMap, VecDeque};

use futures::{
    future::BoxFuture, stream::BoxStream, stream::FuturesUnordered, FutureExt, StreamExt,
};
use zcash_client_backend::{
    data_api::{TransactionDataRequest, TransactionsInvolvingAddress},
    proto::service::RawTransaction,
};
use zcash_primitives::transaction::builder::DEFAULT_TX_EXPIRY_DELTA;

use super::SyncError;

const MAX_ADDRESS_STREAMS: usize = 4;
type HistoryStream = BoxStream<'static, Result<RawTransaction, SyncError>>;
pub(super) type OpenHistory = Box<
    dyn Fn(TransactionsInvolvingAddress) -> BoxFuture<'static, Result<HistoryStream, SyncError>>,
>;

/// Preserve request semantics. Only overlapping/adjacent ranges with identical
/// filters and scheduling constraints can share a response.
pub(super) fn plan(
    requests: &[TransactionDataRequest],
) -> VecDeque<VecDeque<TransactionsInvolvingAddress>> {
    let mut addresses = BTreeMap::new();
    for request in requests {
        if let TransactionDataRequest::TransactionsInvolvingAddress(req) = request {
            if req
                .block_range_end()
                .is_some_and(|end| end > req.block_range_start())
            {
                addresses
                    .entry(req.address())
                    .or_insert_with(Vec::new)
                    .push(req.clone());
            }
        }
    }
    addresses
        .into_values()
        .map(|mut requests| {
            requests.sort_by_key(|r| {
                (
                    r.tx_status_filter().clone(),
                    r.output_status_filter().clone(),
                    r.request_at(),
                    r.block_range_start(),
                    r.block_range_end(),
                )
            });
            requests.dedup();
            let mut merged: Vec<TransactionsInvolvingAddress> = Vec::new();
            for req in requests {
                if let Some(last) = merged.last_mut() {
                    if req.block_range_start() <= last.block_range_end().unwrap()
                        && req.request_at() == last.request_at()
                        && req.tx_status_filter() == last.tx_status_filter()
                        && req.output_status_filter() == last.output_status_filter()
                    {
                        *last = with_range(
                            last,
                            last.block_range_start(),
                            last.block_range_end()
                                .unwrap()
                                .max(req.block_range_end().unwrap()),
                        );
                        continue;
                    }
                }
                merged.push(req);
            }
            let mut chunks = Vec::new();
            for req in merged {
                let mut start = req.block_range_start();
                let end = req.block_range_end().unwrap();
                while start < end {
                    let remaining = u32::from(end) - u32::from(start);
                    let next = start + remaining.min(DEFAULT_TX_EXPIRY_DELTA + 1);
                    chunks.push(with_range(&req, start, next));
                    start = next;
                }
            }
            chunks.sort_by_key(|r| (r.block_range_start(), r.block_range_end()));
            chunks.into()
        })
        .collect()
}

fn with_range(
    req: &TransactionsInvolvingAddress,
    start: zcash_protocol::consensus::BlockHeight,
    end: zcash_protocol::consensus::BlockHeight,
) -> TransactionsInvolvingAddress {
    let TransactionDataRequest::TransactionsInvolvingAddress(req) =
        TransactionDataRequest::transactions_involving_address(
            req.address(),
            start,
            Some(end),
            req.request_at(),
            req.tx_status_filter().clone(),
            req.output_status_filter().clone(),
        )
    else {
        unreachable!()
    };
    req
}

pub(super) struct AddressRead {
    requests: VecDeque<TransactionsInvolvingAddress>,
    stream: Option<HistoryStream>,
}

impl AddressRead {
    pub fn request(&self) -> &TransactionsInvolvingAddress {
        self.requests.front().unwrap()
    }
    /// Called only after the caller has persisted all messages and completion.
    pub fn finish_range(&mut self) {
        self.requests.pop_front();
        self.stream = None;
    }
}

type ReadResult = (AddressRead, Result<Option<RawTransaction>, SyncError>);

/// No detached tasks: dropping this scheduler cancels every pending network read.
/// At most one message per active address is buffered in these futures. The
/// caller must persist/acknowledge an event before resuming that address.
pub(super) struct HistoryReads {
    pending: VecDeque<VecDeque<TransactionsInvolvingAddress>>,
    active: FuturesUnordered<BoxFuture<'static, ReadResult>>,
    open: OpenHistory,
}

impl HistoryReads {
    pub fn new(
        pending: VecDeque<VecDeque<TransactionsInvolvingAddress>>,
        open: OpenHistory,
    ) -> Self {
        Self {
            pending,
            active: FuturesUnordered::new(),
            open,
        }
    }
    pub fn resume(&mut self, read: AddressRead) {
        if read.requests.is_empty() {
            return;
        }
        let opening = read
            .stream
            .is_none()
            .then(|| (self.open)(read.request().clone()));
        self.active.push(
            async move {
                let mut read = read;
                if let Some(opening) = opening {
                    match opening.await {
                        Ok(stream) => read.stream = Some(stream),
                        Err(error) => return (read, Err(error)),
                    }
                }
                let result = read.stream.as_mut().unwrap().next().await.transpose();
                (read, result)
            }
            .boxed(),
        );
    }
    pub async fn next(&mut self) -> Option<ReadResult> {
        while self.active.len() < MAX_ADDRESS_STREAMS {
            let Some(requests) = self.pending.pop_front() else {
                break;
            };
            self.resume(AddressRead {
                requests,
                stream: None,
            });
        }
        self.active.next().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Mutex,
    };
    use transparent::address::TransparentAddress;
    use zcash_client_backend::data_api::{OutputStatusFilter, TransactionStatusFilter};
    use zcash_protocol::consensus::BlockHeight;

    fn request(address: u8, start: u32, end: u32) -> TransactionDataRequest {
        TransactionDataRequest::transactions_involving_address(
            TransparentAddress::PublicKeyHash([address; 20]),
            BlockHeight::from_u32(start),
            Some(BlockHeight::from_u32(end)),
            None,
            TransactionStatusFilter::Mined,
            OutputStatusFilter::All,
        )
    }
    fn ranges(group: &VecDeque<TransactionsInvolvingAddress>) -> Vec<(u32, u32)> {
        group
            .iter()
            .map(|r| {
                (
                    u32::from(r.block_range_start()),
                    u32::from(r.block_range_end().unwrap()),
                )
            })
            .collect()
    }

    #[test]
    fn address_history_merges_duplicates_overlaps_and_adjacent_ranges() {
        let plans = plan(&[
            request(1, 100, 110),
            request(1, 100, 110),
            request(1, 105, 115),
            request(1, 115, 120),
            request(1, 130, 135),
            request(2, 100, 110),
        ]);
        assert_eq!(plans.len(), 2);
        assert_eq!(ranges(&plans[0]), vec![(100, 120), (130, 135)]);
        assert_eq!(ranges(&plans[1]), vec![(100, 110)]);
    }

    #[test]
    fn address_history_preserves_filters_and_bounds_long_ranges() {
        let mut filtered = request(1, 100, 110);
        if let TransactionDataRequest::TransactionsInvolvingAddress(req) = &mut filtered {
            let TransactionDataRequest::TransactionsInvolvingAddress(other) =
                TransactionDataRequest::transactions_involving_address(
                    req.address(),
                    req.block_range_start(),
                    req.block_range_end(),
                    None,
                    TransactionStatusFilter::All,
                    OutputStatusFilter::All,
                )
            else {
                unreachable!()
            };
            *req = other;
        }
        let plans = plan(&[request(1, 100, 110), filtered]);
        assert_eq!(plans[0].len(), 2);
        let max = DEFAULT_TX_EXPIRY_DELTA + 1;
        let plans = plan(&[request(1, 1, 1 + 3 * max)]);
        assert_eq!(
            ranges(&plans[0]),
            vec![
                (1, 1 + max),
                (1 + max, 1 + 2 * max),
                (1 + 2 * max, 1 + 3 * max)
            ]
        );
        let plans = plan(&[request(1, 8, 8), request(1, 9, 8)]);
        assert!(plans.is_empty());
    }

    struct Live(Arc<AtomicUsize>);
    impl Drop for Live {
        fn drop(&mut self) {
            self.0.fetch_sub(1, Ordering::SeqCst);
        }
    }

    #[tokio::test]
    async fn address_history_parallel_reads_are_bounded_and_cancel_by_drop() {
        let live = Arc::new(AtomicUsize::new(0));
        let opened = Arc::new(AtomicUsize::new(0));
        let open: OpenHistory = Box::new({
            let live = live.clone();
            let opened = opened.clone();
            move |_| {
                let live = live.clone();
                let opened = opened.clone();
                async move {
                    live.fetch_add(1, Ordering::SeqCst);
                    opened.fetch_add(1, Ordering::SeqCst);
                    let guard = Live(live);
                    Ok(futures::stream::unfold(guard, |guard| async move {
                        futures::future::pending::<()>().await;
                        Some((Ok(RawTransaction::default()), guard))
                    })
                    .boxed())
                }
                .boxed()
            }
        });
        let requests: Vec<_> = (0..10).map(|i| request(i, 100, 110)).collect();
        let mut reads = HistoryReads::new(plan(&requests), open);
        assert!(futures::poll!(Box::pin(reads.next())).is_pending());
        assert_eq!(opened.load(Ordering::SeqCst), 4);
        assert_eq!(live.load(Ordering::SeqCst), 4);
        drop(reads);
        assert_eq!(live.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn address_history_waits_for_ack_and_drops_later_ranges_on_failure() {
        let opened = Arc::new(Mutex::new(Vec::new()));
        let open: OpenHistory = Box::new({
            let opened = opened.clone();
            move |req| {
                opened
                    .lock()
                    .unwrap()
                    .push((req.address(), u32::from(req.block_range_start())));
                async { Ok(futures::stream::iter(vec![Ok(RawTransaction::default())]).boxed()) }
                    .boxed()
            }
        });
        let requests = vec![
            request(1, 100, 110),
            request(1, 120, 130),
            request(2, 100, 110),
        ];
        let mut reads = HistoryReads::new(plan(&requests), open);
        let mut acknowledged = 0;
        while let Some((mut read, result)) = reads.next().await {
            assert!(!opened
                .lock()
                .unwrap()
                .iter()
                .any(|(_, start)| *start == 120));
            if read.request().address() == TransparentAddress::PublicKeyHash([1; 20]) {
                // Simulate storage failure: don't resume or acknowledge this address.
                assert!(result.unwrap().is_some());
                continue;
            }
            if result.unwrap().is_none() {
                acknowledged += 1;
                read.finish_range();
            }
            reads.resume(read);
        }
        assert_eq!(acknowledged, 1);
        assert_eq!(opened.lock().unwrap().len(), 2);
        // The original durable requests remain eligible for retry from their start.
        assert_eq!(ranges(&plan(&requests)[0]), vec![(100, 110), (120, 130)]);
    }

    #[tokio::test]
    async fn address_history_completes_more_than_four_addresses_without_duplicates() {
        let opened = Arc::new(Mutex::new(Vec::new()));
        let open: OpenHistory = Box::new({
            let opened = opened.clone();
            move |req| {
                opened.lock().unwrap().push(req.address());
                async { Ok(futures::stream::iter(vec![Ok(RawTransaction::default())]).boxed()) }
                    .boxed()
            }
        });
        let mut reads = HistoryReads::new(
            plan(&(0..10).map(|i| request(i, 100, 110)).collect::<Vec<_>>()),
            open,
        );
        let mut messages = 0;
        let mut complete = 0;
        while let Some((mut read, result)) = reads.next().await {
            if result.unwrap().is_some() {
                messages += 1;
            } else {
                complete += 1;
                read.finish_range();
            }
            reads.resume(read);
        }
        assert_eq!((messages, complete), (10, 10));
        let mut opened = opened.lock().unwrap().clone();
        opened.sort();
        opened.dedup();
        assert_eq!(opened.len(), 10);
    }

    #[tokio::test]
    async fn address_history_stream_error_does_not_look_like_completion() {
        let open: OpenHistory = Box::new(|_| {
            async {
                Ok(futures::stream::iter(vec![
                    Ok(RawTransaction::default()),
                    Err(SyncError::net("stream failed")),
                ])
                .boxed())
            }
            .boxed()
        });
        let mut reads =
            HistoryReads::new(plan(&[request(1, 100, 110), request(1, 120, 130)]), open);
        let (read, result) = reads.next().await.unwrap();
        assert!(result.unwrap().is_some());
        reads.resume(read);
        let (read, result) = reads.next().await.unwrap();
        assert!(result.is_err());
        assert_eq!(u32::from(read.request().block_range_start()), 100);
        // Dropping the failed read abandons later ranges; no EOF acknowledgement.
        drop(read);
        assert!(reads.next().await.is_none());
    }

    #[tokio::test]
    async fn address_history_opens_next_range_only_after_eof_acknowledgement() {
        let opened = Arc::new(AtomicUsize::new(0));
        let open: OpenHistory = Box::new({
            let opened = opened.clone();
            move |_| {
                opened.fetch_add(1, Ordering::SeqCst);
                async { Ok(futures::stream::empty().boxed()) }.boxed()
            }
        });
        let mut reads =
            HistoryReads::new(plan(&[request(1, 100, 110), request(1, 120, 130)]), open);
        let (mut read, result) = reads.next().await.unwrap();
        assert!(result.unwrap().is_none());
        assert_eq!(opened.load(Ordering::SeqCst), 1);
        read.finish_range();
        reads.resume(read);
        let (mut read, result) = reads.next().await.unwrap();
        assert!(result.unwrap().is_none());
        assert_eq!(opened.load(Ordering::SeqCst), 2);
        read.finish_range();
        reads.resume(read);
        assert!(reads.next().await.is_none());
    }
}
