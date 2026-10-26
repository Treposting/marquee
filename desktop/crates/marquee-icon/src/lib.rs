//! Marquee's icon, drawn from the same geometry as `site/assets/logo.svg` (a 512×512 canvas):
//! a yellow tile with two viewfinder corners, an outlined square and a filled square.

use std::fs::{self, File};
use std::io;
use std::path::Path;

use tiny_skia::{
    Color, FillRule, LineCap, LineJoin, Paint, Path as SkPath, PathBuilder, Pixmap, Rect, Stroke, Transform,
};

fn yellow() -> Color {
    Color::from_rgba8(0xFF, 0xCF, 0x1A, 255)
}

fn ink() -> Color {
    Color::from_rgba8(0x1D, 0x1D, 0x1F, 255)
}

/// Which way the icon is drawn.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Style {
    /// The app icon: ink marks on the yellow tile.
    App,
    /// A tray icon for a dark taskbar: yellow marks, no tile.
    TrayLight,
    /// A tray icon for a light taskbar: ink marks, no tile.
    TrayDark,
}

/// Renders the icon as straight (not premultiplied) RGBA, `size`×`size` pixels.
pub fn render(size: u32, style: Style) -> Pixmap {
    let mut pixmap = Pixmap::new(size, size).expect("non-zero size");
    let scale = size as f32 / 512.0;
    let t = Transform::from_scale(scale, scale);
    let mark = match style {
        Style::App | Style::TrayDark => ink(),
        Style::TrayLight => yellow(),
    };

    if style == Style::App {
        fill(&mut pixmap, &round_rect(16.0, 16.0, 480.0, 480.0, 116.0), yellow(), t);
    }

    // Tray icons have no tile, so the marks grow to fill the square and stay legible at 16 px.
    let t = if style == Style::App {
        t
    } else {
        t.pre_translate(256.0, 256.0).pre_scale(1.3, 1.3).pre_translate(-256.0, -256.0)
    };

    let mut corner = PathBuilder::new();
    corner.move_to(112.0, 196.0);
    corner.line_to(112.0, 128.0);
    corner.quad_to(112.0, 112.0, 128.0, 112.0);
    corner.line_to(196.0, 112.0);
    corner.move_to(400.0, 316.0);
    corner.line_to(400.0, 384.0);
    corner.quad_to(400.0, 400.0, 384.0, 400.0);
    corner.line_to(316.0, 400.0);
    let corners = corner.finish().expect("valid path");
    stroke(&mut pixmap, &corners, mark, 34.0, t);
    stroke(&mut pixmap, &round_rect(166.0, 166.0, 124.0, 124.0, 20.0), mark, 26.0, t);
    fill(&mut pixmap, &round_rect(222.0, 222.0, 124.0, 124.0, 20.0), mark, t);
    pixmap
}

/// Straight RGBA bytes, as tray and window icon APIs want them.
pub fn rgba(size: u32, style: Style) -> Vec<u8> {
    render(size, style)
        .pixels()
        .iter()
        .flat_map(|p| {
            let c = p.demultiply();
            [c.red(), c.green(), c.blue(), c.alpha()]
        })
        .collect()
}

/// Writes the files Tauri's bundler and Windows resources expect: PNGs and a multi-size .ico.
pub fn write_app_icons(dir: &Path) -> io::Result<()> {
    fs::create_dir_all(dir)?;
    for (name, size) in [("32x32.png", 32), ("128x128.png", 128), ("128x128@2x.png", 256), ("icon.png", 512)]
    {
        render(size, Style::App).save_png(dir.join(name)).map_err(io::Error::other)?;
    }
    let mut icon_dir = ico::IconDir::new(ico::ResourceType::Icon);
    for size in [16, 24, 32, 48, 64, 128, 256] {
        let image = ico::IconImage::from_rgba_data(size, size, rgba(size, Style::App));
        icon_dir.add_entry(ico::IconDirEntry::encode(&image)?);
    }
    icon_dir.write(File::create(dir.join("icon.ico"))?)
}

fn round_rect(x: f32, y: f32, w: f32, h: f32, r: f32) -> SkPath {
    let mut pb = PathBuilder::new();
    let (right, bottom) = (x + w, y + h);
    pb.move_to(x + r, y);
    pb.line_to(right - r, y);
    pb.quad_to(right, y, right, y + r);
    pb.line_to(right, bottom - r);
    pb.quad_to(right, bottom, right - r, bottom);
    pb.line_to(x + r, bottom);
    pb.quad_to(x, bottom, x, bottom - r);
    pb.line_to(x, y + r);
    pb.quad_to(x, y, x + r, y);
    pb.close();
    pb.finish().unwrap_or_else(|| PathBuilder::from_rect(Rect::from_xywh(x, y, w, h).expect("valid rect")))
}

fn paint(color: Color) -> Paint<'static> {
    let mut paint = Paint::default();
    paint.set_color(color);
    paint.anti_alias = true;
    paint
}

fn fill(pixmap: &mut Pixmap, path: &SkPath, color: Color, t: Transform) {
    pixmap.fill_path(path, &paint(color), FillRule::Winding, t, None);
}

fn stroke(pixmap: &mut Pixmap, path: &SkPath, color: Color, width: f32, t: Transform) {
    let stroke = Stroke { width, line_cap: LineCap::Round, line_join: LineJoin::Round, ..Stroke::default() };
    pixmap.stroke_path(path, &paint(color), &stroke, t, None);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_icon_has_yellow_tile_and_ink_center() {
        let px = rgba(512, Style::App);
        let at = |x: usize, y: usize| &px[(y * 512 + x) * 4..(y * 512 + x) * 4 + 4];
        assert_eq!(at(256, 40), [0xFF, 0xCF, 0x1A, 255]);
        assert_eq!(at(300, 300), [0x1D, 0x1D, 0x1F, 255]);
        assert_eq!(at(2, 2)[3], 0, "corners are transparent");
    }

    #[test]
    fn writes_bundle_icons() {
        let dir = std::env::temp_dir().join(format!("marquee-icons-{}", std::process::id()));
        write_app_icons(&dir).unwrap();
        for name in ["32x32.png", "128x128.png", "128x128@2x.png", "icon.png", "icon.ico"] {
            assert!(dir.join(name).metadata().unwrap().len() > 0, "{name}");
        }
        fs::remove_dir_all(dir).unwrap();
    }
}
