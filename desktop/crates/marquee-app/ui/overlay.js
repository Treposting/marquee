// The capture overlay. Rust freezes the display and this page shows the frame. Three ways in:
//   area   drag an area; letting go captures it (Space switches to picking a window)
//   window click a window to capture it (Space switches to dragging an area)
//   aio    All-in-One: a toolbar from the start, and a selection you can redraw, move, resize
//          and nudge before choosing what to do; with no selection, actions use the full screen
// Choices are reported to Rust in the frame's pixels.
"use strict";

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;
const YELLOW = "#FFCF1A";
const HANDLE = 8; // CSS pixels around a handle that grab it

const frame = document.getElementById("frame");
const ui = document.getElementById("ui");
const hint = document.getElementById("hint");
const toolbar = document.getElementById("toolbar");
const sizeLabel = document.getElementById("size");
const uiCtx = ui.getContext("2d");

let info = null;
let windowRects = []; // arrives just after the overlay shows
let aio = false;
let mode = "area";
let pointer = null; // CSS pixels
let sel = null; // the selection { x, y, w, h } in CSS pixels; null means the full screen
let gesture = null; // { kind: "new" | "move" | handle name, start, original }
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

/** The selection (or the full screen) in frame pixels, for an action. */
function area(copy = false) {
  const s = scale();
  const r = sel ?? { x: 0, y: 0, w: window.innerWidth, h: window.innerHeight };
  return {
    kind: "area", copy,
    x: Math.round(r.x * s), y: Math.round(r.y * s),
    width: Math.round(r.w * s), height: Math.round(r.h * s),
  };
}

const ACTIONS = {
  screenshot: () => finish(area()),
  copy: () => finish(area(true)),
  fullscreen: () => { sel = null; finish(area()); },
  window: () => setMode("window"),
  settings: () => finish({ kind: "settings" }),
  close: cancel,
};

function setMode(next) {
  mode = next;
  gesture = null;
  document.body.classList.toggle("window-mode", mode === "window");
  if (mode === "window") {
    hint.innerHTML = aio
      ? "Click a window · <kbd>Space</kbd> back to the area · <kbd>Esc</kbd> cancel"
      : "Click a window · <kbd>Space</kbd> drag an area · <kbd>Esc</kbd> cancel";
  } else if (aio) {
    hint.innerHTML = "Drag to select an area, or choose an action for the full screen";
  } else {
    hint.innerHTML = "Drag to select an area · <kbd>Space</kbd> pick a window · <kbd>Esc</kbd> cancel";
  }
  updateHover();
  schedule();
}

// Geometry

function handles(r) {
  const { x, y, w, h } = r;
  return {
    nw: [x, y], n: [x + w / 2, y], ne: [x + w, y], e: [x + w, y + h / 2],
    se: [x + w, y + h], s: [x + w / 2, y + h], sw: [x, y + h], w: [x, y + h / 2],
  };
}

function handleAt(p) {
  if (!sel) return null;
  for (const [name, [hx, hy]] of Object.entries(handles(sel))) {
    if (Math.abs(p.x - hx) <= HANDLE && Math.abs(p.y - hy) <= HANDLE) return name;
  }
  return null;
}

const inside = (p, r) => r && p.x > r.x && p.y > r.y && p.x < r.x + r.w && p.y < r.y + r.h;

function clampToScreen(r) {
  const W = window.innerWidth, H = window.innerHeight;
  return { ...r, x: Math.min(Math.max(0, r.x), W - r.w), y: Math.min(Math.max(0, r.y), H - r.h) };
}

function fromPoints(a, b) {
  return { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), w: Math.abs(b.x - a.x), h: Math.abs(b.y - a.y) };
}

function resized(r, handle, p) {
  let left = r.x, top = r.y, right = r.x + r.w, bottom = r.y + r.h;
  if (handle.includes("w")) left = p.x;
  if (handle.includes("e")) right = p.x;
  if (handle.includes("n")) top = p.y;
  if (handle.includes("s")) bottom = p.y;
  return fromPoints({ x: left, y: top }, { x: right, y: bottom });
}

