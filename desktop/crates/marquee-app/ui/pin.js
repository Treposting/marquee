// A pinned screenshot. Drag to move, scroll for opacity, Ctrl+scroll or Ctrl+= / Ctrl+- to
// zoom, double-click or Esc to close, right-click for the menu (built in Rust, pin_menu).
"use strict";

const { invoke, convertFileSrc } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;
const current = window.__TAURI__.window.getCurrentWindow();

const image = document.getElementById("image");
const status = document.getElementById("status");
let opacity = 1;
let statusTimer = 0;

function flash(text) {
  if (!text) return;
  status.textContent = text;
  status.hidden = false;
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => (status.hidden = true), 1300);
}

function setOpacity(value) {
  opacity = Math.min(1, Math.max(0.2, value));
  image.style.opacity = String(opacity);
}

function act(action) {
  if (action.startsWith("opacity-")) return setOpacity(Number(action.slice(8)) / 100);
  if (action === "zoom-in") return invoke("pin_zoom", { factor: 1.15 });
  if (action === "zoom-out") return invoke("pin_zoom", { factor: 1 / 1.15 });
  return invoke("pin_action", { action }).then(flash).catch((e) => flash(String(e)));
}

// Dragging starts once the pointer moves, so a double-click still closes the pin.
let press = null;
document.addEventListener("mousedown", (e) => {
  if (e.button === 0 && !e.target.closest("#close")) press = { x: e.screenX, y: e.screenY };
});
document.addEventListener("mousemove", (e) => {
  if (press && Math.hypot(e.screenX - press.x, e.screenY - press.y) > 3) {
    press = null;
    current.startDragging().catch(() => {});
  }
});
document.addEventListener("mouseup", () => (press = null));
document.addEventListener("dblclick", (e) => { if (!e.target.closest("#close")) act("close"); });
document.getElementById("close").addEventListener("click", () => act("close"));
document.addEventListener("contextmenu", (e) => { e.preventDefault(); invoke("pin_menu"); });

document.addEventListener("wheel", (e) => {
  e.preventDefault();
  if (e.ctrlKey) invoke("pin_zoom", { factor: e.deltaY < 0 ? 1.1 : 1 / 1.1 });
  else setOpacity(opacity - Math.sign(e.deltaY) * 0.08);
}, { passive: false });

document.addEventListener("keydown", (e) => {
  const key = e.key.toLowerCase();
  if (key === "escape") act("close");
  else if (e.ctrlKey && key === "c") act("copy");
  else if (e.ctrlKey && key === "s") { e.preventDefault(); act("save"); }
  else if (e.ctrlKey && (key === "=" || key === "+")) { e.preventDefault(); act("zoom-in"); }
  else if (e.ctrlKey && key === "-") { e.preventDefault(); act("zoom-out"); }
  else return;
});

listen("pin-command", (e) => act(e.payload));

invoke("pin_info").then((info) => {
  image.addEventListener("load", () => invoke("pin_ready"), { once: true });
  image.src = convertFileSrc(info.path);
}).catch((e) => console.error(e));
