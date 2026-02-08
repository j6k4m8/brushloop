#!/usr/bin/env node
const target = process.argv[2] ?? "package";
console.log(`Format noop for ${target}; custom lint enforces baseline style.`);
