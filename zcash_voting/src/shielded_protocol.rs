use orchard::bundle::BundleVersion;
use orchard::note::NoteVersion;
use zcash_protocol::consensus::{BlockHeight, BranchId, Parameters};

use crate::types::VotingError;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum VotingShieldedProtocol {
    #[cfg(zcash_unstable = "nu6.3")]
    Ironwood,
}

impl VotingShieldedProtocol {
    pub(crate) fn for_branch_id(_branch_id: BranchId) -> Result<Self, VotingError> {
        #[cfg(zcash_unstable = "nu6.3")]
        if matches!(_branch_id, BranchId::Nu6_3) {
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
        #[cfg(zcash_unstable = "nu6.3")]
        match self {
            Self::Ironwood => BundleVersion::ironwood_v3(),
        }

        #[cfg(not(zcash_unstable = "nu6.3"))]
        match self {}
    }

    pub(crate) fn note_version(self) -> NoteVersion {
        #[cfg(zcash_unstable = "nu6.3")]
        match self {
            Self::Ironwood => NoteVersion::V3,
        }

        #[cfg(not(zcash_unstable = "nu6.3"))]
        match self {}
    }

    pub(crate) fn pool(self) -> &'static str {
        #[cfg(zcash_unstable = "nu6.3")]
        match self {
            Self::Ironwood => "ironwood",
        }

        #[cfg(not(zcash_unstable = "nu6.3"))]
        match self {}
    }

    pub(crate) fn name(self) -> &'static str {
        #[cfg(zcash_unstable = "nu6.3")]
        match self {
            Self::Ironwood => "Ironwood",
        }

        #[cfg(not(zcash_unstable = "nu6.3"))]
        match self {}
    }
}
