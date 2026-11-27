//! Wallet list pictures (contracts-v1 §12.3): a strict WebP decode in pure
//! Rust (`image-webp` forbids unsafe code), so a malformed picture in a
//! signed list never reaches a platform image decoder (plan CMP-14).

use std::io::Cursor;

use image_webp::WebPDecoder;
use zcash_vote_delegate::MAX_LIST_PICTURE_BYTES;

/// Largest picture the decoder reads, in bytes: the wallet list's own cap.
pub(crate) const MAX_PICTURE_BYTES: usize = MAX_LIST_PICTURE_BYTES;

/// Edge of every picture, in pixels: config CI admits only 128 px pictures
/// to a wallet list.
pub(crate) const PICTURE_EDGE: u32 = 128;

/// Why a picture is refused. Vizor then draws the identicon.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum PictureError {
    /// Larger than [`MAX_PICTURE_BYTES`].
    TooLarge,
    /// Not a WebP the decoder reads.
    Malformed,
    /// Not [`PICTURE_EDGE`] pixels square.
    WrongSize,
    /// Animated, or carrying animation frames.
    Animated,
    /// Carries ICC, EXIF or XMP metadata, which the decoder never applies.
    Metadata,
}

/// A decoded picture: rows top to bottom, 4 bytes per pixel, RGBA with
/// premultiplied alpha, as Flutter's `PixelFormat.rgba8888` takes it.
#[derive(Debug)]
pub(crate) struct Picture {
    pub(crate) width: u32,
    pub(crate) height: u32,
    pub(crate) rgba: Vec<u8>,
}

/// Decodes `webp` within the caps above.
pub(crate) fn decode(webp: &[u8]) -> Result<Picture, PictureError> {
    if webp.len() > MAX_PICTURE_BYTES {
        return Err(PictureError::TooLarge);
    }
    let mut decoder = WebPDecoder::new(Cursor::new(webp)).map_err(|_| PictureError::Malformed)?;
    if decoder.dimensions() != (PICTURE_EDGE, PICTURE_EDGE) || !lossy_frames_fit(webp) {
        return Err(PictureError::WrongSize);
    }
    if decoder.is_animated() || decoder.num_frames() > 0 {
        return Err(PictureError::Animated);
    }
    // With no allowance, a metadata read fails before copying its chunk, so
    // this only asks whether one is present.
    decoder.set_memory_limit(0);
    let metadata = [
        decoder.icc_profile(),
        decoder.exif_metadata(),
        decoder.xmp_metadata(),
    ];
    if metadata.iter().any(|chunk| !matches!(chunk, Ok(None))) {
        return Err(PictureError::Metadata);
    }
    let size = decoder
        .output_buffer_size()
        .ok_or(PictureError::Malformed)?;
    let mut pixels = vec![0; size];
    decoder
        .read_image(&mut pixels)
        .map_err(|_| PictureError::Malformed)?;
    let rgba = if decoder.has_alpha() {
        premultiply(pixels)
    } else {
        pixels
            .chunks_exact(3)
            .flat_map(|rgb| [rgb[0], rgb[1], rgb[2], u8::MAX])
            .collect()
    };
    Ok(Picture {
        width: PICTURE_EDGE,
        height: PICTURE_EDGE,
        rgba,
    })
}

/// Whether every top-level lossy (`VP8 `) chunk's frame header declares the
/// picture's edge. image-webp sizes its frame buffers from that header
/// before comparing it with an extended file's canvas, so a larger claim is
/// refused unread.
fn lossy_frames_fit(webp: &[u8]) -> bool {
    let edge = |low: u8, high: u8| u32::from(u16::from_le_bytes([low, high]) & 0x3FFF);
    let mut at: usize = 12;
    while let Some(header) = webp.get(at..at.saturating_add(8)) {
        // A frame header too short to read fails decoding before allocating.
        if &header[..4] == b"VP8 " {
            if let Some(dims) = webp.get(at + 14..at + 18) {
                if (edge(dims[0], dims[1]), edge(dims[2], dims[3])) != (PICTURE_EDGE, PICTURE_EDGE)
                {
                    return false;
                }
            }
        }
        let size = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
        at = at
            .saturating_add(8)
            .saturating_add(size)
            .saturating_add(size % 2);
    }
    true
}

