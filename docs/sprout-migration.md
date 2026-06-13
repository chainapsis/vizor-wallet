# Sprout Migration Support

Issue: [#228](https://github.com/chainapsis/vizor-wallet/issues/228)

## Goal

Add an advanced feature that lets users with legacy Sprout funds download the
Sprout parameters and migrate those funds into the modern Orchard pool (with
Sapling as a possible intermediate step).

## Current State

- Vizor supports transparent, Sapling, Orchard, and Unified Addresses.
- `validate_address` explicitly rejects Sprout addresses.
- Sapling proving parameters (`sapling-spend.params` and `sapling-output.params`)
  are downloaded on demand; Orchard requires no trusted-setup parameters.

## High-Level Plan

1. **Parameter download**
   - Download `sprout-proving.key` and `sprout-verifying.key` from a trusted
     Zcash mirror (e.g., `https://download.z.cash/downloads/`).
   - Verify file integrity with published SHA-256 checksums.
   - Cache the files in a well-known directory (similar to Sapling params).

2. **Sprout viewing support**
   - Allow Sprout keys to be imported for migration only.
   - Detect Sprout notes during a limited scan or via migration-specific RPCs.

3. **Migration transaction**
   - Build a transaction that spends Sprout notes and creates Orchard (or
     Sapling) notes.
   - Re-use the existing proposal/execution flow where possible.
   - Gate the UI behind an "Advanced" or "Legacy Sprout migration" section.

## Open Questions

- Total size of Sprout parameters and whether mobile storage/network limits
  make this feasible.
- Whether `librustzcash` exposes the necessary Sprout note detection and
  spend APIs.
- Whether Sprout-to-Orchard migration needs to be done directly or via a
  Sprout-to-Sapling step.
- How to communicate the trusted-setup implications of Sprout parameters to
  users.

## Related Code

- `rust/src/wallet/sync/mod.rs` — address validation
- `rust/src/wallet/sync.rs` — send/proposal flow
- `lib/src/features/send/screens/send_screen.dart` — send UI and param download
