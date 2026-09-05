import fs from "node:fs";

for (const file of process.argv.slice(2)) {
  const text = fs.readFileSync(file, "utf8");
  const stack = [];
  const pairs = { "}": "{", ")": "(", "]": "[" };
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;

  for (let i = 0; i < text.length; i++) {
    const c = text[i], n = text[i + 1];
    if (lineComment) { if (c === "\n") lineComment = false; continue; }
    if (blockComment) { if (c === "*" && n === "/") { blockComment = false; i++; } continue; }
    if (quote) {
      if (escaped) { escaped = false; continue; }
      if (c === "\\") { escaped = true; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === "/" && n === "/") { lineComment = true; i++; continue; }
    if (c === "/" && n === "*") { blockComment = true; i++; continue; }
    if (c === '"' || c === "'") { quote = c; continue; }
    if ("{([".includes(c)) stack.push(c);
    if ("})]".includes(c)) {
      const got = stack.pop();
      if (got !== pairs[c]) throw new Error(`${file}: unbalanced ${c} at byte ${i}`);
    }
  }
  if (quote || blockComment || stack.length) throw new Error(`${file}: unterminated token or unbalanced delimiters`);
}
console.log("qml delimiter checks: ok");
