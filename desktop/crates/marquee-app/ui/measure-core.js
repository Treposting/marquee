// Measure's pixel logic, ported from the macOS app's EdgeFinder: pure functions over RGBA
// pixels { data, width, height }, so they are unit tested (ui-tests/measure-core.test.js).
"use strict";

const MeasureCore = (() => {
  /** Ignores anti-aliasing and compression noise, keeps 1 px borders. */
  const TOLERANCE = 12;

  function differs(px, i, j, tolerance) {
    const d = px.data;
    return Math.max(Math.abs(d[i] - d[j]), Math.abs(d[i + 1] - d[j + 1]), Math.abs(d[i + 2] - d[j + 2])) > tolerance;
  }

  const index = (px, x, y) => (y * px.width + x) * 4;

  /** How far the same-colored region around (x, y) reaches left, right, up and down. */
  function distances(px, x, y, tolerance = TOLERANCE) {
    x = Math.min(Math.max(0, x), px.width - 1);
    y = Math.min(Math.max(0, y), px.height - 1);
    const start = index(px, x, y);
    let left = x;
    while (left > 0 && !differs(px, index(px, left - 1, y), start, tolerance)) left--;
    let right = x;
    while (right < px.width - 1 && !differs(px, index(px, right + 1, y), start, tolerance)) right++;
    let top = y;
    while (top > 0 && !differs(px, index(px, x, top - 1), start, tolerance)) top--;
    let bottom = y;
    while (bottom < px.height - 1 && !differs(px, index(px, x, bottom + 1), start, tolerance)) bottom++;
    return { left: x - left, right: right - x, up: y - top, down: bottom - y };
  }

  /**
   * Shrinks a dragged rectangle to whatever sits inside it. The background is the most common
   * color along the rectangle's border; the result is the bounding box of every pixel that
   * differs from it, or the clamped rectangle when nothing does.
   */
  function snap(px, rect, tolerance = TOLERANCE) {
    const x0 = Math.min(Math.max(0, rect.x), px.width), y0 = Math.min(Math.max(0, rect.y), px.height);
    const x1 = Math.min(Math.max(x0, rect.x + rect.width), px.width), y1 = Math.min(Math.max(y0, rect.y + rect.height), px.height);
    const clamped = { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
    if (clamped.width <= 0 || clamped.height <= 0) return clamped;

    const d = px.data;
    const counts = new Map();
    const count = (x, y) => {
      const i = index(px, x, y);
      const key = (d[i] << 16) | (d[i + 1] << 8) | d[i + 2];
      counts.set(key, (counts.get(key) ?? 0) + 1);
    };
    for (let x = x0; x < x1; x++) { count(x, y0); count(x, y1 - 1); }
    for (let y = y0; y < y1; y++) { count(x0, y); count(x1 - 1, y); }
    let background = 0, best = -1;
    for (const [key, n] of counts) if (n > best) { best = n; background = key; }
    const br = (background >> 16) & 255, bg = (background >> 8) & 255, bb = background & 255;

    let minX = Infinity, minY = Infinity, maxX = -1, maxY = -1;
    for (let y = y0; y < y1; y++) {
      let i = index(px, x0, y);
      for (let x = x0; x < x1; x++, i += 4) {
        if (Math.max(Math.abs(d[i] - br), Math.abs(d[i + 1] - bg), Math.abs(d[i + 2] - bb)) > tolerance) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return clamped;
    return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
  }

  /**
   * Moves a guide onto the nearest color edge within `reach` pixels, looking along the
   * pointer's row (vertical guides) or column (horizontal guides). Positions are pixel
   * boundaries: a vertical guide at x sits on the left edge of column x.
   */
  function snapGuide(px, axis, position, across, reach, tolerance = TOLERANCE) {
    const vertical = axis === "vertical";
    const limit = vertical ? px.width : px.height;
    across = Math.min(Math.max(0, across), (vertical ? px.height : px.width) - 1);
    const at = (p) => (vertical ? index(px, p, across) : index(px, across, p));
    for (let offset = 0; offset <= reach; offset++) {
      for (const b of offset ? [position - offset, position + offset] : [position]) {
        if (b > 0 && b < limit && differs(px, at(b - 1), at(b), tolerance)) return b;
      }
    }
    return Math.min(Math.max(0, position), limit);
  }

  /** The spaces between neighbouring guides on one axis, as { start, end } positions. */
  function gaps(positions) {
    const sorted = [...positions].sort((a, b) => a - b);
    const out = [];
    for (let i = 1; i < sorted.length; i++) if (sorted[i] > sorted[i - 1]) out.push({ start: sorted[i - 1], end: sorted[i] });
    return out;
  }

  return { TOLERANCE, distances, snap, snapGuide, gaps };
})();

if (typeof module !== "undefined") module.exports = MeasureCore;
