# Voting proof A/B benchmark

This standalone harness compares the ZKP 1 and ZKP 2 proof paths used by
`voting-circuits` 0.10.0-rc.1, which is the version selected by Vizor PR 506.
It builds two independent dependency graphs:

- `upstream` pins PR 506's relevant crates.io circuit versions, including
  `orchard` 0.15.4 and `halo2_proofs` 0.3.2.
- `zakura` applies a root `[patch.crates-io]` for every Zakura crate used by
  this isolated circuit graph at revision
  `7490b608930de93ee69ade037c7aea4bf8b29f32`.

Run both release builds and print the warmed proof-time comparison with:

```sh
./compare.sh
```

The defaults are one warmup and five measured proofs per circuit. They can be
overridden without editing the harness:

```sh
SAMPLES=10 WARMUPS=1 ./compare.sh
```

The default `ORDER=ab` runs upstream then Zakura for ZKP 1 and reverses that
order for ZKP 2. Use `ORDER=ba` for the complementary order when confirming a
result against thermal or run-order effects.

Each run writes `comparison.json`, the raw JSON reports, and resolved dependency
sources under `results/<timestamp>/`. The script builds both variants before
timing and runs the four benchmarks sequentially. Avoid other CPU-heavy work
during the timed runs.

ZKP 1 times `create_delegation_proof` after constructing its fixture and
warming its cached parameters and keys. ZKP 2's public API does not expose the
constructed circuit separately, so it times `build_vote_proof_from_delegation`
after warming its cached parameters and keys. That includes the small amount
of witness construction surrounding the Halo2 proof. Every measured lane also
verifies its final proof.
