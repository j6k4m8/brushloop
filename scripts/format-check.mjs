#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const targets = process.argv.slice(2);
if (targets.length === 0) {
  console.error('Usage: node scripts/format-check.mjs <paths...>');
  process.exit(1);
}

const exts = new Set(['.ts', '.js', '.mjs', '.json', '.md', '.yaml', '.yml']);
const violations = [];

function walk(target) {
  if (!fs.existsSync(target)) {
    return;
  }

  const stat = fs.statSync(target);
  if (stat.isDirectory()) {
    for (const entry of fs.readdirSync(target)) {
      if (entry === '.git' || entry === 'node_modules' || entry === 'dist') {
        continue;
      }
      walk(path.join(target, entry));
    }
    return;
  }

  const ext = path.extname(target);
  if (!exts.has(ext)) {
    return;
  }

  const text = fs.readFileSync(target, 'utf8');
  if (text.length > 0 && !text.endsWith('\n')) {
    violations.push(`${target} is missing a trailing newline`);
  }
}

for (const target of targets) {
  walk(target);
}

if (violations.length > 0) {
  console.error('Format check failed:');
  for (const violation of violations) {
    console.error(`- ${violation}`);
  }
  process.exit(1);
}

console.log('Format check passed.');
