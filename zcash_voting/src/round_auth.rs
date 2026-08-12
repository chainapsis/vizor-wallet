//! Canonical payloads signed by dynamic-config round attestations.

use crate::config::PirLayout;

/// Dynamic-config authentication version using [`RoundAuthPayloadV2`].
pub const ROUND_AUTH_VERSION_V2: u32 = 2;

const ROUND_AUTH_DOMAIN_TAG_V2: [u8; 33] = *b"zcash-shielded-vote:round-auth:v2";

/// Typed round-auth v2 signing payload.
///
/// Its fixed-width encoding is
/// `domain || round_id || ea_pk || pir_depth || tier0_layers || tier1_layers`,
/// with each `u32` encoded little-endian. This preserves the original v2 wire
/// format while giving every signed field an explicit schema.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RoundAuthPayloadV2 {
    domain: [u8; 33],
    round_id: [u8; 32],
    ea_pk: [u8; 32],
    pir_depth: u32,
    tier0_layers: u32,
    tier1_layers: u32,
}

impl RoundAuthPayloadV2 {
    /// Constructs the payload for a round and its advertised PIR layout.
    pub fn new(round_id: [u8; 32], ea_pk: [u8; 32], pir_layout: PirLayout) -> Self {
        Self {
            domain: ROUND_AUTH_DOMAIN_TAG_V2,
            round_id,
            ea_pk,
            pir_depth: pir_layout.pir_depth,
            tier0_layers: pir_layout.tier0_layers,
            tier1_layers: pir_layout.tier1_layers,
        }
    }

    /// Returns the canonical fixed-width bytes to sign or verify.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(33 + 32 + 32 + 12);
        bytes.extend_from_slice(&self.domain);
        bytes.extend_from_slice(&self.round_id);
        bytes.extend_from_slice(&self.ea_pk);
        bytes.extend_from_slice(&self.pir_depth.to_le_bytes());
        bytes.extend_from_slice(&self.tier0_layers.to_le_bytes());
        bytes.extend_from_slice(&self.tier1_layers.to_le_bytes());
        bytes
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encoding_matches_round_auth_v2_wire_format() {
        let round_id = [1u8; 32];
        let ea_pk = [2u8; 32];
        let layout = PirLayout {
            pir_depth: 19,
            tier0_layers: 12,
            tier1_layers: 7,
        };

        let mut expected = ROUND_AUTH_DOMAIN_TAG_V2.to_vec();
        expected.extend_from_slice(&round_id);
        expected.extend_from_slice(&ea_pk);
        expected.extend_from_slice(&19u32.to_le_bytes());
        expected.extend_from_slice(&12u32.to_le_bytes());
        expected.extend_from_slice(&7u32.to_le_bytes());

        assert_eq!(
            RoundAuthPayloadV2::new(round_id, ea_pk, layout).to_bytes(),
            expected
        );
    }
}
