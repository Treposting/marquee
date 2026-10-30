// The Marquee window. Talks to Rust through Tauri commands (withGlobalTauri).
"use strict";

const { invoke, convertFileSrc } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const ACTION_INFO = {
  allInOne: { icon: "i-grid", sub: "Select an area, then choose what to do" },
  captureArea: { icon: "i-area", sub: "Drag over any part of the screen", tile: "Area" },
  captureWindow: { icon: "i-window", sub: "Click a window to capture it", tile: "Window" },
  captureFullscreen: { icon: "i-display", sub: "The display under the pointer", tile: "Full Screen" },
  captureScrolling: { icon: "i-scroll", sub: "One long screenshot as you scroll", tile: "Scrolling" },
  captureTimed: { icon: "i-timer", sub: "Full screen after 5 seconds", tile: "Self-Timer" },
  captureText: { icon: "i-text", sub: "Select text anywhere and copy it", tile: "Copy Text" },
  recordArea: { icon: "i-record", sub: "Video of an area, with audio", record: true },
  recordScreen: { icon: "i-video", sub: "Video of the whole display", record: true },
  measure: { icon: "i-ruler", sub: "Distances and sizes on screen" },
  pickColor: { icon: "i-eyedropper", sub: "Copy any color on screen", tile: "Color Picker" },
  clipboardHistory: { icon: "i-clipboard", sub: "Everything you've copied", tile: "Clipboard" },
};
const CATEGORY_TITLES = { Capture: "Capture", Record: "Record", Tools: "Tools", Clipboard: "Clipboard" };

let prefs = null;
let actions = [];

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

/** "Ctrl+Alt+Shift+A" as separate keys. */
function keyCaps(accel) {
  const span = el("span", { class: "keys" });
  if (!accel) return span;
  span.setAttribute("aria-label", accel.replaceAll("+", " "));
  for (const key of accel.split("+")) span.append(el("kbd", {}, key === "Super" ? "Win" : key));
  return span;
}

// Navigation

function showPage(name) {
  for (const item of $$(".nav-item")) {
    if (item.dataset.page === name) item.setAttribute("aria-current", "page");
    else item.removeAttribute("aria-current");
  }
  for (const page of $$(".page")) page.hidden = page.id !== `page-${name}`;
  $("main").scrollTop = 0;
}

for (const item of $$(".nav-item")) item.addEventListener("click", () => showPage(item.dataset.page));

// Home

function renderHome() {
  const aio = actions.find((a) => a.id === "allInOne");
  $("#aio-keys").replaceWith(Object.assign(keyCaps(aio?.shortcut), { id: "aio-keys" }));

  const groups = $("#action-groups");
  groups.replaceChildren();
  for (const category of Object.keys(CATEGORY_TITLES)) {
    const items = actions.filter((a) => a.category === category && a.id !== "allInOne");
    if (!items.length) continue;
    const grid = el("div", { class: "tiles" });
    for (const action of items) {
      const info = ACTION_INFO[action.id] ?? {};
      grid.append(
        el("button", { class: "tile glass", title: info.sub ?? "", onclick: () => perform(action.id) },
          el("span", { class: `tile-icon${info.record ? " record" : ""}` }, icon(info.icon ?? "i-grid")),
          el("span", { class: "tile-text" },
            el("span", { class: "tile-title" }, info.tile ?? action.title, action.available ? null : el("span", { class: "soon" }, "Soon")),
            el("span", { class: "tile-sub" }, info.sub ?? "")),
          keyCaps(action.shortcut)),
      );
    }
    groups.append(el("h3", { class: "section-title" }, CATEGORY_TITLES[category]), grid);
  }
}

function perform(id) {
  invoke("perform", { id }).catch(showError);
}

async function showComingSoon() {
  const title = await invoke("take_pending");
  if (!title) return;
  showPage("home");
  $("#coming-title").textContent = title;
  $("#coming-soon").hidden = false;
}

$("#coming-close").addEventListener("click", () => ($("#coming-soon").hidden = true));
$$("[data-action]").forEach((b) => b.addEventListener("click", () => perform(b.dataset.action)));

// Settings

function showError(message) {
  const box = $("#settings-error");
  box.textContent = message ?? "";
  box.hidden = !message;
}

async function save() {
  try {
    await invoke("set_prefs", { prefs });
    showError(null);
  } catch (e) {
    showError(String(e));
  }
  actions = await invoke("list_actions");
  renderHome();
  renderShortcuts();
  renderClipboard();
}

function bindPrefs() {
  for (const input of $$("[data-pref]")) {
    const key = input.dataset.pref;
    if (input.type === "checkbox") {
      const invert = "invert" in input.dataset;
      input.checked = invert ? !prefs[key] : !!prefs[key];
      input.onchange = () => { prefs[key] = invert ? !input.checked : input.checked; save(); };
    } else {
      input.value = String(prefs[key]);
      input.onchange = () => { prefs[key] = "number" in input.dataset ? Number(input.value) : input.value; save(); };
    }
  }
  renderIgnored();
}