/// Scales each colour channel by its pixel's alpha, rounding to nearest.
fn premultiply(mut rgba: Vec<u8>) -> Vec<u8> {
    for pixel in rgba.chunks_exact_mut(4) {
        let alpha = u16::from(pixel[3]);
        for channel in &mut pixel[..3] {
            *channel = ((u16::from(*channel) * alpha + 127) / 255) as u8;
        }
    }
    rgba
}

#[cfg(test)]
mod tests {
    use super::*;
    use image_webp::{ColorType, WebPEncoder};

    /// A test pattern: a colour gradient whose top 16 rows are half
    /// transparent.
    fn pattern(width: u32, height: u32) -> Vec<u8> {
        (0..height)
            .flat_map(|y| {
                (0..width).flat_map(move |x| {
                    let alpha = if y < 16 { 0x80 } else { 0xFF };
                    [(x * 2) as u8, (y * 2) as u8, 0x40, alpha]
                })
            })
            .collect()
    }

    /// `pixels` as a lossless WebP from image-webp's encoder.
    fn encode(pixels: &[u8], width: u32, height: u32, color: ColorType) -> Vec<u8> {
        let mut webp = Vec::new();
        WebPEncoder::new(&mut webp)
            .encode(pixels, width, height, color)
            .unwrap();
        webp
    }

    /// A 128 px picture of [`pattern`].
    fn picture() -> Vec<u8> {
        encode(&pattern(128, 128), 128, 128, ColorType::Rgba8)
    }

    /// A RIFF chunk holding `payload`, padded to an even length.
    fn chunk(fourcc: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut out = fourcc.to_vec();
        out.extend((payload.len() as u32).to_le_bytes());
        out.extend(payload);
        if payload.len() % 2 == 1 {
            out.push(0);
        }
        out
    }

    /// A WebP file of `chunks`.
    fn riff(chunks: &[Vec<u8>]) -> Vec<u8> {
        let body = chunks.concat();
        [
            b"RIFF".to_vec(),
            ((body.len() + 4) as u32).to_le_bytes().to_vec(),
            b"WEBP".to_vec(),
            body,
        ]
        .concat()
    }

    /// An extended-format header with `flags` over a 128 px canvas.
    fn vp8x(flags: u8) -> Vec<u8> {
        let [low, high, top, _] = (PICTURE_EDGE - 1).to_le_bytes();
        chunk(b"VP8X", &[flags, 0, 0, 0, low, high, top, low, high, top])
    }

    /// The `VP8L` bitstream inside a simple lossless file.
    fn bitstream(webp: &[u8]) -> &[u8] {
        assert_eq!(&webp[12..16], b"VP8L");
        let size = u32::from_le_bytes(webp[16..20].try_into().unwrap()) as usize;
        &webp[20..20 + size]
    }

    /// A lossy frame header declaring `edge` square, then filler.
    fn lossy_frame(edge: u16) -> Vec<u8> {
        let [low, high] = edge.to_le_bytes();
        [
            vec![0x10, 0, 0, 0x9d, 0x01, 0x2a, low, high, low, high],
            vec![0; 32],
        ]
        .concat()
    }

    #[test]
    fn decodes_a_picture_to_premultiplied_rgba() {
        let pixels = pattern(128, 128);
        let webp = picture();
        let decoded = decode(&webp).unwrap();
        assert_eq!((decoded.width, decoded.height), (128, 128));
        assert_eq!(decoded.rgba.len(), 128 * 128 * 4);
        let at = |x: usize, y: usize| (y * 128 + x) * 4..(y * 128 + x) * 4 + 4;
        assert_eq!(decoded.rgba[at(10, 20)], pixels[at(10, 20)]);
        let source = &pixels[at(100, 2)];
        let premultiplied = |channel: u8| ((u16::from(channel) * 0x80 + 127) / 255) as u8;
        assert_eq!(
            decoded.rgba[at(100, 2)],
            [
                premultiplied(source[0]),
                premultiplied(source[1]),
                premultiplied(source[2]),
                0x80
            ]
        );
    }

