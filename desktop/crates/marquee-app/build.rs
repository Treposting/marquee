// Draws the icons Tauri bundles (icons/ is git-ignored), then runs Tauri's build step.
fn main() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("icons");
    if !dir.join("icon.ico").exists() {
        marquee_icon::write_app_icons(&dir).expect("could not write icons");
    }
    tauri_build::build();
}
