// Clipboard history cards, shared by the Clipboard page and the Clipboard History panel.
"use strict";

const ClipCards = (() => {
  const LABELS = { text: "Text", link: "Link", image: "Image", file: "File" };
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

  /** A card for one history item. `index` (1–9) shows the Ctrl+number shortcut. */
  function render(item, { index, convertFileSrc } = {}) {
    const card = node("article", `clip kind-${item.kind}`);
    card.dataset.id = item.id;
    const header = node("header");
    header.append(node("span", "clip-kind", LABELS[item.kind] ?? item.kind));
    if (item.pinned) header.append(node("span", "clip-pin", "Pinned"));
    if (index) header.append(node("span", "clip-index", `Ctrl+${index}`));
    card.append(header);

    const body = node("div", "clip-body");
    if (item.kind === "image" && item.imagePath) {
      const img = node("img");
      img.src = convertFileSrc(item.imagePath);
      img.alt = "";
      img.draggable = false;
      img.loading = "lazy";
      body.append(img);
      body.classList.add("clip-picture");
    } else if (item.kind === "file") {
      const paths = item.filePaths ?? [];
      body.append(node("div", "clip-filename", fileName(paths[0] ?? "")));
      if (paths.length > 1) body.append(node("div", "clip-more", `and ${paths.length - 1} more`));
    } else if (item.kind === "link") {
      try {
        body.append(node("div", "clip-host", new URL(item.text).host));
      } catch { /* not a URL after all */ }
      body.append(node("div", "clip-text", item.text ?? ""));
    } else {
      body.append(node("div", "clip-text", (item.text ?? "").slice(0, 600)));
    }
    card.append(body);

    const footer = node("footer");
    footer.append(node("span", "clip-source", item.sourceAppName ?? ""), node("span", "clip-age", ago(item.date)));
    card.append(footer);

    const label = { text: "Text", link: "Link", image: "Image", file: "File" }[item.kind];
    const preview = item.kind === "image" ? "" : item.kind === "file" ? fileName((item.filePaths ?? [])[0] ?? "") : (item.text ?? "").slice(0, 80);
    card.setAttribute("aria-label", `${label}${preview ? `: ${preview}` : ""}${item.sourceAppName ? `, from ${item.sourceAppName}` : ""}`);
    return card;
  }

  return { render, ago };
})();
