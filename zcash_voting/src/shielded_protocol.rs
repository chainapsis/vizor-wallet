use orchard::bundle::BundleVersion;
use orchard::note::NoteVersion;
use zcash_protocol::consensus::{BlockHeight, BranchId, Parameters};

use crate::types::VotingError;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum VotingShieldedProtocol {
    Ironwood,
}

impl VotingShieldedProtocol {
    pub(crate) fn for_branch_id(branch_id: BranchId) -> Result<Self, VotingError> {
        if matches!(branch_id, BranchId::Nu6_3) {
            return Ok(Self::Ironwood);
        }

        Err(VotingError::InvalidInput {
            message: "zcash voting only supports Ironwood / NU6.3 shielded voting notes"
                .to_string(),
        })
    }

    pub(crate) fn for_height<P: Parameters>(
        params: &P,
        height: BlockHeight,
    ) -> Result<Self, VotingError> {
        Self::for_branch_id(BranchId::for_height(params, height))
    }

    pub(crate) fn bundle_version(self) -> BundleVersion {
        match self {
            Self::Ironwood => BundleVersion::ironwood_v3(),
        }
    }

    pub(crate) fn note_version(self) -> NoteVersion {
        match self {
            Self::Ironwood => NoteVersion::V3,
        }
    }

    pub(crate) fn pool(self) -> &'static str {
        match self {
            Self::Ironwood => "ironwood",
        }
    }

    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::Ironwood => "Ironwood",
        }
    }
}
