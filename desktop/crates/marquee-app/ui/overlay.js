// The capture overlay. Rust freezes the display, this page shows the frame and lets you drag an
// area (or, after Space, click a window), then reports the choice in the frame's pixels.
"use strict";

const { invoke } = window.__TAURI__.core;
const YELLOW = "#FFCF1A";

const frame = document.getElementById("frame");
const ui = document.getElementById("ui");
const hint = document.getElementById("hint");
const loupe = document.getElementById("loupe");
const loupeCanvas = document.getElementById("loupe-canvas");
const loupeLabel = document.getElementById("loupe-label");
const uiCtx = ui.getContext("2d");
const loupeCtx = loupeCanvas.getContext("2d");

let info = null;
let mode = "area";
let pointer = null; // CSS pixels
let drag = null; // { x, y } where the drag started, CSS pixels
let hover = null; // window under the pointer, in frame pixels
let finished = false;
let queued = false;

/** Frame pixels per CSS pixel. */
const scale = () => info.width / window.innerWidth;

function finish(selection) {
  if (finished) return;
  finished = true;
  invoke("overlay_finish", { selection });
}

const cancel = () => finish({ kind: "cancel" });

function setMode(next) {
  mode = next;
  drag = null;
  document.body.classList.toggle("window-mode", mode === "window");
  hint.innerHTML = mode === "area"
    ? "Drag to select an area · <kbd>Space</kbd> pick a window · <kbd>Esc</kbd> cancel"
    : "Click a window · <kbd>Space</kbd> drag an area · <kbd>Esc</kbd> cancel";
  updateHover();
  schedule();
}

function selectionRect() {
  if (!drag || !pointer) return null;
  return {
    x: Math.min(drag.x, pointer.x), y: Math.min(drag.y, pointer.y),
    w: Math.abs(pointer.x - drag.x), h: Math.abs(pointer.y - drag.y),
  };
}

function updateHover() {
  hover = null;
  if (mode !== "window" || !pointer) return;
  const s = scale();
  const px = pointer.x * s, py = pointer.y * s;
  // Front to back: the first window under the pointer is the visible one.
  hover = info.windows.find((w) => px >= w.x && py >= w.y && px < w.x + w.width && py < w.y + w.height) ?? null;
}

function schedule() {
  if (queued) return;
  queued = true;
  requestAnimationFrame(() => { queued = false; draw(); });
}

function pill(ctx, text, x, y) {
  ctx.font = '600 12px "Segoe UI", system-ui, sans-serif';
  const w = ctx.measureText(text).width + 16;
  const h = 22;
  x = Math.min(Math.max(4, x), window.innerWidth - w - 4);
  y = Math.min(Math.max(4, y), window.innerHeight - h - 4);
  ctx.fillStyle = "rgba(20, 20, 22, .82)";
  ctx.beginPath(); ctx.roundRect(x, y, w, h, 6); ctx.fill();
  ctx.fillStyle = "#fff";
  ctx.textBaseline = "middle";
  ctx.fillText(text, x + 8, y + h / 2 + 0.5);
}

function draw() {
  const W = window.innerWidth, H = window.innerHeight;
  uiCtx.clearRect(0, 0, W, H);
  uiCtx.fillStyle = "rgba(0, 0, 0, .38)";
  uiCtx.fillRect(0, 0, W, H);
  const s = scale();

  if (mode === "area") {
    const r = selectionRect();
    if (r && r.w > 0 && r.h > 0) {
      uiCtx.clearRect(r.x, r.y, r.w, r.h);
      uiCtx.strokeStyle = YELLOW;
      uiCtx.lineWidth = 1.5;
      uiCtx.strokeRect(r.x - 0.75, r.y - 0.75, r.w + 1.5, r.h + 1.5);
      pill(uiCtx, `${Math.round(r.w * s)} × ${Math.round(r.h * s)}`, r.x, r.y + r.h + 8);
    }
    if (pointer) {
      // Crosshair, drawn with a dark edge so it shows on any background.
      for (const [color, width] of [["rgba(0,0,0,.55)", 3], ["rgba(255,255,255,.9)", 1]]) {
        uiCtx.strokeStyle = color;
        uiCtx.lineWidth = width;
        uiCtx.beginPath();
        uiCtx.moveTo(0, pointer.y + 0.5); uiCtx.lineTo(W, pointer.y + 0.5);
        uiCtx.moveTo(pointer.x + 0.5, 0); uiCtx.lineTo(pointer.x + 0.5, H);
        uiCtx.stroke();
      }
    }
  } else if (hover) {
    const x = hover.x / s, y = hover.y / s, w = hover.width / s, h = hover.height / s;
    uiCtx.clearRect(x, y, w, h);
    uiCtx.fillStyle = "rgba(255, 207, 26, .12)";
    uiCtx.fillRect(x, y, w, h);
    uiCtx.strokeStyle = YELLOW;
    uiCtx.lineWidth = 3;
    uiCtx.strokeRect(x + 1.5, y + 1.5, w - 3, h - 3);
    pill(uiCtx, `${hover.width} × ${hover.height}`, x + 8, y + 8);
  }
  drawLoupe();
}