function renderIgnored() {
  const list = $("#ignored-apps");
  list.replaceChildren(...prefs.ignoredApps.map((name) =>
    el("li", {}, name, el("button", {
      class: "icon-button", "aria-label": `Stop ignoring ${name}`,
      onclick: () => { prefs.ignoredApps = prefs.ignoredApps.filter((a) => a !== name); renderIgnored(); save(); },
    }, icon("i-close")))));
}

$("#ignore-form").addEventListener("submit", (e) => {
  e.preventDefault();
  const name = $("#ignore-input").value.trim();
  if (name && !prefs.ignoredApps.some((a) => a.toLowerCase() === name.toLowerCase())) {
    prefs.ignoredApps.push(name);
    renderIgnored();
    save();
  }
  $("#ignore-input").value = "";
});

for (const tab of $$("[role=tab]")) {
  tab.addEventListener("click", () => {
    for (const t of $$("[role=tab]")) t.setAttribute("aria-selected", String(t === tab));
    for (const panel of $$(".tab-panel")) panel.hidden = panel.dataset.panel !== tab.dataset.tab;
  });
}

// Library

const relative = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });

/** "2 minutes ago", "yesterday", or the date for older captures. */
function when(iso) {
  const date = new Date(iso);
  const seconds = (date - Date.now()) / 1000;
  const units = [["second", 60], ["minute", 60], ["hour", 24], ["day", 7]];
  let value = seconds;
  for (const [unit, size] of units) {
    if (Math.abs(value) < size) return relative.format(Math.round(value), unit);
    value /= size;
  }
  return date.toLocaleDateString();
}

function shotStatus(node, text) {
  node.querySelector(".shot-status")?.remove();
  const status = el("div", { class: "shot-status", role: "status" }, text);
  node.append(status);
  setTimeout(() => status.remove(), 1500);
}

function shotAction(node, command, item, done) {
  invoke(command, { id: item.id }).then(() => done && shotStatus(node, done)).catch((e) => shotStatus(node, String(e)));
}

async function renderLibrary() {
  const items = await invoke("library_list");
  const grid = $("#library-grid");
  grid.replaceChildren(...items.map((item) => {
    const node = el("article", { class: "shot", "aria-label": `Screenshot from ${when(item.created)}, ${item.width} by ${item.height}` },
      el("img", { src: convertFileSrc(item.thumb), alt: "", loading: "lazy", draggable: "false" }),
      el("div", { class: "shot-meta" }, el("span", {}, when(item.created)), el("span", {}, `${item.width} × ${item.height}`)));
    node.insertBefore(el("div", { class: "shot-actions" },
      el("button", { class: "big primary", onclick: () => shotAction(node, "library_copy", item, "Copied") }, "Copy"),
      el("button", { class: "big", onclick: () => shotAction(node, "library_save", item, "Saved") }, "Save"),
      el("div", { class: "shot-corner" },
        el("button", { class: "round", title: "Open", "aria-label": "Open", onclick: () => shotAction(node, "library_open", item) }, icon("i-open")),
        el("button", { class: "round", title: "Show in folder", "aria-label": "Show in folder", onclick: () => shotAction(node, "library_reveal", item) }, icon("i-folder")),
        el("button", { class: "round", title: "Delete", "aria-label": "Delete", onclick: () => shotAction(node, "library_delete", item) }, icon("i-trash")))),
    node.querySelector(".shot-meta"));
    return node;
  }));
  $("#library-empty").hidden = items.length > 0;
  $("#library-clear").hidden = items.length === 0;
}

$("#library-clear").addEventListener("click", () => {
  if (!confirm("Delete every screenshot in the library? Copies you saved to your folder stay.")) return;
  invoke("library_clear").catch((e) => alert(String(e)));
});

// Clipboard

let clipFilter = "all";

