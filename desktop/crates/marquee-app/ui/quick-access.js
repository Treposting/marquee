// Quick Access. Rust keeps the stack of recent captures; this page shows it, sizes the window
// to fit (quick_access_layout), and hides each thumbnail after Settings' timeout.
"use strict";

const { invoke, convertFileSrc } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const stack = document.getElementById("stack");
const tuckButton = document.getElementById("tuck");
const tab = document.getElementById("tab");
const tabCount = document.getElementById("tab-count");

let items = [];
let tucked = false;
let timeout = 20;
const remaining = new Map(); // id → milliseconds left before it hides
const hovered = new Set();

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") node.className = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  node.append(...children.filter((c) => c != null));
  return node;
}

function icon(id) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", `#${id}`);
  svg.append(use);
  svg.setAttribute("aria-hidden", "true");
  return svg;
}

function flash(card, text) {
  card.querySelector(".status")?.remove();
  const status = el("div", { class: "status", role: "status" }, text);
  card.append(status);
  setTimeout(() => status.remove(), 1400);
}

function run(card, promise, done) {
  promise.then(() => done && flash(card, done)).catch((e) => flash(card, String(e)));
}

function dismiss(id) {
  remaining.delete(id);
  invoke("quick_access_dismiss", { id });
}

function card(item) {
  const width = 224; // #stack's content width
  const height = Math.round(Math.min(180, Math.max(80, (width * item.height) / item.width)));
  const node = el("article", { class: "card", "aria-label": `Screenshot, ${item.width} by ${item.height}` },
    el("img", { class: "thumb", src: convertFileSrc(item.thumb), alt: "", style: `height:${height}px`, draggable: "false" }));
  node.append(
    el("div", { class: "actions" },
      el("button", { class: "big primary", onclick: () => run(node, invoke("library_copy", { id: item.id }), "Copied") }, "Copy"),
      el("button", { class: "big", onclick: () => run(node, invoke("library_save", { id: item.id }), "Saved") }, "Save")),
    el("div", { class: "corner" },
      el("button", { "aria-label": "Open", title: "Open", onclick: () => run(node, invoke("library_open", { id: item.id })) }, icon("q-open")),
      el("button", { "aria-label": "Show in folder", title: "Show in folder", onclick: () => run(node, invoke("library_reveal", { id: item.id })) }, icon("q-folder")),
      el("button", { "aria-label": "Close", title: "Close", onclick: () => dismiss(item.id) }, icon("q-close"))),
  );
  node.addEventListener("mouseenter", () => hovered.add(item.id));
  node.addEventListener("mouseleave", () => {
    hovered.delete(item.id);
    if (remaining.has(item.id)) remaining.set(item.id, timeout * 1000); // a fresh wait after a look
  });
  return node;
}

async function refresh() {
  const snapshot = await invoke("quick_access_items");
  items = snapshot.items;
  tucked = snapshot.tucked;
  timeout = snapshot.timeout;
  for (const id of [...remaining.keys()]) if (!items.some((i) => i.id === id)) remaining.delete(id);
  for (const item of items) if (!remaining.has(item.id)) remaining.set(item.id, timeout * 1000);

  stack.replaceChildren(...items.map(card));
  stack.hidden = tucked;
  tuckButton.hidden = tucked;
  tab.hidden = !tucked;
  tabCount.textContent = items.length > 1 ? String(items.length) : "";
  await new Promise(requestAnimationFrame);
  const height = items.length ? stack.scrollHeight : 0;
  await invoke("quick_access_layout", { height: tucked ? Math.max(height, 80) : height });
}

tuckButton.addEventListener("click", () => invoke("quick_access_tuck", { tucked: true }).then(refresh));
tab.addEventListener("click", () => invoke("quick_access_tuck", { tucked: false }).then(refresh));

// Thumbnails hide on their own unless you're looking at them or they're tucked away.
let last = performance.now();
setInterval(() => {
  const now = performance.now();
  const step = now - last;
  last = now;
  if (tucked || timeout === 0) return;
  for (const [id, left] of remaining) {
    if (hovered.has(id)) continue;
    if (left - step <= 0) dismiss(id);
    else remaining.set(id, left - step);
  }
}, 250);

listen("quick-access-changed", refresh);
refresh().catch((e) => console.error(e));
