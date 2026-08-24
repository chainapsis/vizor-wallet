# Private state sync HTTP protocol v1

This protocol stores only opaque, client-encrypted objects. The service never
receives a UFVK, account UUID, plaintext, voting round ID, or feature schema.
JSON integers are unsigned and JSON byte strings use unpadded base64url.

## Identity and routes

`object_id` is `SHA-256("Vizor private state object ID v1" || auth_public_key)`
as produced by the client protocol. It is the only stable server-side object
identifier.

- `POST /v1/objects/{object_id}/challenge`
- `GET /v1/objects/{object_id}`
- `PUT /v1/objects/{object_id}`

Every response sets `Cache-Control: no-store`. Requests and logs must not add
wallet addresses, IP-derived account identifiers, or analytics identifiers to
the object record.

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
Rust `private_state_sync` module. GET signs SHA-256 of empty bytes. PUT signs
the submitted envelope hash.

The server rejects requests unless the challenge exists, is unused, is bound
to the same object, the signed expiry is after the server clock and no later
than challenge expiry, the audience is exact, the object ID is self-certifying,
and the signature is valid.

## GET

Success returns `200` and the encrypted envelope. An authenticated missing
object returns `404`. An unauthenticated caller cannot distinguish missing from
existing objects.

## PUT and atomic CAS

The body contains:

```json
{
  "expected": {
    "revision": 4,
    "envelope_hash_base64": "..."
  },
  "envelope": { "protocol_version": 1 }
}
```

`expected: null` means create-if-absent. Within one serialized database
transaction the server:

1. consumes and verifies the request authorization;
2. reads the current envelope;
3. compares its revision and authenticated envelope hash with `expected`;
4. returns `409` on mismatch without changing storage;
5. verifies the new signed envelope and requires revision 1 for creation, or
   exactly `current.revision + 1` with `previous_hash` equal to the current
   envelope hash;
6. stores the envelope and returns `204`.

The unsigned `expected` field is only a concurrency hint. Direct-successor
verification is mandatory to prevent replaying an older correctly signed
envelope while replacing its CAS precondition.

## Limits and errors

The protocol primitive limits plaintext to 256 KiB, which bounds ciphertext
to plaintext plus the AEAD tag. Servers apply the encoded limits before base64
decoding, cap total objects and outstanding challenges, and use generic
`400`, `401`, `404`, `409`, `413`, and `429` responses without echoing opaque
payloads or cryptographic material into logs.

The in-process executable reference is
`InMemoryPrivateStateRemoteStore`. It is for contract tests only and is not a
production persistence or rate-limiting implementation.
