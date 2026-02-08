#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const targets = process.argv.slice(2);
if (targets.length === 0) {
  console.error("Usage: node scripts/lint.mjs <paths...>");
  process.exit(1);
}

const violations = [];
const exts = new Set([".ts", ".js", ".mjs", ".dart", ".md", ".json", ".yaml", ".yml"]);

function scanFile(filePath) {
  const text = fs.readFileSync(filePath, "utf8");
  const lines = text.split(/\r?\n/);

  lines.forEach((line, idx) => {
    if (line.includes("\t")) {
      violations.push(`${filePath}:${idx + 1} contains tab indentation`);
    }

    if (/\s+$/.test(line)) {
      violations.push(`${filePath}:${idx + 1} has trailing whitespace`);
    }
  });
}

function walk(targetPath) {
  const stat = fs.statSync(targetPath);
  if (stat.isDirectory()) {
    for (const entry of fs.readdirSync(targetPath)) {
      if (entry === "node_modules" || entry === ".git" || entry === "dist") {
        continue;
      }
      walk(path.join(targetPath, entry));
    }
    return;
  }

  if (!exts.has(path.extname(targetPath))) {
    return;
  }

  scanFile(targetPath);
}

for (const target of targets) {
  if (!fs.existsSync(target)) {
    continue;
  }
  walk(target);
}

if (violations.length > 0) {
  console.error("Lint violations found:");
  for (const violation of violations) {
    console.error(`- ${violation}`);
  }
  process.exit(1);
}

console.log("Lint passed.");
