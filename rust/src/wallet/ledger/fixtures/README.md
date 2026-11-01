# Historical Orchard V2 memo fixtures

`orchard_v2_memos.json` contains IO-finalized, unproved PCZTs for the Ledger
memo-display tests. They use deterministic synthetic keys and values; no wallet
or user data is included.

Common intentionally disabled new pre-NU6.3 Orchard proving in commit
`30eeb939123414887642f1cdb60ea59ab13bdf7c`. The generator therefore uses its
unmodified parent `a2aa82ce3d3be56650a3236d9739b2b9285ff831` and wallet-libraries
`3fc2bf443020194c56a71d1f63c0d24002cc9517`. The standalone manifest and lockfile
retain those historical sources without adding them to the application graph.
The JSON records the memo bytes, output value, and serialized PCZT for each case.

Regenerate from this directory:

```sh
cargo run --locked --quiet --manifest-path orchard-v2-generator/Cargo.toml > orchard_v2_memos.json
```

The app tests parse these historical bytes through the current production
signing-plan entry points. Current Orchard V3 and Ironwood cases still use the
current builder.
