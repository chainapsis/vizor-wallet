/// Shared Send-level density for every Keystone signing QR.
///
/// At 140 bytes per fragment, even a maximum-size 32-KiB batch fits within
/// Keystone's 256-fragment budget (235 source fragments).
const keystoneQrFragmentLength = 140;
