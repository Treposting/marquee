// Counts down from ?s=N once a second. Marquee closes this window when the time is up.
"use strict";
const count = document.getElementById("count");
let left = Number(new URLSearchParams(location.search).get("s")) || 5;
count.textContent = left;
const timer = setInterval(() => {
  left -= 1;
  if (left <= 0) return clearInterval(timer);
  count.textContent = left;
}, 1000);
