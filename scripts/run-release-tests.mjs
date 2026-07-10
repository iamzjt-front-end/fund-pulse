#!/usr/bin/env node

import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const unitTests = [
  "scripts/tests/release-notes.test.mjs",
  "scripts/tests/release-notes-cli.test.mjs",
];
const testFiles = process.argv.includes("--unit")
  ? unitTests
  : ["scripts/tests/release-flow.test.mjs", ...unitTests];

const child = spawn(
  process.execPath,
  ["--test", "--experimental-test-coverage", ...testFiles],
  { cwd: repositoryRoot, stdio: ["inherit", "pipe", "pipe"] },
);

let stdout = "";
let stderr = "";
child.stdout.on("data", (chunk) => {
  const text = chunk.toString();
  stdout += text;
  process.stdout.write(text);
});
child.stderr.on("data", (chunk) => {
  const text = chunk.toString();
  stderr += text;
  process.stderr.write(text);
});

const exitCode = await new Promise((resolve) => child.on("close", resolve));
if (exitCode !== 0) process.exit(exitCode ?? 1);

const thresholds = new Map([
  ["scripts/lib/release-notes.mjs", { lines: 97, branches: 92, functions: 90 }],
  ["scripts/release-notes.mjs", { lines: 97, branches: 80, functions: 95 }],
]);

for (const [file, required] of thresholds) {
  const escaped = file.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = stdout.match(new RegExp(`^#?\\s*${escaped}\\s*\\|\\s*([\\d.]+)\\s*\\|\\s*([\\d.]+)\\s*\\|\\s*([\\d.]+)`, "m"));
  if (!match) {
    process.stderr.write(`Coverage result missing for ${file}.\n${stderr}`);
    process.exit(1);
  }
  const actual = {
    lines: Number(match[1]),
    branches: Number(match[2]),
    functions: Number(match[3]),
  };
  for (const metric of ["lines", "branches", "functions"]) {
    if (actual[metric] < required[metric]) {
      process.stderr.write(
        `Coverage threshold failed for ${file}: ${metric} ${actual[metric]}% < ${required[metric]}%.\n`,
      );
      process.exit(1);
    }
  }
}

process.stdout.write("Release-note source coverage thresholds passed.\n");
