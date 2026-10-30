// The Marquee window. Talks to Rust through Tauri commands (withGlobalTauri).
"use strict";

const { invoke, convertFileSrc } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const ACTION_INFO = {
  allInOne: { icon: "i-grid", sub: "Select an area, then choose what to do" },
  captureArea: { icon: "i-area", sub: "Drag over part of the screen", tile: "Area" },
  captureWindow: { icon: "i-window", sub: "Click any window", tile: "Window" },
  captureFullscreen: { icon: "i-display", sub: "The screen under the pointer", tile: "Full Screen" },
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

for (const item of $$(".nav-item, .update-pill")) item.addEventListener("click", () => showPage(item.dataset.page));

// Home

function renderHome() {
  const aio = actions.find((a) => a.id === "allInOne");
  $("#aio-keys").replaceWith(Object.assign(keyCaps(aio?.shortcut), { id: "aio-keys" }));

  const groups = $("#action-groups");
  groups.replaceChildren();
  for (const category of Object.keys(CATEGORY_TITLES)) {
    const items = actions.filter((a) => a.category === category && a.id !== "allInOne" && a.available);
    if (!items.length) continue;
    const grid = el("div", { class: "tiles" });
    for (const action of items) {
      const info = ACTION_INFO[action.id] ?? {};
      grid.append(
        el("button", { class: "tile glass", onclick: () => perform(action.id) },
          el("span", { class: "tile-top" },
            el("span", { class: "tile-icon" }, icon(info.icon ?? "i-grid")),
            action.shortcut ? keyCaps(action.shortcut) : null),
          el("span", { class: "tile-title" }, info.tile ?? action.title),
          el("span", { class: "tile-sub" }, info.sub ?? "")),
      );
    }
    groups.append(el("h3", { class: "section-title" }, CATEGORY_TITLES[category]), grid);
  }

  // Features still being ported sit together in one quiet row instead of a wall of "Soon" tiles.
  const later = actions.filter((a) => !a.available);
  if (later.length) {
    groups.append(
      el("h3", { class: "section-title" }, "Coming to Windows"),
      el("ul", { class: "coming glass" }, ...later.map((action) => {
        const info = ACTION_INFO[action.id] ?? {};
        return el("li", { title: info.sub ?? "" }, icon(info.icon ?? "i-grid"), info.tile ?? action.title);
      })),
    );
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
  renderColors();
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
        el("button", { class: "round", title: "Annotate", "aria-label": "Annotate", onclick: () => shotAction(node, "library_annotate", item) }, icon("i-annotate")),
        el("button", { class: "round", title: "Pin above other windows", "aria-label": "Pin", onclick: () => shotAction(node, "library_pin", item) }, icon("i-pin")),
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
let categories = [];

/** Category chips after the built-in filters, in the page's filter row. */
function renderCategoryChips() {
  const bar = $(".clip-filters");
  $$(".category", bar).forEach((b) => b.remove());
  if (clipFilter.startsWith("category:") && !categories.some((c) => `category:${c.id}` === clipFilter)) clipFilter = "all";
  for (const c of categories) {
    const b = el("button", { role: "radio", class: "category", "data-clip-filter": `category:${c.id}` }, c.name);
    b.style.setProperty("--tint", ClipCards.TINTS[c.tint]);
    bar.append(b);
  }
  for (const b of $$("[data-clip-filter]")) b.setAttribute("aria-checked", String(b.dataset.clipFilter === clipFilter));
}

function clipMenu(event, item, card) {
  const act = (command, done) => invoke(command, { id: item.id })
    .then(() => done && shotStatus(card, done))
    .catch((e) => shotStatus(card, String(e)));
  const tail = [];
  if (item.sourceAppId) {
    tail.push({ label: `Ignore ${item.sourceAppName ?? item.sourceAppId}`, run: () => act("clip_ignore_app") });
  }
  tail.push({ label: "Delete", danger: true, run: () => act("clip_delete") });
  ClipCards.menu(event, item, {
    invoke,
    categories,
    actions: [
      { label: "Copy", run: () => act("clip_copy", "Copied") },
      { label: item.pinned ? "Unpin" : "Pin", run: () => act("clip_pin") },
    ],
    tail,
  });
}

async function renderClipboard() {
  categories = await invoke("clip_categories");
  renderCategoryChips();
  renderCategories();
  const items = await invoke("clip_list", { filter: clipFilter, query: $("#clip-search").value });
  $("#clip-grid").replaceChildren(...items.map((item) => {
    const card = ClipCards.render(item, { convertFileSrc, categories });
    card.tabIndex = 0;
    const act = (command, done) => invoke(command, { id: item.id })
      .then(() => done && shotStatus(card, done))
      .catch((e) => shotStatus(card, String(e)));
    card.append(el("div", { class: "clip-actions" },
      el("button", { title: "Copy", "aria-label": "Copy", onclick: () => act("clip_copy", "Copied") }, icon("i-copy")),
      el("button", { title: item.pinned ? "Unpin" : "Pin", "aria-label": item.pinned ? "Unpin" : "Pin", "aria-pressed": String(item.pinned), onclick: () => act("clip_pin") }, icon("i-pin")),
      el("button", { title: "More", "aria-label": "More", onclick: (e) => clipMenu(e, item, card) }, icon("i-more"))));
    card.addEventListener("dblclick", () => act("clip_copy", "Copied"));
    card.addEventListener("contextmenu", (e) => clipMenu(e, item, card));
    card.addEventListener("keydown", (e) => {
      if (e.key === "Delete") act("clip_delete");
      else if (e.key === "Enter") act("clip_copy", "Copied");
      else if (e.key === "ContextMenu" || (e.shiftKey && e.key === "F10")) {
        const r = card.getBoundingClientRect();
        clipMenu({ preventDefault() {}, clientX: r.left + 12, clientY: r.top + 40 }, item, card);
      }
    });
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

/** Settings → Clipboard → Categories: rename, recolor or delete each one. */
function renderCategories() {
  const list = $("#category-list");
  if (list.contains(document.activeElement)) return; // Don't rebuild under the user's typing.
  $("#categories-empty").hidden = categories.length > 0;
  list.replaceChildren(...categories.map((c) => {
    const update = (changes) => invoke("clip_category_update", { id: c.id, name: c.name, tint: c.tint, ...changes }).catch(showError);
    const name = el("input", { type: "text", value: c.name, "aria-label": "Category name", spellcheck: "false" });
    name.addEventListener("change", () => update({ name: name.value }));
    name.addEventListener("keydown", (e) => { if (e.key === "Enter") name.blur(); });
    const dots = el("div", { class: "tint-dots", role: "radiogroup", "aria-label": `Color for ${c.name}` },
      ...Object.entries(ClipCards.TINTS).map(([tint, color]) => {
        const dot = el("button", { role: "radio", "aria-checked": String(tint === c.tint), "aria-label": tint, title: tint, onclick: () => update({ tint }) });
        dot.style.setProperty("--tint", color);
        return dot;
      }));
    return el("div", { class: "row category-row" }, name, dots,
      el("button", { class: "icon-button", title: "Delete category", "aria-label": `Delete ${c.name}`, onclick: () => {
        if (confirm(`Delete "${c.name}"? Its items stay in your history.`)) invoke("clip_category_delete", { id: c.id }).catch(showError);
      } }, icon("i-trash")));
  }));
}

$("#category-form").addEventListener("submit", (e) => {
  e.preventDefault();
  const name = $("#category-input").value.trim();
  if (!name) return;
  const tints = Object.keys(ClipCards.TINTS);
  invoke("clip_category_add", { name, tint: tints[categories.length % tints.length], item: null }).catch(showError);
  $("#category-input").value = "";
});

$("#clip-search").addEventListener("input", renderClipboard);
$(".clip-filters").addEventListener("click", (e) => {
  const button = e.target.closest("[data-clip-filter]");
  if (!button) return;
  clipFilter = button.dataset.clipFilter;
  renderClipboard();
});
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

// Colors

async function renderColors() {
  const colors = await invoke("colors_list");
  for (const b of $$("[data-color-format]")) b.setAttribute("aria-checked", String(b.dataset.colorFormat === prefs.colorFormat));
  $("#color-grid").replaceChildren(...colors.map((c) => {
    const node = el("div", { class: "color", role: "button", tabindex: "0", title: `Copy ${c.text}`, "aria-label": `${c.hex}. Copy as ${c.text}` },
      el("span", { class: "swatch", style: `--c:${c.hex}` }),
      el("span", { class: "values" },
        el("span", { class: "hex" }, c.hex),
        el("span", { class: "sub" }, `RGB ${c.rgb}`),
        el("span", { class: "sub" }, `HSL ${c.hsl}`)),
      el("span", { class: "remove", role: "button", tabindex: "0", title: "Remove", "aria-label": `Remove ${c.hex}`, onclick: (e) => {
        e.stopPropagation();
        invoke("color_delete", { hex: c.hex });
      } }, icon("i-close")));
    const copy = () => invoke("color_copy", { hex: c.hex }).then((text) => shotStatus(node, `Copied ${text}`)).catch((e) => shotStatus(node, String(e)));
    node.addEventListener("click", copy);
    node.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); copy(); }
      else if (e.key === "Delete") invoke("color_delete", { hex: c.hex });
    });
    return node;
  }));
  $("#colors-empty").hidden = colors.length > 0;
  $("#colors-clear").hidden = colors.length === 0;
}

for (const b of $$("[data-color-format]")) {
  b.addEventListener("click", () => { prefs.colorFormat = b.dataset.colorFormat; save(); });
}
$("#colors-clear").addEventListener("click", () => {
  if (confirm("Clear all picked colors?")) invoke("colors_clear");
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

// Updates

let update = null;

function escapeHtml(text) {
  return text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

/** Release notes are short Markdown: headings, bullet lists, bold and code. Links become text. */
function renderNotes(markdown) {
  const inline = (line) => escapeHtml(line)
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>");
  let html = "";
  let list = false;
  for (const raw of markdown.split(/\r?\n/)) {
    const line = raw.trim();
    const bullet = /^[-*] (.*)/.exec(line);
    if (list && !bullet) { html += "</ul>"; list = false; }
    if (bullet) {
      if (!list) { html += "<ul>"; list = true; }
      html += `<li>${inline(bullet[1])}</li>`;
    } else if (/^#{1,6} /.test(line)) {
      html += `<h3>${inline(line.replace(/^#+ /, ""))}</h3>`;
    } else if (line) {
      html += `<p>${inline(line)}</p>`;
    }
  }
  return html + (list ? "</ul>" : "");
}

function renderUpdate() {
  if (!update) return;
  const a = update.available;
  const checked = update.lastChecked ? `Last checked ${when(update.lastChecked)}.` : "";
  $("#update-status-text").textContent = update.checking ? "Checking…"
    : a ? `Marquee ${a.version} is available.`
    : update.error ? update.error
    : `You have the latest version (${update.current}). ${checked}`;
  $("#update-check").disabled = update.checking || update.installing;
  $("#update-pill").hidden = !a;
  $("#update-pill-text").textContent = a ? `Update to ${a.version}` : "";

  $("#update-sub").textContent = `You have Marquee ${update.current}.`;
  $("#update-heading").textContent = a ? `Marquee ${a.version} is available` : update.checking ? "Checking for updates…" : "You're up to date";
  $("#update-detail").textContent = update.installing ? "Downloading… Marquee closes, updates and opens again."
    : a ? (a.canInstall ? "Marquee closes, installs the update and opens again." : "This copy was installed from the .msi. Download the new version from the release page.")
    : checked || "Marquee checks GitHub for new Windows previews.";
  $("#update-install").hidden = !a || !a.canInstall;
  $("#update-install").disabled = update.installing;
  $("#update-install").textContent = update.installing ? "Installing…" : "Install update";
  $("#update-page-link").hidden = !a;
  $("#update-check-big").hidden = !!a;
  $("#update-check-big").disabled = update.checking;
  $("#update-progress").hidden = !update.installing;
  $("#update-error").hidden = !update.error;
  $("#update-error").textContent = update.error ?? "";
  $("#update-notes").hidden = !a?.notes;
  $("#update-notes").innerHTML = a?.notes ? renderNotes(a.notes) : "";
}

async function refreshUpdate() {
  update = await invoke("update_status");
  renderUpdate();
}

async function checkForUpdates() {
  update = { ...(update ?? {}), checking: true };
  renderUpdate();
  update = await invoke("update_check");
  renderUpdate();
}

$("#update-check").addEventListener("click", checkForUpdates);
$("#update-check-big").addEventListener("click", checkForUpdates);
$("#update-install").addEventListener("click", () => {
  $("#update-bar").style.width = "0";
  invoke("update_install").catch(() => refreshUpdate());
});
$("#update-page-link").addEventListener("click", () => {
  if (update?.available) invoke("update_open_page").catch((e) => alert(String(e)));
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
  $("#version").textContent = `Marquee ${await invoke("app_version")}`;
  prefs = await invoke("get_prefs");
  actions = await invoke("list_actions");
  bindPrefs();
  await showSaveFolder();
  await renderLibrary();
  listen("library-changed", renderLibrary);
  await renderClipboard();
  listen("clipboard-changed", renderClipboard);
  // Rust changed a setting itself (e.g. "Ignore this app" from the panel).
  await renderColors();
  listen("colors-changed", renderColors);
  await refreshUpdate();
  listen("update-changed", refreshUpdate);
  listen("update-progress", (e) => ($("#update-bar").style.width = `${e.payload}%`));
  listen("prefs-changed", async () => { prefs = await invoke("get_prefs"); bindPrefs(); });
  renderHome();
  renderShortcuts();
  await showComingSoon();
  listen("coming-soon", showComingSoon);
  const page = await invoke("take_page");
  if (page) showPage(page);
  listen("show-page", (e) => { invoke("take_page"); showPage(e.payload); });
}

start().catch((e) => console.error(e));
