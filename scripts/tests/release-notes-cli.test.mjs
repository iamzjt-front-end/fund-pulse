import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const cliPath = path.join(repositoryRoot, "scripts/release-notes.mjs");
const validFragment = (type, body) => `---\ntype: ${type}\n---\n\n${body}\n`;

async function withTempDirectory(run) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "fund-pulse-release-notes-cli-test-"));
  try {
    return await run(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function generateArguments(directory, extra = []) {
  return [
    cliPath,
    "generate",
    "--fragments-dir", path.join(directory, ".release-notes"),
    "--version", "1.0.42",
    "--tag", "v1.0.42",
    "--previous-tag", "v1.0.41",
    "--repository", "iamzjt-front-end/fund-pulse",
    "--zip-name", "app.zip",
    "--zip-sha", "zip-sha",
    "--dmg-name", "app.dmg",
    "--dmg-sha", "dmg-sha",
    "--feed-name", "latest-mac.yml",
    "--feed-sha", "feed-sha",
    "--date", "2026-07-10",
    "--notes-output", path.join(directory, "notes.md"),
    "--entry-output", path.join(directory, "entry.md"),
    "--manifest-output", path.join(directory, "manifest.json"),
    ...extra,
  ];
}

test("CLI generates notes, changelog entry, and a hash manifest", async () => {
  await withTempDirectory(async (directory) => {
    const fragmentsDirectory = path.join(directory, ".release-notes");
    await mkdir(fragmentsDirectory);
    await writeFile(path.join(fragmentsDirectory, "release-workflow.md"), validFragment("optimization", "发布说明改为结构化生成。"));

    const result = await execFileAsync(process.execPath, generateArguments(directory));

    assert.match(result.stdout, /generated 1 release-note fragment/i);
    assert.match(await readFile(path.join(directory, "notes.md"), "utf8"), /发布说明改为结构化生成。/);
    assert.match(await readFile(path.join(directory, "entry.md"), "utf8"), /v1\.0\.42/);
    const manifest = JSON.parse(await readFile(path.join(directory, "manifest.json"), "utf8"));
    assert.equal(manifest.schemaVersion, 1);
    assert.equal(manifest.version, "1.0.42");
    assert.match(manifest.entrySha256, /^[a-f0-9]{64}$/);
    assert.equal(manifest.fragments.length, 1);
    assert.equal(manifest.fragments[0].fileName, "release-workflow.md");
  });
});

test("CLI apply updates the changelog and consumes the generated manifest", async () => {
  await withTempDirectory(async (directory) => {
    const fragmentsDirectory = path.join(directory, ".release-notes");
    const changelogPath = path.join(directory, "CHANGELOG.md");
    await mkdir(fragmentsDirectory);
    await writeFile(path.join(fragmentsDirectory, "README.md"), "guide");
    await writeFile(path.join(fragmentsDirectory, "release-workflow.md"), validFragment("optimization", "发布说明改为结构化生成。"));
    await writeFile(changelogPath, "# Changelog\n\n## v1.0.41 - 2026-07-08\n\n- 旧版本。\n");
    await execFileAsync(process.execPath, generateArguments(directory));

    await execFileAsync(process.execPath, [
      cliPath,
      "apply",
      "--fragments-dir", fragmentsDirectory,
      "--changelog", changelogPath,
      "--entry-file", path.join(directory, "entry.md"),
      "--manifest-file", path.join(directory, "manifest.json"),
      "--version", "1.0.42",
    ]);

    assert.match(await readFile(changelogPath, "utf8"), /v1\.0\.42/);
    await assert.rejects(() => readFile(path.join(fragmentsDirectory, "release-workflow.md"), "utf8"), /ENOENT/);
    assert.equal(await readFile(path.join(fragmentsDirectory, "README.md"), "utf8"), "guide");
  });
});

test("CLI rejects missing fragments unless allow-empty is explicit", async () => {
  await withTempDirectory(async (directory) => {
    await mkdir(path.join(directory, ".release-notes"));
    await assert.rejects(
      () => execFileAsync(process.execPath, generateArguments(directory)),
      (error) => error.code !== 0 && /no release-note fragments/i.test(error.stderr),
    );

    await execFileAsync(process.execPath, generateArguments(directory, ["--allow-empty"]));
    assert.match(await readFile(path.join(directory, "notes.md"), "utf8"), /仅重新打包/);
  });
});

test("CLI manual notes override the GitHub body but fragments still drive the changelog", async () => {
  await withTempDirectory(async (directory) => {
    const fragmentsDirectory = path.join(directory, ".release-notes");
    const manualPath = path.join(directory, "manual.md");
    await mkdir(fragmentsDirectory);
    await writeFile(path.join(fragmentsDirectory, "fix.md"), validFragment("fix", "修复自动生成说明缺少内容的问题。"));
    await writeFile(manualPath, "## 更新内容\n\n- 面向用户的自定义说明。\n");

    await execFileAsync(process.execPath, generateArguments(directory, ["--notes-file", manualPath]));

    assert.equal(await readFile(path.join(directory, "notes.md"), "utf8"), "## 更新内容\n\n- 面向用户的自定义说明。\n");
    assert.match(await readFile(path.join(directory, "entry.md"), "utf8"), /修复自动生成说明缺少内容的问题。/);
  });
});

test("CLI does not let allow-empty hide a malformed fragment", async () => {
  await withTempDirectory(async (directory) => {
    const fragmentsDirectory = path.join(directory, ".release-notes");
    await mkdir(fragmentsDirectory);
    await writeFile(path.join(fragmentsDirectory, "broken.md"), "---\ntype: unknown\n---\nBroken\n");

    await assert.rejects(
      () => execFileAsync(process.execPath, generateArguments(directory, ["--allow-empty"])),
      (error) => error.code !== 0 && /unsupported.*type/i.test(error.stderr),
    );
  });
});

test("CLI rejects unknown options and missing option values", async () => {
  await assert.rejects(
    () => execFileAsync(process.execPath, [cliPath, "generate", "--unknown"]),
    (error) => error.code !== 0 && /unknown option/i.test(error.stderr),
  );
  await assert.rejects(
    () => execFileAsync(process.execPath, [cliPath, "generate", "--version"]),
    (error) => error.code !== 0 && /missing value.*--version/i.test(error.stderr),
  );
});

test("CLI prints help and rejects unknown commands, positional arguments, and missing required options", async () => {
  const help = await execFileAsync(process.execPath, [cliPath, "--help"]);
  assert.match(help.stdout, /Usage:/);
  assert.match(help.stdout, /--allow-empty/);

  await assert.rejects(
    () => execFileAsync(process.execPath, [cliPath, "unknown"]),
    (error) => error.code !== 0 && /unknown command/i.test(error.stderr),
  );
  await assert.rejects(
    () => execFileAsync(process.execPath, [cliPath, "generate", "positional"]),
    (error) => error.code !== 0 && /unexpected argument/i.test(error.stderr),
  );
  await assert.rejects(
    () => execFileAsync(process.execPath, [cliPath, "generate"]),
    (error) => error.code !== 0 && /missing required option/i.test(error.stderr),
  );
});

test("CLI apply rejects malformed, unsupported, and invalid fragment manifests", async () => {
  await withTempDirectory(async (directory) => {
    const fragmentsDirectory = path.join(directory, ".release-notes");
    const changelogPath = path.join(directory, "CHANGELOG.md");
    const entryPath = path.join(directory, "entry.md");
    const manifestPath = path.join(directory, "manifest.json");
    await mkdir(fragmentsDirectory);
    await writeFile(changelogPath, "# Changelog\n");
    await writeFile(entryPath, "## v1.0.42 - 2026-07-10\n\n- 新版本。\n");
    const args = [
      cliPath,
      "apply",
      "--fragments-dir", fragmentsDirectory,
      "--changelog", changelogPath,
      "--entry-file", entryPath,
      "--manifest-file", manifestPath,
      "--version", "1.0.42",
    ];

    await writeFile(manifestPath, "not json");
    await assert.rejects(
      () => execFileAsync(process.execPath, args),
      (error) => error.code !== 0 && /not valid JSON/i.test(error.stderr),
    );

    await writeFile(manifestPath, "{}\n");
    await assert.rejects(
      () => execFileAsync(process.execPath, args),
      (error) => error.code !== 0 && /unsupported release-note manifest schema/i.test(error.stderr),
    );

    await writeFile(manifestPath, `${JSON.stringify({
      schemaVersion: 1,
      version: "1.0.42",
      entrySha256: "invalid",
      fragments: {},
    })}\n`);
    await assert.rejects(
      () => execFileAsync(process.execPath, args),
      (error) => error.code !== 0 && /changelog entry changed/i.test(error.stderr),
    );
  });
});

test("CLI apply binds the manifest to the release version and changelog entry", async () => {
  await withTempDirectory(async (directory) => {
    const fragmentsDirectory = path.join(directory, ".release-notes");
    const changelogPath = path.join(directory, "CHANGELOG.md");
    await mkdir(fragmentsDirectory);
    await writeFile(path.join(fragmentsDirectory, "fix.md"), validFragment("fix", "修复发布说明绑定问题。"));
    await writeFile(changelogPath, "# Changelog\n\n## v1.0.41 - 2026-07-08\n\n- 旧版本。\n");
    await execFileAsync(process.execPath, generateArguments(directory));
    const baseArgs = [
      cliPath,
      "apply",
      "--fragments-dir", fragmentsDirectory,
      "--changelog", changelogPath,
      "--entry-file", path.join(directory, "entry.md"),
      "--manifest-file", path.join(directory, "manifest.json"),
    ];

    await assert.rejects(
      () => execFileAsync(process.execPath, [...baseArgs, "--version", "1.0.43"]),
      (error) => error.code !== 0 && /version mismatch/i.test(error.stderr),
    );

    await writeFile(path.join(directory, "entry.md"), "## v9.9.9 - 2026-07-10\n\n- 被篡改。\n");
    await assert.rejects(
      () => execFileAsync(process.execPath, [...baseArgs, "--version", "1.0.42"]),
      (error) => error.code !== 0 && /entry changed after generation/i.test(error.stderr),
    );
    assert.doesNotMatch(await readFile(changelogPath, "utf8"), /v9\.9\.9/);
  });
});
