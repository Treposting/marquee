// The annotation editor. Shapes live in image pixels; one renderer draws them for the screen
// and for the exported PNG, so what you see is what you copy. Rust sends the original image
// (annotate_image) and takes the result (annotate_export).
"use strict";

const { invoke } = window.__TAURI__.core;

const COLORS = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#AF52DE", "#1D1D1F", "#FFFFFF"];
/** Line widths for S, M, L in screen pixels; scaled by the display's DPI for the image. */
const WIDTHS = { s: 3, m: 5, l: 9 };
const TOOL_KEYS = { v: "select", a: "arrow", r: "rectangle", e: "ellipse", p: "pen", h: "highlight", t: "text", n: "counter", x: "redact" };
const BOX_TOOLS = new Set(["rectangle", "ellipse", "highlight", "redact"]);

const canvas = document.getElementById("canvas");
const ctx = canvas.getContext("2d");
const stage = document.getElementById("stage");
const textEditor = document.getElementById("text-editor");
const status = document.getElementById("status");
const id = new URLSearchParams(location.search).get("id");

let base = null; // ImageBitmap of the screenshot
let W = 0, H = 0;
const dpr = window.devicePixelRatio || 1;
/** Image pixels per screen pixel at 100%, so S/M/L look the same on any display. */
const unit = dpr;

let shapes = [];
let undoStack = [];
let redoStack = [];
let tool = "arrow";
let color = COLORS[0];
let size = "m";
let redactStyle = "pixelate";
let selectedId = null;
let gesture = null;
let view = { scale: 1, x: 0, y: 0 };
let hidden = { block: 0, pixelated: null, blurred: null };
let editingText = null; // { shape, isNew }
let nextId = 1;

// MARK: Geometry

const clone = (o) => JSON.parse(JSON.stringify(o));
const selected = () => shapes.find((s) => s.id === selectedId) ?? null;

function rectOf(s) {
  const [a, b] = [s.points[0], s.points[s.points.length - 1]];
  return { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), w: Math.abs(a.x - b.x), h: Math.abs(a.y - b.y) };
}

function fontSize(s) { return { s: 18, m: 26, l: 40 }[s.size] * unit; }
function counterRadius(s) { return { s: 12, m: 16, l: 22 }[s.size] * unit; }
function lineWidth(s) { return WIDTHS[s.size] * unit; }

function textLines(s) { return (s.text || " ").split("\n"); }

function boundsOf(s) {
  switch (s.tool) {
    case "pen":
    case "arrow": {
      const xs = s.points.map((p) => p.x), ys = s.points.map((p) => p.y);
      const x = Math.min(...xs), y = Math.min(...ys);
      return { x, y, w: Math.max(...xs) - x, h: Math.max(...ys) - y };
    }
    case "text": {
      const fs = fontSize(s);
      ctx.save();
      ctx.font = font(fs);
      const w = Math.max(fs, ...textLines(s).map((l) => ctx.measureText(l).width));
      ctx.restore();
      return { x: s.points[0].x, y: s.points[0].y, w, h: textLines(s).length * fs * 1.2 };
    }
    case "counter": {
      const r = counterRadius(s), p = s.points[0];
      return { x: p.x - r, y: p.y - r, w: r * 2, h: r * 2 };
    }
    default:
      return rectOf(s);
  }
}

function font(px) { return `600 ${px}px "Segoe UI Variable Display", "Segoe UI", system-ui, sans-serif`; }

function distToSegment(p, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const len = dx * dx + dy * dy;
  const t = len ? Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len)) : 0;
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

/** Whether a point (image pixels) touches a shape. Outlines count, so does inside a filled box. */
function hits(s, p) {
  const tol = Math.max(lineWidth(s) / 2 + 2, 6 / view.scale);
  const b = boundsOf(s);
  const inside = p.x >= b.x - tol && p.x <= b.x + b.w + tol && p.y >= b.y - tol && p.y <= b.y + b.h + tol;
  if (!inside) return false;
  if (s.tool === "pen" || s.tool === "arrow") {
    for (let i = 1; i < s.points.length; i++) if (distToSegment(p, s.points[i - 1], s.points[i]) <= tol * 1.5) return true;
    return false;
  }
  if (s.tool === "rectangle" || s.tool === "ellipse") {
    const nearEdge = p.x < b.x + tol * 2 || p.x > b.x + b.w - tol * 2 || p.y < b.y + tol * 2 || p.y > b.y + b.h - tol * 2;
    return nearEdge;
  }
  return true;
}

