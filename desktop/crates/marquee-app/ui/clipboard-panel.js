// The Clipboard History panel: type to search, arrows to choose, Enter to paste into the app
// you were using. Rust opens it (Ctrl+Alt+Shift+V by default) and closes it when it loses focus.
"use strict";

const { invoke, convertFileSrc } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const search = document.getElementById("search");
const row = document.getElementById("row");
const empty = document.getElementById("empty");
const filters = [...document.querySelectorAll("[data-filter]")];

let items = [];
let selected = 0;
let filter = "all";

async function refresh(keepSelection = true) {
  const id = items[selected]?.id;
  items = await invoke("clip_list", { filter, query: search.value });
  selected = keepSelection && id ? Math.max(0, items.findIndex((i) => i.id === id)) : 0;
  row.replaceChildren(...items.map((item, i) => {
    const card = ClipCards.render(item, { index: i < 9 ? i + 1 : null, convertFileSrc });
    card.setAttribute("role", "option");
    card.addEventListener("click", () => select(i));
    card.addEventListener("dblclick", () => paste(i));
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

function close() {
  invoke("clip_close_panel");
}

for (const button of filters) {
  button.addEventListener("click", () => {
    filter = button.dataset.filter;
    for (const b of filters) b.setAttribute("aria-checked", String(b === button));
    refresh(false);
    search.focus();
  });
}

search.addEventListener("input", () => refresh(false));

document.addEventListener("keydown", (e) => {
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
  search.value = "";
  refresh(false).then(() => search.focus());
});
refresh(false).then(() => search.focus());
