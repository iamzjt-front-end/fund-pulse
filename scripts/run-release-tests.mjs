#!/usr/bin/env node

import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { parseCoverageReport } from "./lib/coverage-report.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const unitTests = [
  "scripts/tests/coverage-report.test.mjs",
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
const coverageResults = parseCoverageReport(stdout);

for (const [file, required] of thresholds) {
  const actual = coverageResults.get(file);
  if (!actual) {
    process.stderr.write(`Coverage result missing for ${file}.\n${stderr}`);
    process.exit(1);
  }
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