async function renderClipboard() {
  const items = await invoke("clip_list", { filter: clipFilter, query: $("#clip-search").value });
  $("#clip-grid").replaceChildren(...items.map((item) => {
    const card = ClipCards.render(item, { convertFileSrc });
    card.tabIndex = 0;
    const act = (command, done) => invoke(command, { id: item.id })
      .then(() => done && shotStatus(card, done))
      .catch((e) => shotStatus(card, String(e)));
    card.append(el("div", { class: "clip-actions" },
      el("button", { title: "Copy", "aria-label": "Copy", onclick: () => act("clip_copy", "Copied") }, icon("i-copy")),
      el("button", { title: item.pinned ? "Unpin" : "Pin", "aria-label": item.pinned ? "Unpin" : "Pin", "aria-pressed": String(item.pinned), onclick: () => act("clip_pin") }, icon("i-pin")),
      el("button", { title: "Delete", "aria-label": "Delete", onclick: () => act("clip_delete") }, icon("i-trash"))));
    card.addEventListener("dblclick", () => act("clip_copy", "Copied"));
    return card;
  }));
  const filtered = clipFilter !== "all" || $("#clip-search").value;
  $("#clip-empty").hidden = items.length > 0;
  $("#clip-empty-title").textContent = filtered ? "Nothing matches" : "Nothing copied yet";
  $("#clip-empty-text").textContent = filtered
    ? "Try other words or another filter."
    : "Text, links, images and files you copy show up here. Password managers are never recorded.";
  $("#clip-paused").hidden = !prefs.monitorPaused;
  $("#clip-pause").textContent = prefs.monitorPaused ? "Resume history" : "Pause history";
  const history = actions.find((a) => a.id === "clipboardHistory");
  $("#clip-keys").replaceChildren(history?.shortcut ? keyCaps(history.shortcut) : "a shortcut you set in Settings");
}

$("#clip-search").addEventListener("input", renderClipboard);
for (const button of $$("[data-clip-filter]")) {
  button.addEventListener("click", () => {
    clipFilter = button.dataset.clipFilter;
    for (const b of $$("[data-clip-filter]")) b.setAttribute("aria-checked", String(b === button));
    renderClipboard();
  });
}
$("#clip-pause").addEventListener("click", async () => {
  prefs.monitorPaused = !prefs.monitorPaused;
  await save();
  bindPrefs();
  renderClipboard();
});
$("#clip-clear").addEventListener("click", () => {
  if (!confirm("Clear clipboard history? Pinned items stay.")) return;
  invoke("clip_clear").catch((e) => alert(String(e)));
});

// Save folder

async function showSaveFolder() {
  $("#save-folder").textContent = await invoke("save_folder");
}

$("#choose-folder").addEventListener("click", async () => {
  try {
    const folder = await invoke("choose_save_folder");
    if (!folder) return;
    // Keep the page's copy in step, or the next save would put the old folder back.
    prefs.saveFolder = folder;
    $("#save-folder").textContent = folder;
    showError(null);
  } catch (e) {
    showError(String(e));
  }
});

// Shortcuts

const MODIFIERS = { Control: "Ctrl", Alt: "Alt", Shift: "Shift", Meta: "Super" };

/** A key event as an accelerator ("Ctrl+Alt+M"), or null if it's only modifiers. */
function accelerator(e) {
  if (e.key in MODIFIERS) return null;
  const mods = [e.ctrlKey && "Ctrl", e.altKey && "Alt", e.shiftKey && "Shift", e.metaKey && "Super"].filter(Boolean);
  if (!mods.length) return null;
  const code = e.code.replace(/^Key/, "").replace(/^Digit/, "");
  return [...mods, code].join("+");
}

function renderShortcuts() {
  const root = $("#shortcut-groups");
  root.replaceChildren();
  for (const category of Object.keys(CATEGORY_TITLES)) {
    const items = actions.filter((a) => a.category === category);
    const group = el("div", { class: "group glass" });
    for (const action of items) {
      const button = el("button", { class: "shortcut-button", "aria-label": `Shortcut for ${action.title}` });
      const show = () => button.replaceChildren(action.shortcut ? keyCaps(action.shortcut) : "Record shortcut");
      show();
      button.addEventListener("click", () => {
        button.classList.add("recording");
        button.replaceChildren("Press keys…");
      });
      button.addEventListener("blur", () => { button.classList.remove("recording"); show(); });
      button.addEventListener("keydown", (e) => {
        if (!button.classList.contains("recording")) return;
        e.preventDefault();
        if (e.key === "Escape") return button.blur();
        if (e.key === "Backspace" || e.key === "Delete") {
          prefs.shortcuts[action.id] = "";
        } else {
          const accel = accelerator(e);
          if (!accel) return;
          prefs.shortcuts[action.id] = accel;
        }
        button.classList.remove("recording");
        save();
      });
      group.append(el("div", { class: "row" }, el("span", {}, action.title), button));
    }
    root.append(el("h3", { class: "group-title" }, CATEGORY_TITLES[category]), group);
  }
}

// Start

async function start() {
  $("#version").textContent = `Version ${await invoke("app_version")} · early Windows build`;
  prefs = await invoke("get_prefs");
  actions = await invoke("list_actions");
  bindPrefs();
  await showSaveFolder();
  await renderLibrary();
  listen("library-changed", renderLibrary);
  await renderClipboard();
  listen("clipboard-changed", renderClipboard);
  renderHome();
  renderShortcuts();
  await showComingSoon();
  listen("coming-soon", showComingSoon);
  const page = await invoke("take_page");
  if (page) showPage(page);
  listen("show-page", (e) => { invoke("take_page"); showPage(e.payload); });
}

start().catch((e) => console.error(e));
