# Transaction resubmission recovery

Automatic resubmission excludes a previously mined transaction while status work
(`tx_retrieval_queue.query_type = 0`) remains pending. Candidate selection checks
this atomically in SQL. Payload work (`query_type = 1`) does not activate the
guard. Failed or inconclusive status retrieval retains status work. Enhancement
returns the txids with conclusive non-mined observations without deleting their
status rows. Both post-batch and queue-drain resubmission complete only those
requests after validating an unchanged tip identity. Errors, cancellation, and
callers that do not reach resubmission leave the guard intact.

Durable evidence consists of a positioned received note or an entry in
`vizor_mined_transactions`. The latter covers sends without change, including
transparent send-max transactions. A SQLite trigger records the transaction ID
before an update replaces a non-null mined height. The record and the update
commit or roll back together; a history-write error prevents the rewind from
clearing that mined height. Deleting the transaction also deletes its history.
Both status suppression and pending-scan exclusions use the same evidence.

The local schema is installed during wallet initialization and on writable
wallet opens. Existing mined transactions are protected on subsequent rewinds.
This does not reconstruct mined evidence already erased before installation:
spend links also exist before mining, and the backend removes nullifier block
locators during rewind, so neither is sufficient to infer past mining.

After final status recovery, immediate resubmission requires the refreshed tip
height and hash to match the stored tip. Equal height without a stored hash
retains status work and skips the immediate pass, preserving suppression across
subsequent sync runs. An advanced tip queues scanning before resubmission and resets progress
totals to the newly queued work, including when the prior queue was empty.

These guards do not restrict the initial broadcast of a new transaction.
