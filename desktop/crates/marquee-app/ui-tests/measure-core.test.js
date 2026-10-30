// Unit tests for ui/measure-core.js: node --test crates/marquee-app/ui-tests/measure-core.test.js (outside ui/, so it isn't bundled)
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const M = require("../ui/measure-core.js");

/** A white image with gray rectangles drawn on it. */
function image(width, height, boxes = [], noise = 0) {
  const data = new Uint8ClampedArray(width * height * 4).fill(255);
  for (const { x, y, w, h, v = 60 } of boxes) {
    for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) {
      const i = (yy * width + xx) * 4;
      data[i] = data[i + 1] = data[i + 2] = v;
    }
  }
  if (noise) for (let i = 0; i < data.length; i += 4) data[i] = Math.max(0, data[i] - (i % 7 === 0 ? noise : 0));
  return { data, width, height };
}

test("distances reach the edges of the region", () => {
  const px = image(100, 80, [{ x: 20, y: 10, w: 50, h: 30 }]);
  assert.deepEqual(M.distances(px, 30, 20), { left: 10, right: 39, up: 10, down: 19 });
  // Outside the box: the background runs to the box or the screen edge.
  assert.deepEqual(M.distances(px, 5, 20), { left: 5, right: 14, up: 20, down: 59 });
  // Out-of-range points are clamped.
  assert.equal(M.distances(px, -5, 500).left, 0);
});

test("small noise doesn't stop the walk", () => {
  const px = image(60, 20, [], 8);
  assert.equal(M.distances(px, 30, 10).left, 30);
  assert.equal(M.distances(px, 30, 10).right, 29);
});

test("snap shrinks a drag to the element inside", () => {
  const px = image(200, 100, [{ x: 50, y: 30, w: 40, h: 20 }]);
  assert.deepEqual(M.snap(px, { x: 30, y: 10, width: 100, height: 70 }), { x: 50, y: 30, width: 40, height: 20 });
  // Nothing inside: the rectangle stays, clamped to the image.
  assert.deepEqual(M.snap(px, { x: 150, y: 60, width: 80, height: 80 }), { x: 150, y: 60, width: 50, height: 40 });
});

test("guides snap to a nearby edge", () => {
  const px = image(100, 50, [{ x: 40, y: 10, w: 20, h: 20 }]);
  assert.equal(M.snapGuide(px, "vertical", 37, 15, 4), 40);
  assert.equal(M.snapGuide(px, "vertical", 62, 15, 4), 60);
  assert.equal(M.snapGuide(px, "vertical", 80, 15, 4), 80); // nothing near
  assert.equal(M.snapGuide(px, "horizontal", 12, 50, 4), 10);
});

test("gaps between guides", () => {
  assert.deepEqual(M.gaps([30, 10, 10, 70]), [{ start: 10, end: 30 }, { start: 30, end: 70 }]);
  assert.deepEqual(M.gaps([5]), []);
});
