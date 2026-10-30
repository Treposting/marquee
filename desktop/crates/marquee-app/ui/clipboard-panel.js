// The Clipboard History panel: type to search, arrows to choose, Enter to paste into the app
// you were using. Rust opens it (Ctrl+Alt+Shift+V by default) and closes it when it loses focus.
"use strict";

const { invoke, convertFileSrc } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const search = document.getElementById("search");
const row = document.getElementById("row");
const empty = document.getElementById("empty");
const filterBar = document.querySelector(".filters");

let items = [];
let categories = [];
let selected = 0;
let filter = "all";

/** Category chips after the built-in filters; a deleted category's filter falls back to All. */
function renderCategoryChips() {
  filterBar.querySelectorAll(".category").forEach((b) => b.remove());
  if (filter.startsWith("category:") && !categories.some((c) => `category:${c.id}` === filter)) filter = "all";
  for (const c of categories) {
    const b = document.createElement("button");
    b.className = "category";
    b.setAttribute("role", "radio");
    b.dataset.filter = `category:${c.id}`;
    b.style.setProperty("--tint", ClipCards.TINTS[c.tint]);
    b.textContent = c.name;
    filterBar.append(b);
  }
  for (const b of filterBar.querySelectorAll("[data-filter]")) b.setAttribute("aria-checked", String(b.dataset.filter === filter));
}

async function refresh(keepSelection = true) {
  const id = items[selected]?.id;
  categories = await invoke("clip_categories");
  renderCategoryChips();
  items = await invoke("clip_list", { filter, query: search.value });
  selected = keepSelection && id ? Math.max(0, items.findIndex((i) => i.id === id)) : 0;
  row.replaceChildren(...items.map((item, i) => {
    const card = ClipCards.render(item, { index: i < 9 ? i + 1 : null, convertFileSrc, categories });
    card.setAttribute("role", "option");
    card.addEventListener("click", () => select(i));
    card.addEventListener("dblclick", () => paste(i));
    card.addEventListener("contextmenu", (e) => { select(i); showMenu(e, item, i); });
    return card;
  }));
  empty.hidden = items.length > 0;
  empty.textContent = search.value || filter !== "all"
    ? "Nothing matches."
    : "Things you copy show up here. Copy some text, a link, an image or a file to start.";
  select(selected);
}

function select(i) {
  if (!items.length) return;
  selected = Math.min(Math.max(0, i), items.length - 1);
  [...row.children].forEach((card, n) => {
    card.classList.toggle("selected", n === selected);
    card.setAttribute("aria-selected", String(n === selected));
  });
  row.children[selected]?.scrollIntoView({ block: "nearest", inline: "nearest" });
}

function paste(i) {
  const item = items[i];
  if (item) invoke("clip_paste", { id: item.id }).catch((e) => console.error(e));
}

function showMenu(event, item, i) {
  const tail = [];
  if (item.sourceAppId) {
    tail.push({ label: `Ignore ${item.sourceAppName ?? item.sourceAppId}`, run: () => invoke("clip_ignore_app", { id: item.id }) });
  }
  tail.push({ label: "Delete", keys: "Del", danger: true, run: () => invoke("clip_delete", { id: item.id }) });
  ClipCards.menu(event, item, {
    invoke,
    categories,
    actions: [
      { label: "Paste", keys: "Enter", run: () => paste(i) },
      { label: "Copy", run: () => invoke("clip_copy", { id: item.id }) },
      { label: item.pinned ? "Unpin" : "Pin", keys: "Ctrl+P", run: () => invoke("clip_pin", { id: item.id }) },
    ],
    tail,
  });
}

function close() {
  invoke("clip_close_panel");
}

filterBar.addEventListener("click", (e) => {
  const button = e.target.closest("[data-filter]");
  if (!button) return;
  filter = button.dataset.filter;
  refresh(false);
  search.focus();
});

search.addEventListener("input", () => refresh(false));

document.addEventListener("keydown", (e) => {
  if (ClipCards.menuOpen()) return;
  const item = items[selected];
  if (e.key === "Escape") { e.preventDefault(); close(); }
  else if (e.key === "Enter") { e.preventDefault(); paste(selected); }
  else if (e.key === "ArrowRight") { e.preventDefault(); select(selected + 1); }
  else if (e.key === "ArrowLeft") { e.preventDefault(); select(selected - 1); }
  else if (e.ctrlKey && /^[1-9]$/.test(e.key)) { e.preventDefault(); paste(Number(e.key) - 1); }
  else if (e.ctrlKey && e.key.toLowerCase() === "p" && item) { e.preventDefault(); invoke("clip_pin", { id: item.id }); }
  // Delete removes the selected item, unless you're editing the search text.
  else if (e.key === "Delete" && item && (document.activeElement !== search || search.value === "")) {
    e.preventDefault();
    invoke("clip_delete", { id: item.id });
  }
});

listen("clipboard-changed", () => refresh(true));
listen("clipboard-panel-open", () => {
  ClipCards.closeMenu();
  search.value = "";
  refresh(false).then(() => search.focus());
});
refresh(false).then(() => search.focus());