/** Drag handles of the selected shape: box corners, or an arrow's two ends. */
function handlesOf(s) {
  if (s.tool === "arrow") return [{ key: "start", ...s.points[0] }, { key: "end", ...s.points[1] }];
  if (BOX_TOOLS.has(s.tool)) {
    const r = rectOf(s);
    return [
      { key: "nw", x: r.x, y: r.y }, { key: "ne", x: r.x + r.w, y: r.y },
      { key: "sw", x: r.x, y: r.y + r.h }, { key: "se", x: r.x + r.w, y: r.y + r.h },
    ];
  }
  return [];
}

function handleAt(p) {
  const s = selected();
  if (!s) return null;
  const reach = 9 / view.scale;
  return handlesOf(s).find((h) => Math.hypot(h.x - p.x, h.y - p.y) <= reach) ?? null;
}

// MARK: Drawing

/** Pixelated and blurred copies of the whole image; redactions show them through a clip. */
function prepareHidden() {
  const block = Math.max(8, Math.round(10 * unit));
  if (hidden.block === block) return;
  const small = new OffscreenCanvas(Math.max(1, Math.ceil(W / block)), Math.max(1, Math.ceil(H / block)));
  const sctx = small.getContext("2d");
  sctx.imageSmoothingQuality = "medium";
  sctx.drawImage(base, 0, 0, small.width, small.height);
  const pixelated = new OffscreenCanvas(W, H);
  const pctx = pixelated.getContext("2d");
  pctx.imageSmoothingEnabled = false;
  pctx.drawImage(small, 0, 0, small.width * block, small.height * block);
  const blurred = new OffscreenCanvas(W, H);
  const bctx = blurred.getContext("2d");
  bctx.filter = `blur(${Math.round(14 * unit)}px)`;
  bctx.drawImage(base, 0, 0);
  hidden = { block, pixelated, blurred };
}

function drawArrow(c, s) {
  const [a, b] = s.points;
  const w = lineWidth(s);
  const angle = Math.atan2(b.y - a.y, b.x - a.x);
  const length = Math.hypot(b.x - a.x, b.y - a.y);
  const head = Math.min(length * 0.6, Math.max(14 * unit, w * 3.6));
  const spread = Math.PI / 7;
  const baseX = b.x - Math.cos(angle) * head * 0.8, baseY = b.y - Math.sin(angle) * head * 0.8;
  c.beginPath();
  c.moveTo(a.x, a.y);
  c.lineTo(baseX, baseY);
  c.lineWidth = w;
  c.stroke();
  c.beginPath();
  c.moveTo(b.x, b.y);
  c.lineTo(b.x - Math.cos(angle - spread) * head, b.y - Math.sin(angle - spread) * head);
  c.lineTo(b.x - Math.cos(angle + spread) * head, b.y - Math.sin(angle + spread) * head);
  c.closePath();
  c.fill();
}

function drawPen(c, s) {
  const pts = s.points;
  c.lineWidth = lineWidth(s);
  c.beginPath();
  c.moveTo(pts[0].x, pts[0].y);
  if (pts.length === 1) c.lineTo(pts[0].x + 0.1, pts[0].y);
  for (let i = 1; i < pts.length - 1; i++) {
    const mid = { x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2 };
    c.quadraticCurveTo(pts[i].x, pts[i].y, mid.x, mid.y);
  }
  if (pts.length > 1) c.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
  c.stroke();
}

function contrast(hex) {
  const n = parseInt(hex.slice(1), 16);
  const lum = 0.299 * (n >> 16) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255);
  return lum > 170 ? "#1D1D1F" : "#FFFFFF";
}