/** A magnified view of the pixels under the pointer, for exact edges. */
function drawLoupe() {
  if (mode !== "area" || !pointer) { loupe.hidden = true; return; }
  const s = scale();
  const fx = Math.floor(pointer.x * s), fy = Math.floor(pointer.y * s);
  const n = 11; // frame pixels across
  const cell = loupeCanvas.width / n;
  loupeCtx.imageSmoothingEnabled = false;
  loupeCtx.fillStyle = "#000";
  loupeCtx.fillRect(0, 0, loupeCanvas.width, loupeCanvas.height);
  loupeCtx.drawImage(frame, fx - (n >> 1), fy - (n >> 1), n, n, 0, 0, loupeCanvas.width, loupeCanvas.height);
  loupeCtx.strokeStyle = "rgba(0, 0, 0, .18)";
  loupeCtx.lineWidth = 1;
  for (let i = 1; i < n; i++) {
    loupeCtx.beginPath();
    loupeCtx.moveTo(i * cell + 0.5, 0); loupeCtx.lineTo(i * cell + 0.5, loupeCanvas.height);
    loupeCtx.moveTo(0, i * cell + 0.5); loupeCtx.lineTo(loupeCanvas.width, i * cell + 0.5);
    loupeCtx.stroke();
  }
  loupeCtx.strokeStyle = YELLOW;
  loupeCtx.lineWidth = 2;
  loupeCtx.strokeRect((n >> 1) * cell, (n >> 1) * cell, cell, cell);
  loupeLabel.textContent = `${fx}, ${fy}`;

  // Beside the pointer, flipped near the right and bottom edges.
  const size = 132, gap = 24;
  let left = pointer.x + gap, top = pointer.y + gap;
  if (left + size > window.innerWidth - 8) left = pointer.x - gap - size;
  if (top + size + 30 > window.innerHeight - 8) top = pointer.y - gap - size - 30;
  loupe.style.left = `${left}px`;
  loupe.style.top = `${top}px`;
  loupe.hidden = false;
}

function resize() {
  const dpr = window.devicePixelRatio || 1;
  ui.width = Math.round(window.innerWidth * dpr);
  ui.height = Math.round(window.innerHeight * dpr);
  uiCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  schedule();
}

window.addEventListener("resize", resize);

window.addEventListener("mousemove", (e) => {
  pointer = { x: e.clientX, y: e.clientY };
  updateHover();
  schedule();
});

window.addEventListener("mousedown", (e) => {
  if (e.button === 2) return cancel();
  if (e.button !== 0) return;
  pointer = { x: e.clientX, y: e.clientY };
  if (mode === "area") drag = { ...pointer };
  schedule();
});

window.addEventListener("mouseup", (e) => {
  if (e.button !== 0) return;
  pointer = { x: e.clientX, y: e.clientY };
  if (mode === "window") {
    updateHover();
    if (hover) finish({ kind: "window", id: hover.id });
    return;
  }
  const r = selectionRect();
  drag = null;
  if (!r || r.w < 3 || r.h < 3) return schedule(); // a click, not a drag
  const s = scale();
  finish({
    kind: "area",
    x: Math.round(r.x * s), y: Math.round(r.y * s),
    width: Math.round(r.w * s), height: Math.round(r.h * s),
  });
});

window.addEventListener("contextmenu", (e) => e.preventDefault());

window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") { e.preventDefault(); cancel(); }
  else if (e.key === " ") { e.preventDefault(); setMode(mode === "area" ? "window" : "area"); }
});

async function start() {
  info = await invoke("overlay_info");
  if (!info) return cancel();
  const bytes = await invoke("overlay_frame");
  frame.width = info.width;
  frame.height = info.height;
  frame.getContext("2d").putImageData(new ImageData(new Uint8ClampedArray(bytes), info.width, info.height), 0, 0);
  resize();
  setMode(info.mode);
  await invoke("overlay_ready");
}

start().catch((e) => { console.error(e); cancel(); });
