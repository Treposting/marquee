//! Writes the app and tray icons to a folder for a look: `cargo run -p marquee-icon --example preview <dir>`.
fn main() {
    let dir = std::path::PathBuf::from(std::env::args().nth(1).unwrap_or_else(|| "icon-preview".into()));
    marquee_icon::write_app_icons(&dir).unwrap();
    for (name, style) in
        [("tray-light.png", marquee_icon::Style::TrayLight), ("tray-dark.png", marquee_icon::Style::TrayDark)]
    {
        marquee_icon::render(64, style).save_png(dir.join(name)).unwrap();
    }
}