function drawShape(c, s) {
  c.save();
  c.strokeStyle = s.color;
  c.fillStyle = s.color;
  c.lineCap = "round";
  c.lineJoin = "round";
  const shadow = () => { c.shadowColor = "rgba(0,0,0,.28)"; c.shadowBlur = 4 * unit; c.shadowOffsetY = 1 * unit; };
  const r = rectOf(s);
  switch (s.tool) {
    case "arrow": shadow(); drawArrow(c, s); break;
    case "rectangle":
      shadow();
      c.lineWidth = lineWidth(s);
      c.beginPath();
      c.roundRect(r.x, r.y, r.w, r.h, Math.min(4 * unit, r.w / 2, r.h / 2));
      c.stroke();
      break;
    case "ellipse":
      shadow();
      c.lineWidth = lineWidth(s);
      c.beginPath();
      c.ellipse(r.x + r.w / 2, r.y + r.h / 2, r.w / 2, r.h / 2, 0, 0, Math.PI * 2);
      c.stroke();
      break;
    case "pen": shadow(); drawPen(c, s); break;
    case "highlight":
      c.globalCompositeOperation = "multiply";
      c.globalAlpha = 0.4;
      c.fillRect(r.x, r.y, r.w, r.h);
      break;
    case "redact":
      if (s.redact === "solid") {
        c.fillStyle = "#111113";
        c.fillRect(r.x, r.y, r.w, r.h);
      } else {
        c.beginPath();
        c.rect(r.x, r.y, r.w, r.h);
        c.clip();
        c.drawImage(s.redact === "blur" ? hidden.blurred : hidden.pixelated, 0, 0);
      }
      break;
    case "text": {
      const fs = fontSize(s);
      c.font = font(fs);
      c.textBaseline = "top";
      c.lineWidth = Math.max(2, fs / 7);
      c.strokeStyle = contrast(s.color) === "#FFFFFF" ? "rgba(255,255,255,.9)" : "rgba(0,0,0,.65)";
      textLines(s).forEach((line, i) => {
        const y = s.points[0].y + i * fs * 1.2 + fs * 0.08;
        c.strokeText(line, s.points[0].x, y);
        c.fillText(line, s.points[0].x, y);
      });
      break;
    }
    case "counter": {
      const p = s.points[0], radius = counterRadius(s);
      shadow();
      c.beginPath();
      c.arc(p.x, p.y, radius, 0, Math.PI * 2);
      c.fill();
      c.shadowColor = "transparent";
      c.lineWidth = Math.max(1.5, radius / 7);
      c.strokeStyle = "#FFFFFF";
      c.stroke();
      c.fillStyle = contrast(s.color);
      c.font = font(Math.round(radius * 1.1));
      c.textAlign = "center";
      c.textBaseline = "middle";
      c.fillText(String(s.number), p.x, p.y + radius * 0.05);
      break;
    }
  }
  c.restore();
}

/** The image and its shapes; redactions first so they never cover the marks drawn on top. */
function paint(c, skip) {
  c.drawImage(base, 0, 0);
  const visible = shapes.filter((s) => s !== skip);
  for (const s of visible) if (s.tool === "redact") drawShape(c, s);
  for (const s of visible) if (s.tool !== "redact") drawShape(c, s);
}

function layout() {
  const rect = stage.getBoundingClientRect();
  canvas.width = Math.round(rect.width * dpr);
  canvas.height = Math.round(rect.height * dpr);
  const pad = 24;
  // At most 100%: one image pixel per display pixel.
  view.scale = Math.min((rect.width - pad * 2) / W, (rect.height - pad * 2) / H, 1 / dpr);
  view.x = (rect.width - W * view.scale) / 2;
  view.y = (rect.height - H * view.scale) / 2;
  draw();
  if (editingText) placeTextEditor();
}

let pending = false;
function draw() {
  if (pending || !base) return;
  pending = true;
  requestAnimationFrame(() => {
    pending = false;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(dpr * view.scale, 0, 0, dpr * view.scale, dpr * view.x, dpr * view.y);
    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,.25)";
    ctx.shadowBlur = 18 / view.scale;
    ctx.fillRect(0, 0, W, H);
    ctx.restore();
    ctx.imageSmoothingQuality = "high";
    paint(ctx, editingText?.shape);
    const s = selected();
    if (s && !editingText) {
      const b = boundsOf(s);
      const px = 1 / view.scale;
      ctx.save();
      ctx.setLineDash([5 * px, 4 * px]);
      ctx.lineWidth = 1.5 * px;
      ctx.strokeStyle = "#FFCF1A";
      const m = 5 * px;
      ctx.strokeRect(b.x - m, b.y - m, b.w + m * 2, b.h + m * 2);
      ctx.setLineDash([]);
      for (const h of handlesOf(s)) {
        ctx.beginPath();
        ctx.arc(h.x, h.y, 5.5 * px, 0, Math.PI * 2);
        ctx.fillStyle = "#FFFFFF";
        ctx.fill();
        ctx.lineWidth = 2 * px;
        ctx.stroke();
      }
      ctx.restore();
    }
  });
}

// MARK: Editing

function commit() {
  undoStack.push(clone(shapes));
  if (undoStack.length > 200) undoStack.shift();
  redoStack = [];
  updateButtons();
}

