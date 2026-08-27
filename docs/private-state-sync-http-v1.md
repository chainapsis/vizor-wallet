# Private state sync HTTP protocol v1

This protocol stores only opaque, client-encrypted objects. The service never
receives a UFVK, account UUID, plaintext, voting round ID, or feature schema.
JSON integers are unsigned and JSON byte strings use unpadded base64url.

## Identity and routes

`object_id` is `SHA-256("Vizor private state object ID v1" || auth_public_key)`
as produced by the client protocol. It is the only stable server-side object
identifier.

- `POST /api/private-state/v1/objects/{object_id}/challenge`
- `GET /api/private-state/v1/objects/{object_id}`
- `PUT /api/private-state/v1/objects/{object_id}`
- `POST /api/private-state/v1/objects/{object_id}/put` (transport alias for
  signed PUT)

Every response sets `Cache-Control: no-store`. Requests and logs must not add
wallet addresses, IP-derived account identifiers, or analytics identifiers to
the object record.

The POST `/put` alias exists for the app's embedded Tor HTTP transport, which
supports body-bearing POST requests but not arbitrary methods. It executes the
same handler as PUT and authorization is still signed and verified with the
canonical method `PUT`; the transport method does not weaken or alter the
signed operation.

## Challenge

The challenge request contains `protocol_version` and
`auth_public_key_base64`. The server verifies that the public key hashes to the
path object ID, then returns:

```json
{
  "challenge_base64": "...",
  "expires_at_seconds": 1787565600,
  "audience": "https://sync.vizor.example/v1"
}
```

Challenges contain at least 128 bits from a CSPRNG, expire within two minutes,
are bound to the full object reference, and are consumed atomically on the
first request attempt whether verification succeeds or fails. Deployments cap
outstanding challenges and rate-limit by coarse abuse controls that are not
persisted as wallet identity.

## Authorization

GET and PUT send these headers (or an equivalent structured authorization
object):

- `X-Vizor-Protocol-Version`
- `X-Vizor-Auth-Public-Key`
- `X-Vizor-Challenge`
- `X-Vizor-Audience`
- `X-Vizor-Expires-At`
- `X-Vizor-Content-Hash`
- `X-Vizor-Signature`

The signature is the canonical Ed25519 request authorization defined by the
Rust `private_state_sync` module. GET signs SHA-256 of empty bytes. PUT signs a
domain-separated SHA-256 digest computed from the canonical signed envelope.
That digest exists only in the authorization header; it is not stored as part
of the envelope.

The server rejects requests unless the challenge exists, is unused, is bound
to the same object, the signed expiry is after the server clock and no later
than challenge expiry, the audience is exact, the object ID is self-certifying,
and the signature is valid.

## GET

Success returns `200` and the encrypted envelope. An authenticated missing
object returns `404`. An unauthenticated caller cannot distinguish missing from
existing objects.

## PUT and atomic creation

The body is the encrypted envelope itself:

```json
{
  "protocol_version": 1,
  "object_id": "...",
  "auth_public_key_base64": "...",
  "nonce_base64": "...",
  "ciphertext_base64": "...",
  "signature_base64": "..."
}
```

The server:

1. consumes and verifies the request authorization;
2. verifies the self-certifying object reference, envelope signature, size
   limits, and the authorization's envelope content digest;
3. atomically inserts the object only when `object_id` does not exist;
4. returns `204` for the winner or `409` without changing storage when the
   object already exists.

There is no revision, update, delete, or compare-and-set operation. Once an
object ID exists its envelope is immutable. New application state always uses
a newly derived object key and therefore a new object ID.

## App object policies

Voting completion uses one immutable create-only object per authenticated
round. It stores display recovery data, including the encrypted choices, while
the Rust recovery database and chain remain authoritative.

Swap and Pay share one finalized activity archive implementation but use
separate namespaces. Only `complete` and `refunded` records are eligible.
Pending, failed, and expired activity never leaves the installation. Each
archive generation is a cumulative snapshot written to a new UFVK-derived slot
(`archive-v1:1`, `archive-v1:2`, ...); existing slot objects cannot be updated.
A create conflict is resolved by reading the winning slot, merging it locally,
and creating the following slot. Consequently each slot has an unrelated
public key and object ID at rest.

Activity deletion is installation-local. Deleted IDs are suppressed only in
local secure metadata, never uploaded as tombstones, and never remove a remote
archive record. Re-importing on another installation can therefore restore a
locally deleted activity.

The rotating identifiers reduce durable database linkability. They do not
prevent an online service from correlating closely timed requests by network
metadata; Tor routing and minimal request logging remain separate controls.

## Limits and errors

The protocol primitive limits plaintext to 256 KiB, which bounds ciphertext
to plaintext plus the AEAD tag. Servers apply the encoded limits before base64
decoding, cap total objects and outstanding challenges, and use generic
`400`, `401`, `404`, `409`, `413`, and `429` responses without echoing opaque
payloads or cryptographic material into logs.

The in-process executable reference is
`InMemoryPrivateStateRemoteStore`. It is for contract tests only and is not a
production persistence or rate-limiting implementation.

## App endpoint configuration

Production builds default to
`https://functions.vizor.cash/api/private-state/v1`. A local server can be
selected at build time; plaintext HTTP always requires a separate explicit
opt-in so a production endpoint cannot silently downgrade:

```bash
fvm flutter run \
  --dart-define=VIZOR_PRIVATE_STATE_BASE_URL=http://127.0.0.1:3000/api/private-state/v1 \
  --dart-define=VIZOR_PRIVATE_STATE_AUDIENCE=http://localhost:3000/api/private-state/v1 \
  --dart-define=VIZOR_PRIVATE_STATE_ALLOW_INSECURE_HTTP=true
```

iOS Simulator can use host loopback. Android Emulator normally uses
`10.0.2.2`; a physical device uses the development machine's reachable LAN
address. Mobile commands must also include the repository's required
`VIZOR_FORM_FACTOR=mobile` define.

## Local app-server contract test

The cross-repository HTTP contract test is tagged `external-service` and is
skipped by default. With the Lambda server's memory-backed development mode
running on port 3000, invoke it explicitly:

```bash
fvm flutter test \
  --tags external-service \
  --run-skipped \
  --dart-define=VIZOR_PRIVATE_STATE_INTEGRATION_URL=http://127.0.0.1:3000/api/private-state/v1 \
  --dart-define=VIZOR_PRIVATE_STATE_INTEGRATION_AUDIENCE=http://localhost:3000/api/private-state/v1 \
  test/core/private_state_sync/private_state_http_local_integration_test.dart
```

The test also exits before network access when the URL define is absent, even
if a broad `--run-skipped` command overrides the tag's default skip.
