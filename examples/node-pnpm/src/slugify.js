// Turns a post title into the last part of its URL: "Über Äpfel & Birnen!" → "ueber-aepfel-birnen".
const UMLAUTS = { ä: "ae", ö: "oe", ü: "ue", ß: "ss" };
export const MAX_LENGTH = 60;

export function slugify(title) {
  if (typeof title !== "string") throw new TypeError("slugify: title must be a string");
  const slug = title
    .toLowerCase()
    .replace(/[äöüß]/g, (c) => UMLAUTS[c])
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "") // accents: é → e
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (slug === "") throw new RangeError("slugify: the title has no letters or digits");
  // cut at a word boundary, never in the middle of a word
  if (slug.length <= MAX_LENGTH) return slug;
  const cut = slug.slice(0, MAX_LENGTH + 1);
  const end = cut.lastIndexOf("-");
  return end > 0 ? cut.slice(0, end) : slug.slice(0, MAX_LENGTH);
}