function undo() {
  finishText();
  if (!undoStack.length) return;
  redoStack.push(clone(shapes));
  shapes = undoStack.pop();
  if (!selected()) selectedId = null;
  updateButtons();
  draw();
}

function redo() {
  finishText();
  if (!redoStack.length) return;
  undoStack.push(clone(shapes));
  shapes = redoStack.pop();
  if (!selected()) selectedId = null;
  updateButtons();
  draw();
}

function removeSelected() {
  if (!selected()) return;
  commit();
  shapes = shapes.filter((s) => s.id !== selectedId);
  selectedId = null;
  renumber();
  draw();
}

/** Step numbers stay 1, 2, 3… in the order they were placed. */
function renumber() {
  let n = 1;
  for (const s of shapes) if (s.tool === "counter") s.number = n++;
}

function toImage(e) {
  const rect = canvas.getBoundingClientRect();
  return { x: (e.clientX - rect.left - view.x) / view.scale, y: (e.clientY - rect.top - view.y) / view.scale };
}

function clampToImage(p) {
  return { x: Math.min(W, Math.max(0, p.x)), y: Math.min(H, Math.max(0, p.y)) };
}

function topShapeAt(p) {
  for (let i = shapes.length - 1; i >= 0; i--) if (hits(shapes[i], p)) return shapes[i];
  return null;
}

function newShape(kind, p) {
  return { id: nextId++, tool: kind, color, size, redact: redactStyle, points: [p, p], text: "", number: 0 };
}

canvas.addEventListener("pointerdown", (e) => {
  if (e.button !== 0 || !base) return;
  if (editingText) { finishText(); return; }
  canvas.setPointerCapture(e.pointerId);
  const p = toImage(e);
  const handle = handleAt(p);
  if (handle) {
    commit();
    gesture = { kind: "handle", handle: handle.key, start: p, original: clone(selected()) };
    return;
  }
  if (tool === "select") {
    const hit = topShapeAt(p);
    selectedId = hit?.id ?? null;
    syncControlsToSelection();
    if (hit) {
      commit();
      gesture = { kind: "move", start: p, original: clone(hit), moved: false };
    }
    draw();
    return;
  }
  if (tool === "text") {
    e.preventDefault(); // keep the focus for the text box
    const hit = topShapeAt(p);
    if (hit?.tool === "text") return editText(hit, false);
    const s = newShape("text", clampToImage(p));
    s.points = [s.points[0]];
    return editText(s, true);
  }
  if (tool === "counter") {
    commit();
    const s = newShape("counter", clampToImage(p));
    s.points = [s.points[0]];
    shapes.push(s);
    renumber();
    selectedId = s.id;
    draw();
    return;
  }
  commit();
  const s = newShape(tool, tool === "pen" ? p : clampToImage(p));
  if (tool === "pen") s.points = [p];
  shapes.push(s);
  selectedId = null;
  gesture = { kind: "draw", shape: s, start: p };
  draw();
});

canvas.addEventListener("pointermove", (e) => {
  const p = toImage(e);
  if (!gesture) {
    const overHandle = handleAt(p);
    canvas.style.cursor = overHandle ? "grab"
      : tool === "select" ? (topShapeAt(p) ? "move" : "default")
      : tool === "text" ? "text" : "crosshair";
    return;
  }
  if (gesture.kind === "draw") {
    const s = gesture.shape;
    if (s.tool === "pen") {
      const last = s.points[s.points.length - 1];
      if (Math.hypot(p.x - last.x, p.y - last.y) * view.scale >= 1.5) s.points.push(p);
    } else {
      let end = clampToImage(p);
      if (e.shiftKey) end = constrain(s.tool, s.points[0], end);
      s.points[1] = end;
    }
  } else if (gesture.kind === "move") {
    const s = selected();
    const dx = p.x - gesture.start.x, dy = p.y - gesture.start.y;
    s.points = gesture.original.points.map((q) => ({ x: q.x + dx, y: q.y + dy }));
    gesture.moved = true;
  } else if (gesture.kind === "handle") {
    const s = selected();
    const o = gesture.original;
    const q = clampToImage(p);
    if (s.tool === "arrow") {
      s.points = gesture.handle === "start" ? [q, o.points[1]] : [o.points[0], q];
    } else {
      const r = rectOf(o);
      const x1 = gesture.handle.includes("w") ? q.x : r.x, x2 = gesture.handle.includes("e") ? q.x : r.x + r.w;
      const y1 = gesture.handle.includes("n") ? q.y : r.y, y2 = gesture.handle.includes("s") ? q.y : r.y + r.h;
      s.points = [{ x: x1, y: y1 }, { x: x2, y: y2 }];
    }
  }
  draw();
});

