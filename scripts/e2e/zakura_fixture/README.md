# Vendored Zakura regtest fixture

These files are copied byte-for-byte from the contributor-fork commit
[`piatoss3612/zakura@5ecafcf`](https://github.com/piatoss3612/zakura/commit/5ecafcfdb43cf42f34c8046f09c6d874b567daa4).
They are not an official Zakura release. Vizor no longer reads that fork at run
time; this directory is the only source.

| Vendored path | Fork path | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `regtest_fixture.py` | `scripts/regtest_fixture.py` | 98120 | `a37f5913fbd3322a4d9afbc4a1bc27c86409835c7eb5295afe6af4ed440c8fc1` |
| `regtest_fixture_smoke.py` | `scripts/regtest_fixture_smoke.py` | 9794 | `8602ee81f24d209d745e99fa5bfb475c44f7c960b238bec53e33795eb81b612e` |
| `tests/test_regtest_fixture.py` | `scripts/tests/test_regtest_fixture.py` | 98561 | `81f449821caecb62495cb234effaffd68b2d8e14d4f1e39aa0211e10ca9208c4` |
| `tests/test_regtest_fixture_smoke.py` | `scripts/tests/test_regtest_fixture_smoke.py` | 24633 | `1924444b8cb49bd5c5829cd28c6f003c24e6a4a45e36627cac54461bf93486be` |

The empty `__init__.py` files only make the tests discoverable from
`scripts/e2e`. `../zakura_fixture_source.py` pins the helper's size, SHA-256 and
node/lightwalletd image digests; changing `regtest_fixture.py` requires a
reviewed update of that pin.

The tests mock Docker and run offline:

```bash
python3 -B -m unittest discover -s scripts/e2e/zakura_fixture/tests
```

`regtest_fixture_smoke.py` is the fork's manual Docker smoke tool. It starts
real containers and is not part of the E2E runner.