function updateHover() {
  hover = null;
  if (mode !== "window" || !pointer) return;
  const s = scale();
  const px = pointer.x * s, py = pointer.y * s;
  // Front to back: the first window under the pointer is the visible one.
  hover = windowRects.find((w) => px >= w.x && py >= w.y && px < w.x + w.width && py < w.y + w.height) ?? null;
}

function updateCursor() {
  if (!aio || mode !== "area" || !pointer || gesture) return;
  const h = handleAt(pointer);
  const cursors = { nw: "nwse-resize", se: "nwse-resize", ne: "nesw-resize", sw: "nesw-resize", n: "ns-resize", s: "ns-resize", e: "ew-resize", w: "ew-resize" };
  document.body.style.cursor = h ? cursors[h] : inside(pointer, sel) ? "move" : "";
}

// Drawing

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

  if (mode === "area" && sel && sel.w > 0 && sel.h > 0) {
    uiCtx.clearRect(sel.x, sel.y, sel.w, sel.h);
    uiCtx.strokeStyle = YELLOW;
    uiCtx.lineWidth = 1.5;
    uiCtx.strokeRect(sel.x - 0.75, sel.y - 0.75, sel.w + 1.5, sel.h + 1.5);
    if (aio && !gesture) {
      for (const [hx, hy] of Object.values(handles(sel))) {
        uiCtx.beginPath();
        uiCtx.arc(hx, hy, 4.5, 0, Math.PI * 2);
        uiCtx.fillStyle = "#fff";
        uiCtx.fill();
        uiCtx.lineWidth = 1.5;
        uiCtx.strokeStyle = YELLOW;
        uiCtx.stroke();
      }
    }
    if (!aio || gesture) pill(uiCtx, `${Math.round(sel.w * s)} × ${Math.round(sel.h * s)}`, sel.x, sel.y + sel.h + 8);
  } else if (mode === "window" && hover) {
    const x = hover.x / s, y = hover.y / s, w = hover.width / s, h = hover.height / s;
    uiCtx.clearRect(x, y, w, h);
    uiCtx.fillStyle = "rgba(255, 207, 26, .12)";
    uiCtx.fillRect(x, y, w, h);
    uiCtx.strokeStyle = YELLOW;
    uiCtx.lineWidth = 3;
    uiCtx.strokeRect(x + 1.5, y + 1.5, w - 3, h - 3);
    pill(uiCtx, `${hover.width} × ${hover.height}`, x + 8, y + 8);
  }
  placeToolbar();
}

/** Under the selection (above it, or inside, when there's no room), or bottom center. */
function placeToolbar() {
  // The hint only helps before the first drag.
  hint.hidden = !!sel || !!gesture;
  if (!aio) return;
  const hidden = mode !== "area" || !!gesture;
  toolbar.hidden = hidden;
  if (hidden) return;
  const s = scale();
  sizeLabel.textContent = sel ? `${Math.round(sel.w * s)} × ${Math.round(sel.h * s)}` : "Full screen";
  const W = window.innerWidth, H = window.innerHeight;
  const tw = toolbar.offsetWidth, th = toolbar.offsetHeight, gap = 12;
  let x, y;
  if (sel) {
    x = sel.x + sel.w / 2 - tw / 2;
    y = sel.y + sel.h + gap;
    if (y + th > H - 8) y = sel.y - th - gap;
    if (y < 8) y = sel.y + sel.h - th - gap;
  } else {
    x = W / 2 - tw / 2;
    y = H - th - 40;
  }
  toolbar.style.left = `${Math.min(Math.max(8, x), W - tw - 8)}px`;
  toolbar.style.top = `${Math.min(Math.max(8, y), H - th - 8)}px`;
}

function resize() {
  const dpr = window.devicePixelRatio || 1;
  ui.width = Math.round(window.innerWidth * dpr);
  ui.height = Math.round(window.innerHeight * dpr);
  uiCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  schedule();
}

// Input

window.addEventListener("resize", resize);

window.addEventListener("mousemove", (e) => {
  pointer = { x: e.clientX, y: e.clientY };
  if (gesture) {
    const clamped = { x: Math.min(Math.max(0, pointer.x), window.innerWidth), y: Math.min(Math.max(0, pointer.y), window.innerHeight) };
    if (gesture.kind === "new") sel = fromPoints(gesture.start, clamped);
    else if (gesture.kind === "move") {
      sel = clampToScreen({ ...gesture.original, x: gesture.original.x + pointer.x - gesture.start.x, y: gesture.original.y + pointer.y - gesture.start.y });
    } else sel = resized(gesture.original, gesture.kind, clamped);
  }
  updateHover();
  updateCursor();
  schedule();
});

