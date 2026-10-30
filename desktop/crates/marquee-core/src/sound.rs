//! The shutter sound, synthesized so the repo needs no audio files: two short, filtered
//! noise clicks like a camera shutter opening and closing, as a 16-bit mono WAV.

const RATE: u32 = 22_050;

/// A complete WAV file (header and samples), ready to hand to the system player.
pub fn shutter_wav() -> Vec<u8> {
    let len = (RATE as f32 * 0.16) as usize;
    let mut seed: u32 = 0x9E37_79B9;
    let mut noise = move || {
        // xorshift: deterministic, so the sound is the same every time.
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        (seed as f32 / u32::MAX as f32) * 2.0 - 1.0
    };
    let click = |t: f32, start: f32, gain: f32, n: f32| {
        let dt = t - start;
        if dt < 0.0 {
            0.0
        } else {
            let tone = (dt * 2.0 * std::f32::consts::PI * 1_650.0).sin() * (-dt / 0.012).exp() * 0.35;
            gain * (n * (-dt / 0.006).exp() + tone)
        }
    };

    let mut samples = Vec::with_capacity(len);
    let mut low = 0.0f32;
    for i in 0..len {
        let t = i as f32 / RATE as f32;
        let n = noise();
        // A gentle low-pass takes the hiss off the noise.
        low += 0.45 * (n - low);
        let v = click(t, 0.0, 0.75, low) + click(t, 0.065, 0.5, low);
        samples.push((v.clamp(-1.0, 1.0) * i16::MAX as f32) as i16);
    }

    let data_len = (samples.len() * 2) as u32;
    let mut wav = Vec::with_capacity(44 + data_len as usize);
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + data_len).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16u32.to_le_bytes()); // fmt chunk size
    wav.extend_from_slice(&1u16.to_le_bytes()); // PCM
    wav.extend_from_slice(&1u16.to_le_bytes()); // mono
    wav.extend_from_slice(&RATE.to_le_bytes());
    wav.extend_from_slice(&(RATE * 2).to_le_bytes()); // bytes per second
    wav.extend_from_slice(&2u16.to_le_bytes()); // block align
    wav.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&data_len.to_le_bytes());
    for s in samples {
        wav.extend_from_slice(&s.to_le_bytes());
    }
    wav
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_a_valid_short_wav() {
        let wav = shutter_wav();
        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(&wav[8..16], b"WAVEfmt ");
        let riff_len = u32::from_le_bytes(wav[4..8].try_into().unwrap()) as usize;
        assert_eq!(riff_len + 8, wav.len());
        let data_len = u32::from_le_bytes(wav[40..44].try_into().unwrap()) as usize;
        assert_eq!(data_len + 44, wav.len());
        // About 0.16 seconds, and not silent.
        assert!((3_000..4_000).contains(&(data_len / 2)));
        assert!(wav[44..].chunks(2).any(|s| i16::from_le_bytes([s[0], s[1]]).abs() > 8_000));
    }

    #[test]
    fn is_the_same_every_time() {
        assert_eq!(shutter_wav(), shutter_wav());
    }
}
