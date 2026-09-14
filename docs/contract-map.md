# Agent contract graph

Read Mermaid source as a text map when cross-contract ownership is unclear.
Normal work can go directly to the relevant contract or routing index.

From the repository root:

```sh
# Find domain/shared/platform groups without expanding every document.
python3 scripts/contract-graph/generate.py --overview

# Read a domain's own documents and their direct outgoing references.
python3 scripts/contract-graph/generate.py --scope domains/donation

# Find direct consumers when changing a shared contract.
python3 scripts/contract-graph/generate.py --scope references/transactions/proposal-release.md --incoming
```

Scopes are file or directory paths relative to `docs/contracts/`; `AGENTS.md`
is also supported. Output is Markdown containing Mermaid, printed to stdout.
Only the selected scope's direct links are expanded. `--incoming` also includes
direct referrers; it does not recursively load their other dependencies.

- Solid edges are index routes; dashed edges are document references.
- Explicit short read conditions come from the original link context. Other
  edges show the link label and source line for checking the owning document.
- References are not runtime calls, execution order, or mandatory reading.
  Incoming links identify documented consumers, not every code-level impact.

The generator reads current Markdown links; there is no second graph manifest,
saved graph snapshot, browser UI, or rendering dependency. Source/test files
are not expanded into graph nodes. The [generator](../scripts/contract-graph/generate.py)
validates document paths and anchors before printing.