window.addEventListener("mousedown", (e) => {
  if (e.target.closest?.("#toolbar")) return;
  if (e.button === 2) return cancel();
  if (e.button !== 0 || mode !== "area") return;
  pointer = { x: e.clientX, y: e.clientY };
  const handle = aio ? handleAt(pointer) : null;
  if (handle) gesture = { kind: handle, start: pointer, original: sel };
  else if (aio && inside(pointer, sel)) gesture = { kind: "move", start: pointer, original: sel };
  else gesture = { kind: "new", start: pointer, original: sel };
  schedule();
});

window.addEventListener("mouseup", (e) => {
  if (e.button !== 0) return;
  pointer = { x: e.clientX, y: e.clientY };
  if (mode === "window") {
    if (e.target.closest?.("#toolbar")) return;
    updateHover();
    if (hover) finish({ kind: "window", id: hover.id });
    return;
  }
  if (!gesture) return;
  const ended = gesture;
  gesture = null;
  // A click or a tiny drag keeps what was selected before.
  if (!sel || sel.w < 4 || sel.h < 4) sel = ended.original;
  if (sel) sel = { x: Math.round(sel.x), y: Math.round(sel.y), w: Math.round(sel.w), h: Math.round(sel.h) };
  if (!aio && sel && ended.kind === "new" && sel !== ended.original) return finish(area());
  updateCursor();
  schedule();
});

window.addEventListener("contextmenu", (e) => e.preventDefault());

window.addEventListener("keydown", (e) => {
  const key = e.key;
  if (key === "Escape") { e.preventDefault(); return cancel(); }
  if (key === " ") { e.preventDefault(); return setMode(mode === "area" ? "window" : "area"); }
  if (!aio || mode !== "area") return;
  if (key === "Enter") { e.preventDefault(); ACTIONS.screenshot(); }
  else if (e.ctrlKey && key.toLowerCase() === "c") { e.preventDefault(); ACTIONS.copy(); }
  else if (!e.ctrlKey && key.toLowerCase() === "f") { e.preventDefault(); ACTIONS.fullscreen(); }
  else if (!e.ctrlKey && key.toLowerCase() === "w") { e.preventDefault(); ACTIONS.window(); }
  else if (key === "Delete" || key === "Backspace") { e.preventDefault(); sel = null; schedule(); }
  else if (key.startsWith("Arrow") && sel) {
    e.preventDefault();
    const step = e.shiftKey ? 10 : 1;
    const dx = key === "ArrowLeft" ? -step : key === "ArrowRight" ? step : 0;
    const dy = key === "ArrowUp" ? -step : key === "ArrowDown" ? step : 0;
    sel = clampToScreen({ ...sel, x: sel.x + dx, y: sel.y + dy });
    schedule();
  }
});

for (const button of toolbar.querySelectorAll("[data-action]")) {
  button.addEventListener("click", () => ACTIONS[button.dataset.action]());
}

/** Starts a capture session. The window stays loaded between captures (Rust only hides it),
 *  so everything from the last one is reset here. */
async function start() {
  info = await invoke("overlay_info");
  if (!info) return;
  aio = info.mode === "aio";
  finished = false;
  sel = null;
  gesture = null;
  hover = null;
  pointer = null;
  windowRects = [];
  document.body.style.cursor = "";
  const bytes = await invoke("overlay_frame");
  frame.width = info.width;
  frame.height = info.height;
  frame.getContext("2d").putImageData(new ImageData(new Uint8ClampedArray(bytes), info.width, info.height), 0, 0);
  resize();
  setMode(info.mode === "window" ? "window" : "area");
  draw();
  await invoke("overlay_ready");
  windowRects = await invoke("overlay_windows");
  updateHover();
  schedule();
}

listen("overlay-start", () => start().catch((e) => { console.error(e); cancel(); }));
start().catch((e) => { console.error(e); cancel(); });
