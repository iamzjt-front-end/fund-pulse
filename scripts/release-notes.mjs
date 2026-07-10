#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import {
  applyReleaseMetadata,
  buildChangelogEntry,
  buildReleaseNotes,
  loadReleaseNoteFragments,
} from "./lib/release-notes.mjs";

const VALUE_OPTIONS = new Set([
  "fragments-dir",
  "version",
  "tag",
  "previous-tag",
  "repository",
  "zip-name",
  "zip-sha",
  "dmg-name",
  "dmg-sha",
  "feed-name",
  "feed-sha",
  "date",
  "notes-output",
  "entry-output",
  "manifest-output",
  "notes-file",
  "changelog",
  "entry-file",
  "manifest-file",
]);
const BOOLEAN_OPTIONS = new Set(["allow-empty", "help"]);

function usage() {
  return `Usage:
  node scripts/release-notes.mjs generate [options]
  node scripts/release-notes.mjs apply [options]

Generate options:
  --fragments-dir DIR
  --version VERSION
  --tag TAG
  --previous-tag TAG
  --repository OWNER/REPO
  --zip-name NAME --zip-sha SHA256
  --dmg-name NAME --dmg-sha SHA256
  --feed-name NAME --feed-sha SHA256
  --date YYYY-MM-DD
  --notes-output FILE
  --entry-output FILE
  --manifest-output FILE
  --notes-file FILE
  --allow-empty

Apply options:
  --fragments-dir DIR
  --changelog FILE
  --entry-file FILE
  --manifest-file FILE
  --version VERSION
`;
}

function parseArguments(argv) {
  const [command, ...rest] = argv;
  if (!command || command === "--help" || command === "-h") return { command: "help", options: {} };
  if (!new Set(["generate", "apply"]).has(command)) {
    throw new Error(`Unknown command: ${command}`);
  }

  const options = {};
  for (let index = 0; index < rest.length; index += 1) {
    const argument = rest[index];
    if (!argument.startsWith("--")) throw new Error(`Unexpected argument: ${argument}`);
    const name = argument.slice(2);
    if (BOOLEAN_OPTIONS.has(name)) {
      options[name] = true;
      continue;
    }
    if (!VALUE_OPTIONS.has(name)) throw new Error(`Unknown option: --${name}`);
    const value = rest[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`Missing value for --${name}`);
    }
    options[name] = value;
    index += 1;
  }
  return { command, options };
}

function requireOptions(options, names) {
  for (const name of names) {
    if (!options[name]) throw new Error(`Missing required option: --${name}`);
  }
}

async function writeOutput(filePath, content) {
  const { mkdir, rename, rm, writeFile } = await import("node:fs/promises");
  const { randomUUID } = await import("node:crypto");
  await mkdir(path.dirname(filePath), { recursive: true });
  const temporaryPath = `${filePath}.${process.pid}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporaryPath, content);
    await rename(temporaryPath, filePath);
  } catch (error) {
    await rm(temporaryPath, { force: true });
    throw error;
  }
}

async function generate(options) {
  requireOptions(options, [
    "fragments-dir",
    "version",
    "tag",
    "repository",
    "zip-name",
    "zip-sha",
    "dmg-name",
    "dmg-sha",
    "feed-name",
    "feed-sha",
    "date",
    "notes-output",
    "entry-output",
    "manifest-output",
  ]);

  const loaded = await loadReleaseNoteFragments(options["fragments-dir"]);
  const manualNotes = options["notes-file"]
    ? await readFile(options["notes-file"], "utf8")
    : undefined;
  const context = {
    fragments: loaded.fragments,
    manualNotes,
    allowEmpty: options["allow-empty"] === true,
    version: options.version,
    tag: options.tag,
    previousTag: options["previous-tag"],
    repository: options.repository,
    assets: {
      zip: { name: options["zip-name"], sha256: options["zip-sha"] },
      dmg: { name: options["dmg-name"], sha256: options["dmg-sha"] },
      feed: { name: options["feed-name"], sha256: options["feed-sha"] },
    },
  };
  const notes = buildReleaseNotes(context);
  const entry = buildChangelogEntry({
    version: options.version,
    date: options.date,
    fragments: loaded.fragments,
    manualNotes,
    allowEmpty: options["allow-empty"] === true,
  });
  const releaseManifest = {
    schemaVersion: 1,
    version: options.version,
    entrySha256: createHash("sha256").update(entry).digest("hex"),
    fragments: loaded.manifest,
  };

  await Promise.all([
    writeOutput(options["notes-output"], notes),
    writeOutput(options["entry-output"], entry),
    writeOutput(options["manifest-output"], `${JSON.stringify(releaseManifest, null, 2)}\n`),
  ]);
  process.stdout.write(`Generated ${loaded.fragments.length} release-note fragment${loaded.fragments.length === 1 ? "" : "s"}.\n`);
}

async function apply(options) {
  requireOptions(options, ["fragments-dir", "changelog", "entry-file", "manifest-file", "version"]);
  const [entry, manifestContent] = await Promise.all([
    readFile(options["entry-file"], "utf8"),
    readFile(options["manifest-file"], "utf8"),
  ]);
  let manifest;
  try {
    manifest = JSON.parse(manifestContent);
  } catch {
    throw new Error(`Manifest is not valid JSON: ${options["manifest-file"]}`);
  }
  if (manifest?.schemaVersion !== 1) throw new Error("Unsupported release-note manifest schema.");
  if (manifest.version !== options.version) {
    throw new Error(`Release-note manifest version mismatch: ${manifest.version} != ${options.version}`);
  }
  const entrySha256 = createHash("sha256").update(entry).digest("hex");
  if (manifest.entrySha256 !== entrySha256) {
    throw new Error("Changelog entry changed after generation; regenerate the release metadata.");
  }
  if (!Array.isArray(manifest.fragments)) throw new Error("Release-note manifest fragments must be an array.");
  await applyReleaseMetadata({
    changelogPath: options.changelog,
    fragmentsDirectory: options["fragments-dir"],
    entry,
    version: options.version,
    manifest: manifest.fragments,
  });
  process.stdout.write(`Applied release metadata for v${options.version}.\n`);
}

export async function main(argv = process.argv.slice(2)) {
  const { command, options } = parseArguments(argv);
  if (command === "help" || options.help) {
    process.stdout.write(usage());
    return;
  }
  if (command === "generate") await generate(options);
  else await apply(options);
}

const invokedPath = process.argv[1] ? pathToFileURL(path.resolve(process.argv[1])).href : "";
if (import.meta.url === invokedPath) {
  main().catch((error) => {
    process.stderr.write(`release-notes: ${error.message}\n`);
    process.exitCode = 1;
  });
}
