import { test } from "node:test";
import assert from "node:assert/strict";
import { slugify, MAX_LENGTH } from "../src/slugify.js";

test("lower case, words joined with a dash", () => {
  assert.equal(slugify("Hello World"), "hello-world");
});

test("German umlauts are spelled out, accents dropped", () => {
  assert.equal(slugify("Über Äpfel & Birnen!"), "ueber-aepfel-birnen");
  assert.equal(slugify("Café Crème"), "cafe-creme");
});

test("long titles are cut at a word boundary", () => {
  const slug = slugify("word ".repeat(30));
  assert.ok(slug.length <= MAX_LENGTH);
  assert.ok(!slug.endsWith("-"));
  assert.equal(slug, Array(12).fill("word").join("-")); // 12 words = 59 characters
});

test("a title without letters or digits is refused", () => {
  assert.throws(() => slugify("!!! ???"), RangeError);
  assert.throws(() => slugify(""), RangeError);
});

test("anything but a string is refused", () => {
  assert.throws(() => slugify(undefined), TypeError);
  assert.throws(() => slugify(42), TypeError);
});
