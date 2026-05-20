use ff::{PrimeField, PrimeFieldBits};
use group::{Curve, GroupEncoding};
use halo2_gadgets::poseidon::primitives::{self as poseidon, ConstantLength, P128Pow5T3};
use orchard::{
    constants::{
        fixed_bases::{COMMIT_IVK_PERSONALIZATION, NOTE_COMMITMENT_PERSONALIZATION},
        L_ORCHARD_BASE, L_VALUE,
    },
    keys::{FullViewingKey, Scope, SpendValidatingKey},
    note::{RandomSeed, Rho},
    spec::NonIdentityPallasPoint,
    value::NoteValue,
};
use pasta_curves::{
    arithmetic::{CurveAffine, CurveExt},
    pallas,
};

use crate::types::VotingError;

pub(crate) struct SyntheticPaddingNoteParts {
    pub cmx: [u8; 32],
    pub nullifier: [u8; 32],
}

fn point_x(point: &pallas::Point) -> Result<pallas::Base, VotingError> {
    point
        .to_affine()
        .coordinates()
        .map(|coords| *coords.x())
        .into_option()
        .ok_or_else(|| VotingError::Internal {
            message: "synthetic padding point is identity".to_string(),
        })
}

fn byte_bits(bytes: [u8; 32]) -> impl Iterator<Item = bool> {
    bytes
        .into_iter()
        .flat_map(|byte| (0..8).map(move |bit| ((byte >> bit) & 1) == 1))
}

fn u64_bits(value: u64) -> impl Iterator<Item = bool> {
    value
        .to_le_bytes()
        .into_iter()
        .flat_map(|byte| (0..8).map(move |bit| ((byte >> bit) & 1) == 1))
}

fn poseidon_hash_2(a: pallas::Base, b: pallas::Base) -> pallas::Base {
    poseidon::Hash::<_, P128Pow5T3, ConstantLength<2>, 3, 2>::init().hash([a, b])
}

fn base_to_scalar(value: pallas::Base) -> pallas::Scalar {
    pallas::Scalar::from_repr(value.to_repr()).expect("Pallas base embeds in scalar field")
}

fn external_ivk_scalar(
    fvk: &FullViewingKey,
    ak: &SpendValidatingKey,
) -> Result<pallas::Scalar, VotingError> {
    let ak_point: pallas::Point = ak.into();
    let ak_x = point_x(&ak_point)?;
    let rivk = fvk.rivk(Scope::External).inner();
    let domain = sinsemilla::CommitDomain::new(COMMIT_IVK_PERSONALIZATION);
    let ivk = domain
        .short_commit(
            std::iter::empty()
                .chain(ak_x.to_le_bits().iter().by_vals().take(L_ORCHARD_BASE))
                .chain(
                    fvk.nk()
                        .inner()
                        .to_le_bits()
                        .iter()
                        .by_vals()
                        .take(L_ORCHARD_BASE),
                ),
            &rivk,
        )
        .into_option()
        .ok_or_else(|| VotingError::Internal {
            message: "external ivk commitment bottomed out".to_string(),
        })?;
    Ok(base_to_scalar(ivk))
}

fn non_identity_padding_point(
    point: pallas::Point,
    slot_index: usize,
    component: &'static str,
) -> Result<NonIdentityPallasPoint, VotingError> {
    NonIdentityPallasPoint::from_bytes(&point.to_affine().to_bytes())
        .into_option()
        .ok_or_else(|| VotingError::Internal {
            message: format!("invalid synthetic padding {component} at slot {slot_index}"),
        })
}

fn padding_points(
    slot_index: usize,
    ivk: pallas::Scalar,
) -> Result<(NonIdentityPallasPoint, NonIdentityPallasPoint), VotingError> {
    const PADDING_PERSONALIZATION: &str = "shielded-vote/padding-v1";

    let slot_index_u32 = u32::try_from(slot_index).map_err(|_| VotingError::InvalidInput {
        message: format!("padding slot index {slot_index} does not fit in u32"),
    })?;
    let g_d_pad =
        pallas::Point::hash_to_curve(PADDING_PERSONALIZATION)(&slot_index_u32.to_le_bytes());
    let pk_d_pad = g_d_pad * ivk;

    Ok((
        non_identity_padding_point(g_d_pad, slot_index, "g_d")?,
        non_identity_padding_point(pk_d_pad, slot_index, "pk_d")?,
    ))
}

fn note_commitment_point(
    g_d: pallas::Point,
    pk_d: pallas::Point,
    value: NoteValue,
    rho: pallas::Base,
    psi: pallas::Base,
    rcm: pallas::Scalar,
) -> Option<pallas::Point> {
    let domain = sinsemilla::CommitDomain::new(NOTE_COMMITMENT_PERSONALIZATION);
    domain
        .commit(
            std::iter::empty()
                .chain(byte_bits(g_d.to_affine().to_bytes()))
                .chain(byte_bits(pk_d.to_affine().to_bytes()))
                .chain(u64_bits(value.inner()).take(L_VALUE))
                .chain(rho.to_le_bits().iter().by_vals().take(L_ORCHARD_BASE))
                .chain(psi.to_le_bits().iter().by_vals().take(L_ORCHARD_BASE)),
            &rcm,
        )
        .into_option()
}

fn derive_note_nullifier(
    nk: pallas::Base,
    rho: pallas::Base,
    psi: pallas::Base,
    cm: pallas::Point,
) -> Result<pallas::Base, VotingError> {
    let k = pallas::Point::hash_to_curve("z.cash:Orchard")(b"K");
    let prf_nf = poseidon_hash_2(nk, rho);
    let scalar = pallas::Scalar::from_repr((prf_nf + psi).to_repr())
        .expect("Pallas base field is smaller than its scalar field");
    point_x(&(k * scalar + cm))
}

/// Reproduces the `voting-circuits` synthetic padding slot derivation.
///
/// Keep this in lockstep with `voting_circuits::delegation::builder` until the
/// circuits crate exposes this as a public helper. Padded slots are not Orchard
/// diversified addresses; using `fvk.address_at(...)` here makes PCZT metadata
/// and PIR precompute cache proofs for the wrong nullifiers.
pub(crate) fn synthetic_padding_note_parts(
    fvk: &FullViewingKey,
    slot_index: usize,
    rho: Rho,
    rseed: RandomSeed,
) -> Result<SyntheticPaddingNoteParts, VotingError> {
    let ak: SpendValidatingKey = fvk.clone().into();
    let ivk = external_ivk_scalar(fvk, &ak)?;
    let (g_d_pad, pk_d_pad) = padding_points(slot_index, ivk)?;
    let psi = rseed.psi(&rho);
    let rcm = rseed.rcm(&rho);
    let cm = note_commitment_point(
        *g_d_pad,
        *pk_d_pad,
        NoteValue::ZERO,
        rho.into_inner(),
        psi,
        rcm.inner(),
    )
    .ok_or_else(|| VotingError::Internal {
        message: format!("synthetic padding note commitment bottomed out at slot {slot_index}"),
    })?;

    Ok(SyntheticPaddingNoteParts {
        cmx: point_x(&cm)?.to_repr(),
        nullifier: derive_note_nullifier(fvk.nk().inner(), rho.into_inner(), psi, cm)?.to_repr(),
    })
}
