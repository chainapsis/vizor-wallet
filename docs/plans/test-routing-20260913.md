# Test execution routing and Receive test separation

Make test commands discoverable through repository documentation and keep
iteration focused without deleting behavioral coverage.

- AGENTS routes test selection to one shared guide. CONTRIBUTING links the same
  guide while retaining mandatory PR checks.
- Shared guidance distinguishes dependency preparation from `--no-pub`, Flutter
  tests from Dart tooling, and token definitions from test tags. Domain guidance
  maps behavior to existing test files and focused/final verification scopes.
- Split Receive view-model, desktop widgets, mobile-sized sheet, and QR export
  groups into separate files. Preserve names, assertions, fixtures, timeouts and
  untagged two-form-factor semantics. Do not implement the benchmark's amountless
  product requirement or change production code.
- Compare pre/post test names, results and skips in desktop and mobile-token
  runs; check targeted analysis/format, documented mobile-screen selection, and
  local Markdown links. Preserve prior changes and all Vizor main refs.

Work branch: `rowan/agent-contract-docs`. Test moves delegated to Sol / Medium;
routing, integration and verification owned by the parent agent. The frozen
Luna/Astra campaigns are historical evidence and remain unchanged. No new model
benchmark, commit, push, or device run is included.

Status: complete on the local work branch.

Validation: scoped formatting and analysis passed. Before and after the split,
85 tests passed with desktop tokens and 85 with mobile tokens, with identical
test-name/result/skip multisets. The mobile-tagged screen added 20 passing checks.
All 44 moved test bodies match after helper renames and formatting. The docs
check covered 102 documents and 635 local links; all 12 graph-parser tests passed.
See [validation evidence](test-routing-20260913-validation.json).

The previous 957-line test is now four files (44 / 426 / 340 / 121 lines) plus
122 lines of shared test support. Test coverage is preserved; these checks do
not measure agent token savings or establish a runtime speedup.
