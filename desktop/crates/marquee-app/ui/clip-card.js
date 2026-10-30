// Clipboard history cards, shared by the Clipboard page and the Clipboard History panel.
"use strict";

const ClipCards = (() => {
  const LABELS = { text: "Text", link: "Link", image: "Image", file: "File" };
  /** Category colors, the same palette as the Mac app. */
  const TINTS = {
    red: "#FF3B30", orange: "#FF9500", yellow: "#FFCC00", green: "#34C759", mint: "#00C7BE", teal: "#30B0C7",
    blue: "#007AFF", indigo: "#5856D6", purple: "#AF52DE", pink: "#FF2D55", brown: "#A2845E", gray: "#8E8E93",
  };
  const COLOR = /^\s*(#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})|(?:rgba?|hsla?)\([^()]{4,60}\))\s*;?\s*$/i;

  /** The CSS color a text item is, like "#FFCF1A" or "rgb(0 120 255)", or null. */
  function colorOf(text) {
    const match = COLOR.exec(text ?? "");
    return match && CSS.supports("color", match[1]) ? match[1] : null;
  }
  const relative = new Intl.RelativeTimeFormat(undefined, { numeric: "auto", style: "short" });

  /** "2 min. ago", "yesterday", or the date. */
  function ago(iso) {
    const date = new Date(iso);
    let value = (date - Date.now()) / 1000;
    for (const [unit, size] of [["second", 60], ["minute", 60], ["hour", 24], ["day", 7]]) {
      if (Math.abs(value) < size) return Math.abs(value) < 10 && unit === "second" ? "just now" : relative.format(Math.round(value), unit);
      value /= size;
    }
    return date.toLocaleDateString();
  }

  function node(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  function fileName(path) {
    return path.split(/[\\/]/).pop() || path;
  }

  function picture(src, convertFileSrc) {
    const img = node("img");
    img.src = convertFileSrc(src);
    img.alt = "";
    img.draggable = false;
    img.loading = "lazy";
    return img;
  }

  function host(text) {
    try { return new URL(text).host.replace(/^www\./, ""); } catch { return null; }
  }

  /** A card for one history item. `index` (1–9) shows the Ctrl+number shortcut. */
  function render(item, { index, convertFileSrc, categories = [] } = {}) {
    const card = node("article", `clip kind-${item.kind}`);
    card.dataset.id = item.id;
    const header = node("header");
    header.append(node("span", "clip-kind", LABELS[item.kind] ?? item.kind));
    const category = categories.find((c) => c.id === item.categoryId);
    if (category) {
      const tag = node("span", "clip-category", category.name);
      tag.style.setProperty("--tint", TINTS[category.tint] ?? TINTS.gray);
      header.append(tag);
    }
    if (item.pinned) header.append(node("span", "clip-pin", "Pinned"));
    if (index) header.append(node("span", "clip-index", `Ctrl+${index}`));
    card.append(header);

    const body = node("div", "clip-body");
    if (item.kind === "image" && item.imagePath) {
      body.append(picture(item.imagePath, convertFileSrc));
      body.classList.add("clip-picture");
    } else if (item.kind === "file") {
      const paths = item.filePaths ?? [];
      const names = node("div", "clip-names");
      names.append(node("div", "clip-filename", fileName(paths[0] ?? "")));
      if (paths.length > 1) names.append(node("div", "clip-more", `and ${paths.length - 1} more`));
      if (item.previewPath) {
        body.classList.add("clip-picture", "clip-captioned");
        body.append(picture(item.previewPath, convertFileSrc));
      }
      body.append(names);
    } else if (item.kind === "link") {
      if (item.previewPath) {
        const art = node("div", "clip-link-image");
        art.append(picture(item.previewPath, convertFileSrc));
        body.append(art);
        body.classList.add("clip-rich-link");
      }
      if (item.linkTitle) body.append(node("div", "clip-link-title", item.linkTitle));
      const site = host(item.text);
      if (site) body.append(node("div", "clip-host", site));
      if (!item.previewPath) body.append(node("div", "clip-text", item.text ?? ""));
    } else {
      const color = colorOf(item.text);
      if (color) {
        const swatch = node("div", "clip-swatch");
        swatch.style.setProperty("--swatch", color);
        body.append(swatch);
        body.classList.add("clip-color");
      }
      body.append(node("div", "clip-text", (item.text ?? "").slice(0, 600)));
    }
    card.append(body);

    const footer = node("footer");
    footer.append(node("span", "clip-source", item.sourceAppName ?? ""), node("span", "clip-age", ago(item.date)));
    card.append(footer);

    const label = LABELS[item.kind];
    const preview = item.kind === "image" ? "" : item.kind === "file" ? fileName((item.filePaths ?? [])[0] ?? "") : (item.linkTitle ?? item.text ?? "").slice(0, 80);
    card.setAttribute("aria-label", `${label}${preview ? `: ${preview}` : ""}${item.sourceAppName ? `, from ${item.sourceAppName}` : ""}`);
    return card;
  }

  // Right-click menu

  let openMenu = null;

  function closeMenu() {
    openMenu?.remove();
    openMenu = null;
  }

  /**
   * Shows the menu for an item at the pointer. `actions` are the commands this window offers
   * ({ label, run, danger, keys }); categories follow, with a "New category" field, then
   * `tail` actions. `invoke` calls Rust.
   */
  function menu(event, item, { actions = [], tail = [], categories = [], invoke }) {
    event.preventDefault();
    closeMenu();
    const box = node("div", "clip-menu");
    box.setAttribute("role", "menu");
    const run = (fn) => () => { closeMenu(); Promise.resolve(fn()).catch((e) => console.error(e)); };
    const add = ({ label, run: fn, danger, keys }) => {
      const b = node("button", danger ? "danger" : "");
      b.setAttribute("role", "menuitem");
      b.append(node("span", "label", label));
      if (keys) b.append(node("span", "keys", keys));
      b.addEventListener("click", run(fn));
      box.append(b);
    };
    actions.forEach(add);

    box.append(node("hr"), node("div", "heading", "Category"));
    const chips = node("div", "category-chips");
    chips.setAttribute("role", "radiogroup");
    chips.setAttribute("aria-label", "Category");
    for (const c of [{ id: null, name: "None" }, ...categories]) {
      const chip = node("button", "", c.name);
      chip.setAttribute("role", "radio");
      chip.setAttribute("aria-checked", String((item.categoryId ?? null) === c.id));
      if (c.tint) chip.style.setProperty("--tint", TINTS[c.tint] ?? TINTS.gray);
      chip.addEventListener("click", run(() => invoke("clip_set_category", { id: item.id, category: c.id })));
      chips.append(chip);
    }
    box.append(chips);
    const form = node("form", "new-category");
    const input = node("input");
    input.placeholder = "New category";
    input.setAttribute("aria-label", "New category name");
    input.spellcheck = false;
    form.append(input);
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const name = input.value.trim();
      if (!name) return;
      const tints = Object.keys(TINTS);
      const tint = tints[categories.length % tints.length];
      run(() => invoke("clip_category_add", { name, tint, item: item.id }))();
    });
    box.append(form);

    if (tail.length) box.append(node("hr"));
    tail.forEach(add);

    document.body.append(box);
    const { innerWidth: W, innerHeight: H } = window;
    const r = box.getBoundingClientRect();
    box.style.left = `${Math.max(4, Math.min(event.clientX, W - r.width - 4))}px`;
    box.style.top = `${Math.max(4, Math.min(event.clientY, H - r.height - 4))}px`;
    openMenu = box;
    box.querySelector("button")?.focus();
    box.addEventListener("keydown", (e) => {
      const buttons = [...box.querySelectorAll("button, input")];
      const i = buttons.indexOf(document.activeElement);
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); closeMenu(); }
      else if (e.key === "ArrowDown") { e.preventDefault(); e.stopPropagation(); buttons[(i + 1) % buttons.length].focus(); }
      else if (e.key === "ArrowUp") { e.preventDefault(); e.stopPropagation(); buttons[(i - 1 + buttons.length) % buttons.length].focus(); }
      else e.stopPropagation();
    });
  }

  document.addEventListener("pointerdown", (e) => { if (openMenu && !openMenu.contains(e.target)) closeMenu(); }, true);
  window.addEventListener("blur", closeMenu);

  /** Whether a menu is open (so the window's own keys can stand aside). */
  const menuOpen = () => openMenu != null;

  return { render, ago, menu, closeMenu, menuOpen, TINTS };
})();