function endGesture() {
  if (!gesture) return;
  if (gesture.kind === "draw") {
    const s = gesture.shape;
    const b = boundsOf(s);
    const tiny = s.tool !== "pen" && Math.max(b.w, b.h) * view.scale < 4;
    if (tiny) {
      shapes = shapes.filter((x) => x !== s);
      undoStack.pop();
      updateButtons();
    } else {
      selectedId = s.id;
    }
  } else if (gesture.kind === "move" && !gesture.moved) {
    undoStack.pop();
    updateButtons();
  }
  gesture = null;
  draw();
}
canvas.addEventListener("pointerup", endGesture);
canvas.addEventListener("pointercancel", endGesture);

canvas.addEventListener("dblclick", (e) => {
  const hit = topShapeAt(toImage(e));
  if (hit?.tool === "text") editText(hit, false);
});

/** Shift: arrows snap to 45°, boxes become squares and circles. */
function constrain(kind, a, b) {
  if (kind === "arrow") {
    const angle = Math.round(Math.atan2(b.y - a.y, b.x - a.x) / (Math.PI / 4)) * (Math.PI / 4);
    const len = Math.hypot(b.x - a.x, b.y - a.y);
    return { x: a.x + Math.cos(angle) * len, y: a.y + Math.sin(angle) * len };
  }
  const side = Math.max(Math.abs(b.x - a.x), Math.abs(b.y - a.y));
  return { x: a.x + Math.sign(b.x - a.x || 1) * side, y: a.y + Math.sign(b.y - a.y || 1) * side };
}

// MARK: Text

function placeTextEditor() {
  const s = editingText.shape;
  const fs = fontSize(s) * view.scale;
  Object.assign(textEditor.style, {
    left: `${view.x + s.points[0].x * view.scale - 3}px`,
    top: `${view.y + s.points[0].y * view.scale - 3}px`,
    fontSize: `${fs}px`,
    color: s.color,
    padding: "2px",
  });
  textEditor.style.width = "10px";
  textEditor.style.height = "10px";
  textEditor.style.width = `${Math.max(fs * 2, textEditor.scrollWidth + fs)}px`;
  textEditor.style.height = `${textEditor.scrollHeight}px`;
}

function editText(s, isNew) {
  selectedId = null;
  editingText = { shape: s, isNew };
  textEditor.value = s.text;
  textEditor.hidden = false;
  placeTextEditor();
  draw();
  textEditor.focus();
  textEditor.select();
}

function finishText() {
  if (!editingText) return;
  const { shape, isNew } = editingText;
  editingText = null;
  textEditor.hidden = true;
  const text = textEditor.value.replace(/\s+$/, "");
  if (isNew) {
    if (text) {
      commit();
      shape.text = text;
      shapes.push(shape);
      selectedId = shape.id;
    }
  } else if (text !== shape.text) {
    commit();
    if (text) {
      shape.text = text;
      selectedId = shape.id;
    } else {
      shapes = shapes.filter((x) => x !== shape);
    }
  }
  draw();
}

textEditor.addEventListener("input", placeTextEditor);
textEditor.addEventListener("blur", finishText);
textEditor.addEventListener("keydown", (e) => {
  e.stopPropagation();
  if (e.key === "Escape" || (e.key === "Enter" && (e.ctrlKey || !e.shiftKey))) {
    e.preventDefault();
    finishText();
  }
});

// MARK: Toolbar

const toolButtons = [...document.querySelectorAll("[data-tool]")];
const sizeButtons = [...document.querySelectorAll("[data-size]")];
const redactButtons = [...document.querySelectorAll("[data-redact]")];
const colorBox = document.getElementById("colors");
const colorButtons = COLORS.map((c) => {
  const b = document.createElement("button");
  b.setAttribute("role", "radio");
  b.setAttribute("aria-label", `Color ${c}`);
  b.title = c;
  b.style.setProperty("--c", c);
  b.append(document.createElement("span"));
  b.addEventListener("click", () => setColor(c));
  colorBox.append(b);
  return b;
});

function setTool(next) {
  finishText();
  tool = next;
  if (tool !== "select" && selected() && selected().tool !== tool) selectedId = null;
  updateButtons();
  draw();
}

