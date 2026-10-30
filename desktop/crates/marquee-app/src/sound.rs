//! Plays the shutter sound (synthesized in marquee-core) without blocking.

#[cfg(windows)]
pub fn shutter() {
    use std::sync::OnceLock;
    use windows_sys::Win32::Media::Audio::{PlaySoundW, SND_ASYNC, SND_MEMORY, SND_NODEFAULT};

    // PlaySound reads the bytes while it plays, so they have to live for the whole run.
    static WAV: OnceLock<Vec<u8>> = OnceLock::new();
    let wav = WAV.get_or_init(marquee_core::sound::shutter_wav);
    // SAFETY: with SND_MEMORY the first argument points at a complete WAV image, which stays
    // alive for the life of the process.
    unsafe {
        PlaySoundW(wav.as_ptr().cast(), std::ptr::null_mut(), SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
    }
}

#[cfg(not(windows))]
pub fn shutter() {}