    #[test]
    fn an_opaque_picture_gets_full_alpha() {
        let rgb = pattern(128, 128)
            .chunks_exact(4)
            .flat_map(|pixel| [pixel[0], pixel[1], pixel[2]])
            .collect::<Vec<_>>();
        let webp = encode(&rgb, 128, 128, ColorType::Rgb8);
        let decoded = decode(&webp).unwrap();
        assert!(decoded.rgba.chunks_exact(4).all(|pixel| pixel[3] == 255));
        assert_eq!(decoded.rgba[4..7], rgb[3..6]);
    }

    #[test]
    fn the_extended_format_decodes_without_extras() {
        let simple = picture();
        let extended = riff(&[vp8x(0x10), chunk(b"VP8L", bitstream(&simple))]);
        assert_eq!(
            decode(&extended).unwrap().rgba,
            decode(&simple).unwrap().rgba
        );
    }

    #[test]
    fn garbage_is_refused() {
        assert_eq!(
            decode(b"not a picture").unwrap_err(),
            PictureError::Malformed
        );
    }

    #[test]
    fn oversized_input_is_refused_unread() {
        let mut webp = picture();
        webp.resize(MAX_PICTURE_BYTES + 1, 0);
        assert_eq!(decode(&webp).unwrap_err(), PictureError::TooLarge);
    }

    #[test]
    fn other_dimensions_are_refused() {
        for (width, height) in [(64, 64), (128, 127), (129, 128), (256, 256)] {
            let webp = encode(&pattern(width, height), width, height, ColorType::Rgba8);
            assert_eq!(
                decode(&webp).unwrap_err(),
                PictureError::WrongSize,
                "{width}x{height}"
            );
        }
    }

    #[test]
    fn a_lossy_frame_larger_than_its_canvas_is_refused_unread() {
        let claimed = riff(&[vp8x(0), chunk(b"VP8 ", &lossy_frame(0x3FFF))]);
        assert_eq!(decode(&claimed).unwrap_err(), PictureError::WrongSize);
        // A frame that fits gets past the size check and fails as data.
        let filler = riff(&[vp8x(0), chunk(b"VP8 ", &lossy_frame(128))]);
        assert_eq!(decode(&filler).unwrap_err(), PictureError::Malformed);
    }

    #[test]
    fn corrupt_bytes_are_refused() {
        let webp = picture();
        let mut signature = webp.clone();
        signature[8..12].copy_from_slice(b"WEBQ");
        let mut bitstream = webp.clone();
        bitstream[20] ^= 0xFF;
        for corrupt in [
            webp[..webp.len() / 2].to_vec(),
            webp[..11].to_vec(),
            signature,
            bitstream,
            Vec::new(),
        ] {
            assert_eq!(decode(&corrupt).unwrap_err(), PictureError::Malformed);
        }
    }

    #[test]
    fn animation_is_refused() {
        let frame_data = chunk(b"VP8L", bitstream(&picture()));
        let [low, high, top, _] = (PICTURE_EDGE - 1).to_le_bytes();
        let frame = [
            vec![
                0, 0, 0, 0, 0, 0, low, high, top, low, high, top, 100, 0, 0, 0,
            ],
            frame_data.clone(),
        ]
        .concat();
        let animated = riff(&[
            vp8x(0x12),
            chunk(b"ANIM", &[0, 0, 0, 0, 0, 0]),
            chunk(b"ANMF", &frame),
        ]);
        let reader = WebPDecoder::new(Cursor::new(&animated)).unwrap();
        assert!(reader.is_animated() && reader.num_frames() == 1);
        assert_eq!(decode(&animated).unwrap_err(), PictureError::Animated);
        // A frame without the animation flag is refused as well.
        let unflagged = riff(&[vp8x(0x10), chunk(b"ANMF", &frame), frame_data]);
        assert_eq!(decode(&unflagged).unwrap_err(), PictureError::Animated);
    }

    #[test]
    fn metadata_is_refused() {
        for kind in ["icc", "exif", "xmp"] {
            let mut webp = Vec::new();
            let mut encoder = WebPEncoder::new(&mut webp);
            match kind {
                "icc" => encoder.set_icc_profile(vec![1; 4]),
                "exif" => encoder.set_exif_metadata(vec![1; 4]),
                _ => encoder.set_xmp_metadata(vec![1; 4]),
            }
            encoder
                .encode(&pattern(128, 128), 128, 128, ColorType::Rgba8)
                .unwrap();
            assert_eq!(decode(&webp).unwrap_err(), PictureError::Metadata, "{kind}");
        }
    }
}