/** Changing color, size or redact style also restyles the selected shape. */
function restyle(change) {
  const s = selected();
  if (!s) return;
  commit();
  Object.assign(s, change);
  draw();
}

function setColor(c) { color = c; restyle({ color: c }); updateButtons(); }
function setSize(v) { size = v; restyle({ size: v }); updateButtons(); }
function setRedact(v) { redactStyle = v; if (selected()?.tool === "redact") restyle({ redact: v }); updateButtons(); }

function syncControlsToSelection() {
  const s = selected();
  if (!s) return updateButtons();
  color = s.color;
  size = s.size;
  if (s.tool === "redact") redactStyle = s.redact;
  updateButtons();
}

function updateButtons() {
  for (const b of toolButtons) b.setAttribute("aria-checked", String(b.dataset.tool === tool));
  for (const b of sizeButtons) b.setAttribute("aria-checked", String(b.dataset.size === size));
  for (const b of redactButtons) b.setAttribute("aria-checked", String(b.dataset.redact === redactStyle));
  colorButtons.forEach((b, i) => b.setAttribute("aria-checked", String(COLORS[i] === color)));
  const redacting = tool === "redact" || selected()?.tool === "redact";
  document.getElementById("redact-styles").hidden = !redacting;
  colorBox.hidden = redacting;
  document.getElementById("undo").disabled = !undoStack.length;
  document.getElementById("redo").disabled = !redoStack.length;
}

toolButtons.forEach((b) => b.addEventListener("click", () => setTool(b.dataset.tool)));
sizeButtons.forEach((b) => b.addEventListener("click", () => setSize(b.dataset.size)));
redactButtons.forEach((b) => b.addEventListener("click", () => setRedact(b.dataset.redact)));
document.getElementById("undo").addEventListener("click", undo);
document.getElementById("redo").addEventListener("click", redo);

// MARK: Export

let statusTimer = 0;
function flash(text) {
  status.textContent = text;
  status.hidden = false;
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => (status.hidden = true), 2200);
}

async function exportAs(action) {
  finishText();
  const buttons = document.querySelectorAll("[data-export]");
  buttons.forEach((b) => (b.disabled = true));
  try {
    const out = new OffscreenCanvas(W, H);
    paint(out.getContext("2d"));
    const blob = await out.convertToBlob({ type: "image/png" });
    const bytes = new Uint8Array(await blob.arrayBuffer());
    flash(await invoke("annotate_export", bytes, { headers: { "x-action": action } }));
  } catch (e) {
    flash(String(e));
  } finally {
    buttons.forEach((b) => (b.disabled = false));
  }
}

document.querySelectorAll("[data-export]").forEach((b) => b.addEventListener("click", () => exportAs(b.dataset.export)));

document.addEventListener("keydown", (e) => {
  if (editingText) return;
  const key = e.key.toLowerCase();
  if (e.ctrlKey && key === "z" && !e.shiftKey) { e.preventDefault(); undo(); }
  else if (e.ctrlKey && (key === "y" || (key === "z" && e.shiftKey))) { e.preventDefault(); redo(); }
  else if (e.ctrlKey && key === "c") { e.preventDefault(); exportAs("copy"); }
  else if (e.ctrlKey && key === "s") { e.preventDefault(); exportAs("save"); }
  else if (e.ctrlKey && key === "p") { e.preventDefault(); exportAs("pin"); }
  else if (key === "delete" || key === "backspace") { e.preventDefault(); removeSelected(); }
  else if (key === "escape") { selectedId = null; updateButtons(); draw(); }
  else if (!e.ctrlKey && !e.altKey && TOOL_KEYS[key]) setTool(TOOL_KEYS[key]);
  else if (selected() && key.startsWith("arrow")) {
    e.preventDefault();
    const step = (e.shiftKey ? 10 : 1) * unit;
    const d = { arrowleft: [-step, 0], arrowright: [step, 0], arrowup: [0, -step], arrowdown: [0, step] }[key];
    commit();
    selected().points = selected().points.map((q) => ({ x: q.x + d[0], y: q.y + d[1] }));
    draw();
  }
});

// MARK: Start

new ResizeObserver(layout).observe(stage);

async function start() {
  const buffer = await invoke("annotate_image", { id });
  base = await createImageBitmap(new Blob([buffer], { type: "image/png" }));
  W = base.width;
  H = base.height;
  prepareHidden();
  updateButtons();
  layout();
  await invoke("annotate_ready");
}

start().catch((e) => {
  flash(String(e));
  invoke("annotate_ready");
});
