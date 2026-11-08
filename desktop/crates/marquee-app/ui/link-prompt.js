// The Open Link prompt after Copy Text (link_prompt.rs). Rust stores the links; this page
// shows them, sizes the window to fit, and opens one by index. Enter opens the first, Esc
// closes, and it closes by itself after 15 seconds unless the pointer is on it.
"use strict";

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const LIFETIME = 15000;
const card = document.getElementById("card");
const list = document.getElementById("links");
let timer = 0;
let hovering = false;
let closing = false;

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

function glyph(email) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  svg.innerHTML = email
    ? '<rect x="3.5" y="5.5" width="17" height="13" rx="2"/><path d="m4 7 8 6 8-6"/>'
    : '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.6 2.5 14.4 0 17M12 3.5c-2.5 2.6-2.5 14.4 0 17"/>';
  return svg;
}

/** Plays the exit, then hides the window (or opens a link first). */
function leave(then) {
  if (closing) return;
  closing = true;
  clearTimeout(timer);
  card.classList.add("leaving");
  setTimeout(() => then().catch((e) => console.error(e)), 150);
}

const close = () => leave(() => invoke("link_prompt_close"));
const open = (index) => leave(() => invoke("link_prompt_open", { index }));

function arm() {
  clearTimeout(timer);
  timer = setTimeout(() => (hovering ? arm() : close()), LIFETIME);
}

async function show() {
  const info = await invoke("link_prompt_info");
  if (!info) return;
  closing = false;
  hovering = false;
  card.classList.remove("leaving");
  const single = info.links.length === 1;
  document.getElementById("title").textContent = single ? (info.links[0].email ? "Write to this address?" : "Open this link?") : "Open a link?";
  document.getElementById("summary").textContent = info.summary;
  // SVG elements have no `hidden` property, only the attribute.
  document.getElementById("icon-qr").toggleAttribute("hidden", !info.fromCode);
  document.getElementById("icon-link").toggleAttribute("hidden", info.fromCode);

  if (single) {
    const link = info.links[0];
    list.replaceChildren(
      el("div", { class: "address", title: link.text }, link.text),
      el("div", { class: "actions" },
        el("button", { class: "button", onclick: close }, "Close"),
        el("button", { class: "button primary", id: "primary", onclick: () => open(0) }, link.email ? "New Email" : "Open Link")));
  } else {
    list.replaceChildren(
      ...info.links.map((link, i) => el("div", { class: "row" },
        glyph(link.email),
        el("span", { class: "text", title: link.text }, link.text),
        el("button", { class: i === 0 ? "button primary" : "button", id: i === 0 ? "primary" : null, "aria-label": `Open ${link.text}`, onclick: () => open(i) }, "Open"))),
      el("div", { class: "actions" }, el("button", { class: "button", onclick: close }, "Close")));
  }
  // Restart the entrance animation for this showing.
  card.hidden = true;
  void card.offsetWidth;
  card.hidden = false;
  await new Promise(requestAnimationFrame);
  await invoke("link_prompt_layout", { height: Math.ceil(document.body.getBoundingClientRect().height) });
  document.getElementById("primary")?.focus();
  arm();
}

document.getElementById("close").addEventListener("click", close);
card.addEventListener("mouseenter", () => (hovering = true));
card.addEventListener("mouseleave", () => (hovering = false));
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") { e.preventDefault(); close(); }
  else if (e.key === "Enter" && document.activeElement?.tagName !== "BUTTON") { e.preventDefault(); open(0); }
});

listen("link-prompt-show", () => show().catch((e) => console.error(e)));
