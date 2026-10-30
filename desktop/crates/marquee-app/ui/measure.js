// Measure, on the capture overlay's frozen frame (overlay.js hands over when Rust starts it
// in "measure" mode). Measuring works in frame pixels; values show in display units (pixels
// divided by the display's scale), or in real pixels while Shift is held.
//   move     distances to the nearest edges, left to right and top to bottom
//   drag     snap to the element inside the rectangle
//   H / V    add a guide at the pointer (it snaps to a nearby edge); drag to move it, arrows
//            nudge the selected one (Shift for 10), Tab selects the next, Delete removes it
//   Space    keep the current measurement; Delete clears kept ones when no guide is selected
//   Ctrl+C   copy the last measurement; Ctrl+S capture the screen with the measurements
//   Esc      leave
"use strict";

const Measure = (() => {
  const YELLOW = "#FFCF1A";
  const GRAB = 5; // CSS pixels around a guide that grab it
  const { invoke } = window.__TAURI__.core;

  let active = false;
  let px = null; // { data, width, height }
  let frameCanvas = null, canvas = null, ctx = null, hint = null;
  let s = 1; // frame pixels per CSS pixel
  let pointer = null; // CSS pixels
  let showPixels = false;
  let live = null; // { kind: "distances", x, y, d } | { kind: "box", rect }
  let kept = [];
  let guides = [];
  let selectedGuide = null;
  let nextGuide = 1;
  let gesture = null; // { kind: "drag", start } | { kind: "guide", id }
  let queued = false;
  let hintTimer = 0;

  const value = (pixels) => (showPixels ? pixels : Math.round(pixels / s));
  const size = (w, h) => `${value(w)} × ${value(h)}`;
  const toFrame = (p) => ({ x: Math.floor(p.x * s), y: Math.floor(p.y * s) });

  // MARK: Drawing

  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; draw(); });
  }

  function label(text, x, y, { anchor = "center", strong = false } = {}) {
    ctx.font = `600 ${strong ? 13 : 12}px "Segoe UI", system-ui, sans-serif`;
    const w = ctx.measureText(text).width + 12, h = strong ? 24 : 21;
    let left = anchor === "center" ? x - w / 2 : anchor === "right" ? x - w : x;
    let top = y - h / 2;
    left = Math.min(Math.max(4, left), window.innerWidth - w - 4);
    top = Math.min(Math.max(4, top), window.innerHeight - h - 4);
    ctx.fillStyle = strong ? YELLOW : "rgba(20, 20, 22, .88)";
    ctx.beginPath();
    ctx.roundRect(left, top, w, h, 6);
    ctx.fill();
    if (strong) {
      ctx.lineWidth = 1;
      ctx.strokeStyle = "rgba(20, 20, 22, .55)";
      ctx.stroke();
    }
    ctx.fillStyle = strong ? "#1D1D1F" : "#FFFFFF";
    ctx.textBaseline = "middle";
    ctx.textAlign = "left";
    ctx.fillText(text, left + 6, top + h / 2 + 0.5);
  }

  /** A line with short end caps, like a dimension line on a drawing, with a dark outline so
   *  it shows on any color. */
  function dimension(ax, ay, bx, by, color = YELLOW) {
    const horizontal = ay === by;
    const cap = 4;
    const path = new Path2D();
    path.moveTo(ax, ay);
    path.lineTo(bx, by);
    if (horizontal) {
      path.moveTo(ax, ay - cap); path.lineTo(ax, ay + cap);
      path.moveTo(bx, by - cap); path.lineTo(bx, by + cap);
    } else {
      path.moveTo(ax - cap, ay); path.lineTo(ax + cap, ay);
      path.moveTo(bx - cap, by); path.lineTo(bx + cap, by);
    }
    ctx.lineWidth = 3;
    ctx.strokeStyle = "rgba(20, 20, 22, .55)";
    ctx.stroke(path);
    ctx.lineWidth = 1;
    ctx.strokeStyle = color;
    ctx.stroke(path);
  }

  /** Lines to the nearest edge on each side; the width sits on the horizontal line and the
   *  height beside the vertical one. */
  function drawDistances(m) {
    const { x, y, d } = m;
    const cy = Math.round((y + 0.5) / s) + 0.5, cx = Math.round((x + 0.5) / s) + 0.5;
    const left = (x - d.left) / s, right = (x + d.right + 1) / s;
    const top = (y - d.up) / s, bottom = (y + d.down + 1) / s;
    dimension(left, cy, right, cy);
    dimension(cx, top, cx, bottom);
    label(String(value(d.left + d.right + 1)), (left + right) / 2, cy - 16);
    label(String(value(d.up + d.down + 1)), cx + 10, (top + bottom) / 2, { anchor: "left" });
  }

  function drawBox(m) {
    const r = m.rect;
    const x = r.x / s, y = r.y / s, w = r.width / s, h = r.height / s;
    ctx.fillStyle = "rgba(255, 207, 26, .14)";
    ctx.fillRect(x, y, w, h);
    ctx.strokeStyle = YELLOW;
    ctx.lineWidth = 1;
    ctx.strokeRect(x + 0.5, y + 0.5, Math.max(0, w - 1), Math.max(0, h - 1));
    label(size(r.width, r.height), x + w / 2, y + h + 16, { strong: true });
  }

  function drawGuides() {
    const p = pointer ?? { x: window.innerWidth / 2, y: window.innerHeight / 2 };
    for (const g of guides) {
      const selected = g.id === selectedGuide;
      const at = g.position / s;
      const line = new Path2D();
      if (g.axis === "vertical") { line.moveTo(at, 0); line.lineTo(at, window.innerHeight); }
      else { line.moveTo(0, at); line.lineTo(window.innerWidth, at); }
      ctx.lineWidth = selected ? 4 : 3;
      ctx.strokeStyle = "rgba(20, 20, 22, .4)";
      ctx.stroke(line);
      ctx.lineWidth = selected ? 2 : 1;
      ctx.strokeStyle = YELLOW;
      ctx.setLineDash(selected ? [] : [6, 4]);
      ctx.stroke(line);
      ctx.setLineDash([]);
      if (selected) {
        if (g.axis === "vertical") label(`x ${value(g.position)}`, at + 8, 18, { anchor: "left", strong: true });
        else label(`y ${value(g.position)}`, 8, at - 14, { anchor: "left", strong: true });
      }
    }
    // The space between neighbouring guides, drawn near the pointer (clear of the distance
    // labels) so it's easy to read.
    const gy = Math.round(p.y) + 48.5, gx = Math.round(p.x) - 48.5;
    for (const gap of MeasureCore.gaps(guides.filter((g) => g.axis === "vertical").map((g) => g.position))) {
      const a = gap.start / s, b = gap.end / s;
      dimension(a, gy, b, gy, "#FFFFFF");
      label(String(value(gap.end - gap.start)), (a + b) / 2, gy);
    }
    for (const gap of MeasureCore.gaps(guides.filter((g) => g.axis === "horizontal").map((g) => g.position))) {
      const a = gap.start / s, b = gap.end / s;
      dimension(gx, a, gx, b, "#FFFFFF");
      label(String(value(gap.end - gap.start)), gx, (a + b) / 2);
    }
  }

  function draw() {
    if (!active) return;
    ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
    for (const m of kept) m.kind === "box" ? drawBox(m) : drawDistances(m);
    drawGuides();
    if (gesture?.kind === "drag" && pointer) {
      const a = gesture.start, b = pointer;
      ctx.setLineDash([5, 4]);
      ctx.strokeStyle = YELLOW;
      ctx.lineWidth = 1;
      ctx.strokeRect(Math.min(a.x, b.x) + 0.5, Math.min(a.y, b.y) + 0.5, Math.abs(b.x - a.x), Math.abs(b.y - a.y));
      ctx.setLineDash([]);
    } else if (live) {
      live.kind === "box" ? drawBox(live) : drawDistances(live);
    }
  }

  // MARK: Measuring

  function measureAt(p) {
    const f = toFrame(p);
    live = { kind: "distances", x: f.x, y: f.y, d: MeasureCore.distances(px, f.x, f.y) };
  }

  function guideNear(p) {
    let best = null, bestDistance = GRAB;
    for (const g of guides) {
      const distance = Math.abs((g.axis === "vertical" ? p.x : p.y) - g.position / s);
      if (distance <= bestDistance) { best = g; bestDistance = distance; }
    }
    return best;
  }

  function addGuide(axis) {
    if (!pointer) return;
    const f = toFrame(pointer);
    const position = axis === "vertical" ? Math.round(pointer.x * s) : Math.round(pointer.y * s);
    const snapped = MeasureCore.snapGuide(px, axis, position, axis === "vertical" ? f.y : f.x, Math.round(4 * s));
    const g = { id: nextGuide++, axis, position: snapped };
    guides.push(g);
    selectedGuide = g.id;
  }

  function lastText() {
    const g = guides.find((x) => x.id === selectedGuide);
    if (g) return String(value(g.position));
    const m = live ?? kept[kept.length - 1];
    if (!m) return null;
    if (m.kind === "box") return size(m.rect.width, m.rect.height);
    // Hovering: the width and height of the region under the pointer.
    return size(m.d.left + m.d.right + 1, m.d.up + m.d.down + 1);
  }

  function flash(text) {
    hint.textContent = text;
    hint.hidden = false;
    clearTimeout(hintTimer);
    hintTimer = setTimeout(() => (hint.hidden = true), 1600);
  }

  async function capture() {
    const out = new OffscreenCanvas(px.width, px.height);
    const c = out.getContext("2d");
    c.drawImage(frameCanvas, 0, 0);
    c.drawImage(canvas, 0, 0, px.width, px.height);
    const blob = await out.convertToBlob({ type: "image/png" });
    stop();
    await invoke("overlay_capture", new Uint8Array(await blob.arrayBuffer()));
  }

  function leave() {
    stop();
    invoke("overlay_finish", { selection: { kind: "cancel" } });
  }

  // MARK: Input

  window.addEventListener("mousemove", (e) => {
    if (!active) return;
    pointer = { x: e.clientX, y: e.clientY };
    if (gesture?.kind === "guide") {
      const g = guides.find((x) => x.id === gesture.id);
      if (g) g.position = Math.round((g.axis === "vertical" ? pointer.x : pointer.y) * s);
    } else if (!gesture) {
      measureAt(pointer);
      const g = guideNear(pointer);
      document.body.style.cursor = g ? (g.axis === "vertical" ? "ew-resize" : "ns-resize") : "crosshair";
    }
    schedule();
  });

  window.addEventListener("mousedown", (e) => {
    if (!active) return;
    if (e.button === 2) return leave();
    if (e.button !== 0) return;
    pointer = { x: e.clientX, y: e.clientY };
    const g = guideNear(pointer);
    if (g) {
      selectedGuide = g.id;
      gesture = { kind: "guide", id: g.id };
    } else {
      selectedGuide = null;
      gesture = { kind: "drag", start: pointer };
    }
    schedule();
  });

  window.addEventListener("mouseup", (e) => {
    if (!active || e.button !== 0 || !gesture) return;
    const ended = gesture;
    gesture = null;
    pointer = { x: e.clientX, y: e.clientY };
    if (ended.kind === "drag") {
      const a = toFrame(ended.start), b = toFrame(pointer);
      const rect = { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), width: Math.abs(b.x - a.x), height: Math.abs(b.y - a.y) };
      if (rect.width / s >= 3 && rect.height / s >= 3) live = { kind: "box", rect: MeasureCore.snap(px, rect) };
      else measureAt(pointer);
    } else {
      // A guide let go near an edge settles on it.
      const g = guides.find((x) => x.id === ended.id);
      if (g) {
        const f = toFrame(pointer);
        g.position = MeasureCore.snapGuide(px, g.axis, g.position, g.axis === "vertical" ? f.y : f.x, Math.round(4 * s));
      }
    }
    schedule();
  });

  window.addEventListener("keydown", (e) => {
    if (!active) return;
    const key = e.key.toLowerCase();
    if (e.key === "Shift" && !showPixels) { showPixels = true; schedule(); return; }
    e.preventDefault();
    if (key === "escape") return leave();
    if (e.ctrlKey && key === "c") {
      const text = lastText();
      if (text) invoke("overlay_copy_text", { text }).then(() => flash(`Copied ${text}`)).catch((err) => flash(String(err)));
    } else if (e.ctrlKey && key === "s") {
      capture().catch((err) => console.error(err));
    } else if (key === " ") {
      if (live) { kept.push(live); live = null; flash("Kept on screen"); }
    } else if (key === "h" || key === "v") {
      addGuide(key === "h" ? "horizontal" : "vertical");
    } else if (key === "tab") {
      if (guides.length) {
        const i = guides.findIndex((g) => g.id === selectedGuide);
        selectedGuide = guides[(i + 1) % guides.length].id;
      }
    } else if (key === "delete" || key === "backspace") {
      if (selectedGuide != null) {
        guides = guides.filter((g) => g.id !== selectedGuide);
        selectedGuide = null;
      } else {
        kept = [];
        live = null;
      }
    } else if (key.startsWith("arrow")) {
      const g = guides.find((x) => x.id === selectedGuide);
      if (!g) return;
      const step = Math.max(1, Math.round((e.shiftKey ? 10 : 1) * (showPixels ? 1 : s)));
      const forward = g.axis === "vertical" ? key === "arrowright" : key === "arrowdown";
      const backward = g.axis === "vertical" ? key === "arrowleft" : key === "arrowup";
      if (forward || backward) {
        const limit = g.axis === "vertical" ? px.width : px.height;
        g.position = Math.min(limit, Math.max(0, g.position + (forward ? step : -step)));
      }
    }
    schedule();
  });

  window.addEventListener("resize", () => active && schedule());

  window.addEventListener("keyup", (e) => {
    if (active && e.key === "Shift") { showPixels = false; schedule(); }
  });

  // MARK: Start and stop

  /** Starts measuring over the frame overlay.js has drawn. */
  function start({ frame, ui, uiContext, hintElement, bytes, width, height }) {
    active = true;
    frameCanvas = frame;
    canvas = ui;
    ctx = uiContext;
    hint = hintElement;
    px = { data: new Uint8ClampedArray(bytes), width, height };
    s = width / window.innerWidth;
    pointer = null;
    showPixels = false;
    live = null;
    kept = [];
    guides = [];
    selectedGuide = null;
    gesture = null;
    document.body.style.cursor = "crosshair";
    hint.innerHTML = "Move to measure · Drag around an element · <kbd>H</kbd> <kbd>V</kbd> guides · <kbd>Space</kbd> keep · <kbd>Ctrl+C</kbd> copy · <kbd>Ctrl+S</kbd> capture · <kbd>Shift</kbd> pixels · <kbd>Esc</kbd> exit";
    hint.hidden = false;
    clearTimeout(hintTimer);
    hintTimer = setTimeout(() => (hint.hidden = true), 6000);
    schedule();
  }

  function stop() {
    active = false;
    px = null;
    clearTimeout(hintTimer);
  }

  return { start, stop, get active() { return active; } };
})();
