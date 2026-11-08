//! Copy Text: reads the text in a capture with Windows' own OCR (`Windows.Media.Ocr`, the
//! engine behind the Snipping Tool's text actions) and decodes any QR codes in it (`rqrr`).
//! What to copy and which links to offer is marquee-core's `RecognizedContent`.

use image::imageops::{self, FilterType};
use marquee_core::recognized::RecognizedContent;
use xcap::image::RgbaImage;

/// Text and QR codes in an image. OCR failing (no OCR language installed, say) is an error
/// only when there's no QR code either.
pub fn recognize(image: &RgbaImage) -> Result<RecognizedContent, String> {
    let codes = qr_codes(image);
    match text(image) {
        Ok(text) => Ok(RecognizedContent { text, codes }),
        Err(e) if !codes.is_empty() => {
            eprintln!("Marquee: OCR failed: {e}");
            Ok(RecognizedContent { text: String::new(), codes })
        }
        Err(e) => Err(e),
    }
}

fn qr_codes(image: &RgbaImage) -> Vec<String> {
    let gray = image::DynamicImage::ImageRgba8(image.clone()).to_luma8();
    let mut prepared = rqrr::PreparedImage::prepare(gray);
    let mut codes: Vec<String> = Vec::new();
    for grid in prepared.detect_grids() {
        if let Ok((_, content)) = grid.decode() {
            if !content.is_empty() && !codes.contains(&content) {
                codes.push(content);
            }
        }
    }
    codes
}

/// Small selections are enlarged before OCR (it reads small text much better), large ones
/// shrunk to the engine's limit.
fn scaled_for_ocr(image: &RgbaImage, max: u32) -> RgbaImage {
    let (w, h) = image.dimensions();
    let long = w.max(h).max(1);
    let factor = if long < 800 { 2.0 } else { 1.0_f64.min(max as f64 / long as f64) };
    if (factor - 1.0).abs() < f64::EPSILON {
        return image.clone();
    }
    let nw = ((w as f64 * factor).round() as u32).clamp(1, max);
    let nh = ((h as f64 * factor).round() as u32).clamp(1, max);
    imageops::resize(image, nw, nh, FilterType::CatmullRom)
}

#[cfg(windows)]
fn text(image: &RgbaImage) -> Result<String, String> {
    use windows::Graphics::Imaging::{BitmapAlphaMode, BitmapPixelFormat, SoftwareBitmap};
    use windows::Media::Ocr::OcrEngine;
    use windows::Security::Cryptography::CryptographicBuffer;
    use windows::Win32::System::WinRT::{RoInitialize, RO_INIT_MULTITHREADED};

    // This runs on a worker thread; WinRT needs it joined to the multithreaded apartment.
    // An "already initialized" error is fine.
    let _ = unsafe { RoInitialize(RO_INIT_MULTITHREADED) };
    let failed = |e: windows::core::Error| format!("Windows couldn't read the text: {}", e.message());
    let engine = OcrEngine::TryCreateFromUserProfileLanguages().map_err(|_| {
        "Windows has no text recognition for your languages. Add a language with its \
         \"Optical character recognition\" feature in Settings → Time & language → Language & region."
            .to_string()
    })?;
    let max = OcrEngine::MaxImageDimension().unwrap_or(2600);
    let scaled = scaled_for_ocr(image, max);
    let (w, h) = scaled.dimensions();
    let mut bgra = scaled.into_raw();
    for pixel in bgra.chunks_exact_mut(4) {
        pixel.swap(0, 2);
    }
    let buffer = CryptographicBuffer::CreateFromByteArray(&bgra).map_err(failed)?;
    let bitmap = SoftwareBitmap::CreateCopyWithAlphaFromBuffer(
        &buffer,
        BitmapPixelFormat::Bgra8,
        w as i32,
        h as i32,
        BitmapAlphaMode::Premultiplied,
    )
    .map_err(failed)?;
    let result = engine.RecognizeAsync(&bitmap).map_err(failed)?.join().map_err(failed)?;
    let mut lines = Vec::new();
    for line in result.Lines().map_err(failed)? {
        lines.push(line.Text().map_err(failed)?.to_string_lossy());
    }
    Ok(lines.join("\n").trim().to_string())
}

#[cfg(not(windows))]
fn text(_image: &RgbaImage) -> Result<String, String> {
    Err("Copy Text isn't available on this system yet.".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn small_images_are_enlarged_and_large_ones_fit_the_limit() {
        let small = RgbaImage::new(300, 100);
        assert_eq!(scaled_for_ocr(&small, 2600).dimensions(), (600, 200));
        let large = RgbaImage::new(5200, 1000);
        assert_eq!(scaled_for_ocr(&large, 2600).dimensions(), (2600, 500));
        let fine = RgbaImage::new(1200, 900);
        assert_eq!(scaled_for_ocr(&fine, 2600).dimensions(), (1200, 900));
    }
}
