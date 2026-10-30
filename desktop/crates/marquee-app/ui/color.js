// The color picker, on the capture overlay's frozen frame (Rust starts the overlay in
// "color" mode, or All-in-One's Color button switches to it). A loupe magnifies the pixels
// around the pointer; click or Enter copies the center one. Arrow keys move one pixel
// (Shift for 10), Esc cancels.
"use strict";

const ColorPick = (() => {
  const CELLS = 15; // pixels across the loupe
  const CELL = 10; // CSS pixels per magnified pixel
  const { invoke } = window.__TAURI__.core;

  let active = false;
  let px = null;
  let canvas = null, ctx = null, hint = null;
  let s = 1;
  let point = null; // frame pixel being sampled
  let pointerCss = null;
  let queued = false;
  let hintTimer = 0;

  const hex = (x, y) => {
    const i = (y * px.width + x) * 4;
    return "#" + [px.data[i], px.data[i + 1], px.data[i + 2]].map((v) => v.toString(16).padStart(2, "0")).join("").toUpperCase();
  };

  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; draw(); });
  }

  function draw() {
    if (!active) return;
    const W = window.innerWidth, H = window.innerHeight;
    ctx.clearRect(0, 0, W, H);
    if (!point) return;
    const size = CELLS * CELL;
    const at = pointerCss ?? { x: point.x / s, y: point.y / s };
    // Below and to the right of the pointer, flipped near the screen's edges.
    let left = at.x + 22, top = at.y + 22;
    if (left + size > W - 8) left = at.x - 22 - size;
    if (top + size + 40 > H - 8) top = at.y - 22 - size - 40;

    ctx.save();
    ctx.shadowColor = "rgba(0, 0, 0, .35)";
    ctx.shadowBlur = 18;
    ctx.fillStyle = "#1D1D1F";
    ctx.beginPath();
    ctx.roundRect(left - 3, top - 3, size + 6, size + 40, 14);
    ctx.fill();
    ctx.restore();

    ctx.save();
    ctx.beginPath();
    ctx.roundRect(left, top, size, size, 11);
    ctx.clip();
    const half = (CELLS - 1) / 2;
    for (let j = 0; j < CELLS; j++) {
      for (let i = 0; i < CELLS; i++) {
        const x = point.x + i - half, y = point.y + j - half;
        const inside = x >= 0 && y >= 0 && x < px.width && y < px.height;
        ctx.fillStyle = inside ? hex(x, y) : "#000000";
        ctx.fillRect(left + i * CELL, top + j * CELL, CELL, CELL);
      }
    }
    ctx.strokeStyle = "rgba(0, 0, 0, .12)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let k = 1; k < CELLS; k++) {
      ctx.moveTo(left + k * CELL + 0.5, top); ctx.lineTo(left + k * CELL + 0.5, top + size);
      ctx.moveTo(left, top + k * CELL + 0.5); ctx.lineTo(left + size, top + k * CELL + 0.5);
    }
    ctx.stroke();
    const cx = left + half * CELL, cy = top + half * CELL;
    ctx.lineWidth = 3;
    ctx.strokeStyle = "#000000";
    ctx.strokeRect(cx - 0.5, cy - 0.5, CELL + 1, CELL + 1);
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = "#FFFFFF";
    ctx.strokeRect(cx - 0.5, cy - 0.5, CELL + 1, CELL + 1);
    ctx.restore();

    const color = hex(point.x, point.y);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(left + 4, top + size + 10, 18, 18, 5);
    ctx.fill();
    ctx.strokeStyle = "rgba(255, 255, 255, .35)";
    ctx.lineWidth = 1;
    ctx.stroke();
    ctx.fillStyle = "#FFFFFF";
    ctx.font = '600 13px "Cascadia Mono", Consolas, monospace';
    ctx.textBaseline = "middle";
    ctx.fillText(color, left + 30, top + size + 19.5);
    ctx.fillStyle = "#A8A8B3";
    ctx.font = '12px "Segoe UI", system-ui, sans-serif';
    ctx.textAlign = "right";
    ctx.fillText(`${point.x}, ${point.y}`, left + size - 4, top + size + 19.5);
    ctx.textAlign = "left";
  }

  function pick() {
    if (!point) return;
    const color = hex(point.x, point.y);
    stop();
    invoke("overlay_pick_color", { hex: color });
  }

  function leave() {
    stop();
    invoke("overlay_finish", { selection: { kind: "cancel" } });
  }

  window.addEventListener("mousemove", (e) => {
    if (!active) return;
    pointerCss = { x: e.clientX, y: e.clientY };
    point = { x: Math.min(px.width - 1, Math.floor(e.clientX * s)), y: Math.min(px.height - 1, Math.floor(e.clientY * s)) };
    schedule();
  });

  window.addEventListener("mousedown", (e) => {
    if (!active) return;
    e.preventDefault();
    if (e.button === 2) return leave();
    if (e.button === 0) {
      point = { x: Math.min(px.width - 1, Math.floor(e.clientX * s)), y: Math.min(px.height - 1, Math.floor(e.clientY * s)) };
      pick();
    }
  });

  window.addEventListener("keydown", (e) => {
    if (!active) return;
    e.preventDefault();
    if (e.key === "Escape") return leave();
    if (e.key === "Enter" || e.key === " ") return pick();
    const step = e.shiftKey ? 10 : 1;
    const d = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[e.key];
    if (d && point) {
      point = { x: Math.min(px.width - 1, Math.max(0, point.x + d[0])), y: Math.min(px.height - 1, Math.max(0, point.y + d[1])) };
      // The loupe follows the pixel, not the (unmoved) pointer.
      pointerCss = { x: point.x / s, y: point.y / s };
      schedule();
    }
  });

  /** Starts picking over the frame overlay.js has drawn; `at` is the pointer, if known. */
  function start({ ui, uiContext, hintElement, bytes, width, height, at }) {
    active = true;
    canvas = ui;
    ctx = uiContext;
    hint = hintElement;
    px = { data: new Uint8ClampedArray(bytes), width, height };
    s = width / window.innerWidth;
    pointerCss = at ?? null;
    point = at ? { x: Math.floor(at.x * s), y: Math.floor(at.y * s) } : null;
    document.body.style.cursor = "crosshair";
    hint.innerHTML = "Click to copy a color · <kbd>←</kbd><kbd>→</kbd><kbd>↑</kbd><kbd>↓</kbd> one pixel · <kbd>Enter</kbd> copy · <kbd>Esc</kbd> cancel";
    hint.hidden = false;
    clearTimeout(hintTimer);
    hintTimer = setTimeout(() => (hint.hidden = true), 4000);
    schedule();
  }

  function stop() {
    active = false;
    px = null;
    clearTimeout(hintTimer);
    if (ctx) ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
  }

  return { start, stop, get active() { return active; } };
})();
