import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import {
  appendFile,
  chmod,
  cp,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

async function run(command, args, options = {}) {
  return execFileAsync(command, args, { encoding: "utf8", ...options });
}

async function git(cwd, ...args) {
  return run("git", args, { cwd });
}

async function createReleaseFixture({ fragment = "valid" } = {}) {
  const root = await mkdtemp(path.join(os.tmpdir(), "fund-pulse-release-flow-test-"));
  const repository = path.join(root, "repo");
  const remote = path.join(root, "remote.git");
  const fakeBin = path.join(root, "bin");
  const temporary = path.join(root, "tmp");
  const ghLog = path.join(root, "gh.log");
  const commandLog = path.join(root, "commands.log");
  const ghState = path.join(root, "gh-state");
  await Promise.all([
    mkdir(path.join(repository, "scripts/lib"), { recursive: true }),
    mkdir(path.join(repository, ".release-notes"), { recursive: true }),
    mkdir(fakeBin),
    mkdir(temporary),
    mkdir(path.join(ghState, "assets"), { recursive: true }),
  ]);

  await Promise.all([
    cp(path.join(repositoryRoot, "scripts/release.sh"), path.join(repository, "scripts/release.sh")),
    cp(path.join(repositoryRoot, "scripts/release-notes.mjs"), path.join(repository, "scripts/release-notes.mjs")),
    cp(path.join(repositoryRoot, "scripts/lib/release-notes.mjs"), path.join(repository, "scripts/lib/release-notes.mjs")),
    writeFile(path.join(repository, "Package.swift"), "// release-flow fixture\n"),
    writeFile(path.join(repository, ".gitignore"), "dist\nrelease/swift\n"),
    writeFile(path.join(repository, "CHANGELOG.md"), "# Changelog\n\n## v1.0.41 - 2026-07-08\n\n- 旧版本。\n"),
    writeFile(path.join(repository, ".release-notes/README.md"), "release-note guide\n"),
    writeFile(path.join(repository, "package.json"), `${JSON.stringify({
      name: "fund-pulse",
      version: "1.0.41",
      scripts: {
        package: "true",
        "test:release:unit": "true",
      },
    }, null, 2)}\n`),
  ]);

  const ghStub = `#!/usr/bin/env node
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
const state = process.env.FAKE_GH_STATE;
fs.appendFileSync(process.env.GH_LOG, args.join(" ") + "\\n");
const file = (name) => path.join(state, name);
const read = (name, fallback = "") => fs.existsSync(file(name)) ? fs.readFileSync(file(name), "utf8") : fallback;
const write = (name, value) => fs.writeFileSync(file(name), String(value));
const option = (name) => { const index = args.indexOf(name); return index === -1 ? "" : args[index + 1]; };
const command = (args[0] || "") + " " + (args[1] || "");
if (command === "auth status") process.exit(0);
if (command === "release list") { process.stdout.write("v1.0.41\\n"); process.exit(0); }
if (args[0] === "api") { process.stdout.write(read("tag") + "\\n"); process.exit(0); }
if (command === "release create") {
  if (process.env.FAKE_GH_FAIL_CREATE === "1") process.exit(1);
  write("created", "1");
  write("draft", "true");
  write("tag", args[2]);
  write("name", option("--title"));
  fs.copyFileSync(option("--notes-file"), file("body"));
  process.exit(0);
}
if (command === "release upload") {
  const assets = JSON.parse(read("assets.json", "{}"));
  let uploaded = 0;
  for (let index = 3; index < args.length && !args[index].startsWith("--"); index += 1) {
    const source = args[index];
    const name = path.basename(source);
    const content = fs.readFileSync(source);
    assets[name] = crypto.createHash("sha256").update(content).digest("hex");
    fs.copyFileSync(source, path.join(state, "assets", name));
    uploaded += 1;
    if (process.env.FAKE_GH_FAIL_UPLOAD === "1" && uploaded === 1) {
      write("assets.json", JSON.stringify(assets));
      process.exit(1);
    }
  }
  write("assets.json", JSON.stringify(assets));
  process.exit(0);
}
if (command === "release edit") { write("draft", "false"); process.exit(0); }
if (command === "release download") {
  const name = option("--pattern");
  fs.mkdirSync(option("--dir"), { recursive: true });
  fs.copyFileSync(path.join(state, "assets", name), path.join(option("--dir"), name));
  process.exit(0);
}
if (command === "release view") {
  if (!fs.existsSync(file("created"))) process.exit(1);
  const field = option("--json");
  const jq = option("--jq");
  if (field === "body") process.stdout.write(read("body"));
  else if (field === "isDraft") process.stdout.write(read("draft") + "\\n");
  else if (field === "name") process.stdout.write(read("name") + "\\n");
  else if (field === "isPrerelease") process.stdout.write("false\\n");
  else if (field === "url") process.stdout.write("https://example.invalid/releases/" + read("tag") + "\\n");
  else if (field === "assets") {
    const assets = JSON.parse(read("assets.json", "{}"));
    if (jq === ".assets[].name") process.stdout.write(Object.keys(assets).join("\\n") + "\\n");
    else {
      const match = jq.match(/name == \"([^\"]+)\"/);
      if (match && assets[match[1]]) process.stdout.write("sha256:" + assets[match[1]] + "\\n");
    }
  }
  process.exit(0);
}
process.exit(0);
`;
  await writeFile(path.join(fakeBin, "gh"), ghStub);
  await chmod(path.join(fakeBin, "gh"), 0o755);
  const npmStub = `#!/usr/bin/env bash
set -euo pipefail
printf 'npm %s\\n' "$*" >> "$COMMAND_LOG"
if [[ "\${1:-} \${2:-}" == "run package" ]]; then
  if [[ "\${FAKE_NPM_FAIL_PACKAGE:-0}" == "1" ]]; then
    exit 1
  fi
  version="$(node -p "require('./package.json').version")"
  arch="$(uname -m)"
  mkdir -p dist/fund-pulse.app/Contents release/swift
  printf '<plist/>\\n' > dist/fund-pulse.app/Contents/Info.plist
  printf 'zip-%s\\n' "$version" > "release/swift/fund-pulse-\${version}-\${arch}-swift.zip"
  printf 'dmg-%s\\n' "$version" > "release/swift/fund-pulse-\${version}-\${arch}-swift.dmg"
  if [[ "\${FAKE_NPM_MUTATE_FRAGMENT:-0}" == "1" ]]; then
    printf '构建期间发生变化。\\n' >> .release-notes/release-workflow.md
  fi
fi
`;
  await writeFile(path.join(fakeBin, "npm"), npmStub);
  await chmod(path.join(fakeBin, "npm"), 0o755);
  for (const commandName of ["swift", "codesign"]) {
    await writeFile(path.join(fakeBin, commandName), `#!/usr/bin/env bash\nprintf '%s %s\\n' '${commandName}' "$*" >> "$COMMAND_LOG"\n`);
    await chmod(path.join(fakeBin, commandName), 0o755);
  }
  await writeFile(path.join(fakeBin, "security"), "#!/usr/bin/env bash\nprintf '  1) ABCDEF \"Apple Development: Release Test (TEAMID)\"\\n'\n");
  await chmod(path.join(fakeBin, "security"), 0o755);
  await writeFile(path.join(fakeBin, "plutil"), "#!/usr/bin/env bash\nnode -p \"require('./package.json').version\"\n");
  await chmod(path.join(fakeBin, "plutil"), 0o755);
  await chmod(path.join(repository, "scripts/release.sh"), 0o755);

  await run("git", ["init", "--bare", remote]);
  await git(repository, "init", "-b", "main");
  await git(repository, "config", "user.name", "Release Test");
  await git(repository, "config", "user.email", "release-test@example.com");
  await git(repository, "add", ".");
  await git(repository, "commit", "-m", "chore: initial release fixture");
  await git(repository, "tag", "-a", "v1.0.41", "-m", "v1.0.41");
  await git(repository, "remote", "add", "origin", remote);
  await git(repository, "push", "-u", "origin", "main", "refs/tags/v1.0.41");

  if (fragment !== "none") {
    const content = fragment === "valid"
      ? "---\ntype: optimization\n---\n\n发布说明改为结构化生成。\n"
      : "---\ntype: unknown\n---\n\n损坏的发布说明。\n";
    await writeFile(path.join(repository, ".release-notes/release-workflow.md"), content);
    await git(repository, "add", ".release-notes/release-workflow.md");
    await git(repository, "commit", "-m", "refactor: improve release notes");
    await git(repository, "push", "origin", "main");
  }

  const environment = {
    ...process.env,
    PATH: `${fakeBin}:${process.env.PATH}`,
    GH_LOG: ghLog,
    COMMAND_LOG: commandLog,
    FAKE_GH_STATE: ghState,
    TMPDIR: temporary,
  };

  return {
    root,
    repository,
    remote,
    ghLog,
    commandLog,
    ghState,
    environment,
    cleanup: () => rm(root, { recursive: true, force: true }),
  };
}

async function runRelease(fixture, args = []) {
  return run("bash", ["scripts/release.sh", "--dry-run", "--bump", "patch", "--yes", ...args], {
    cwd: fixture.repository,
    env: fixture.environment,
  });
}

async function runRealRelease(fixture, args = [], environment = {}) {
  try {
    return await run("bash", ["scripts/release.sh", "--bump", "patch", "--yes", ...args], {
      cwd: fixture.repository,
      env: { ...fixture.environment, ...environment },
    });
  } catch (error) {
    error.message += `\n--- release stdout ---\n${error.stdout ?? ""}\n--- release stderr ---\n${error.stderr ?? ""}`;
    throw error;
  }
}

async function repositoryFingerprint(fixture) {
  const [head, status, tags, packageJson, changelog, fragment] = await Promise.all([
    git(fixture.repository, "rev-parse", "HEAD"),
    git(fixture.repository, "status", "--porcelain=v1"),
    git(fixture.repository, "show-ref", "--tags"),
    readFile(path.join(fixture.repository, "package.json"), "utf8"),
    readFile(path.join(fixture.repository, "CHANGELOG.md"), "utf8"),
    readFile(path.join(fixture.repository, ".release-notes/release-workflow.md"), "utf8").catch(() => null),
  ]);
  return { head: head.stdout, status: status.stdout, tags: tags.stdout, packageJson, changelog, fragment };
}

test("release dry-run previews structured notes and performs zero repository or remote writes", async () => {
  const fixture = await createReleaseFixture();
  try {
    const before = await repositoryFingerprint(fixture);
    const remoteBefore = await git(fixture.repository, "ls-remote", "origin");
    const result = await runRelease(fixture);
    const after = await repositoryFingerprint(fixture);
    const remoteAfter = await git(fixture.repository, "ls-remote", "origin");

    assert.match(result.stdout, /v1\.0\.42/);
    assert.match(result.stdout, /发布说明改为结构化生成。/);
    assert.match(result.stdout, /DRY-RUN/);
    assert.deepEqual(after, before);
    assert.equal(remoteAfter.stdout, remoteBefore.stdout);
    const ghCalls = await readFile(fixture.ghLog, "utf8");
    assert.doesNotMatch(ghCalls, /release (?:create|edit|upload|delete)/);
    const commands = await readFile(fixture.commandLog, "utf8");
    assert.match(commands, /npm run test:release:unit/);
    assert.match(commands, /swift test/);
  } finally {
    await fixture.cleanup();
  }
});

test("real release path commits only metadata, atomically pushes, verifies a draft, and publishes it", async () => {
  const fixture = await createReleaseFixture();
  try {
    const result = await runRealRelease(fixture);
    const packageJson = JSON.parse(await readFile(path.join(fixture.repository, "package.json"), "utf8"));
    const changelog = await readFile(path.join(fixture.repository, "CHANGELOG.md"), "utf8");
    const status = await git(fixture.repository, "status", "--porcelain=v1");
    const head = await git(fixture.repository, "rev-parse", "HEAD");
    const tagCommit = await git(fixture.repository, "rev-parse", "v1.0.42^{commit}");
    const remoteMain = await git(fixture.repository, "ls-remote", "origin", "refs/heads/main");
    const arch = (await run("uname", ["-m"])).stdout.trim();

    assert.match(result.stdout, /发布完成：v1\.0\.42/);
    assert.equal(packageJson.version, "1.0.42");
    assert.match(changelog, /## v1\.0\.42/);
    assert.match(changelog, /发布说明改为结构化生成。/);
    await assert.rejects(
      () => readFile(path.join(fixture.repository, ".release-notes/release-workflow.md"), "utf8"),
      /ENOENT/,
    );
    assert.equal(status.stdout, "");
    assert.equal(tagCommit.stdout, head.stdout);
    assert.equal(remoteMain.stdout.split("\t")[0], head.stdout.trim());
    assert.equal(await readFile(path.join(fixture.ghState, "draft"), "utf8"), "false");
    const body = await readFile(path.join(fixture.ghState, "body"), "utf8");
    assert.match(body, /发布说明改为结构化生成。/);
    assert.doesNotMatch(body, /dry-run/);
    const assets = JSON.parse(await readFile(path.join(fixture.ghState, "assets.json"), "utf8"));
    assert.deepEqual(Object.keys(assets).sort(), [
      `fund-pulse-1.0.42-${arch}-swift.dmg`,
      `fund-pulse-1.0.42-${arch}-swift.zip`,
      "latest-mac.yml",
    ]);
    const ghCalls = await readFile(fixture.ghLog, "utf8");
    assert.ok(ghCalls.indexOf("release create") < ghCalls.indexOf("release upload"));
    assert.ok(ghCalls.indexOf("release upload") < ghCalls.indexOf("release edit"));
  } finally {
    await fixture.cleanup();
  }
});

test("asset upload failure preserves the draft and recovery files", async () => {
  const fixture = await createReleaseFixture();
  try {
    let recoveryNotesPath = "";
    await assert.rejects(
      () => runRealRelease(fixture, [], { FAKE_GH_FAIL_UPLOAD: "1" }),
      (error) => {
        assert.notEqual(error.code, 0);
        assert.match(error.stderr, /Draft Release 已保留/);
        const notesMatch = error.stderr.match(/Release notes：(.+)/);
        assert.ok(notesMatch);
        recoveryNotesPath = notesMatch[1].trim();
        return true;
      },
    );
    assert.equal((await readFile(recoveryNotesPath, "utf8")).includes("发布说明改为结构化生成。"), true);
    assert.equal(await readFile(path.join(fixture.ghState, "draft"), "utf8"), "true");
    const assets = JSON.parse(await readFile(path.join(fixture.ghState, "assets.json"), "utf8"));
    assert.equal(Object.keys(assets).length, 1);
    const localTag = await git(fixture.repository, "rev-parse", "v1.0.42^{commit}");
    const remoteTag = await git(fixture.repository, "ls-remote", "origin", "refs/tags/v1.0.42^{}");
    assert.equal(remoteTag.stdout.split("\t")[0], localTag.stdout.trim());
  } finally {
    await fixture.cleanup();
  }
});

test("draft creation failure preserves recovery files after the release refs are pushed", async () => {
  const fixture = await createReleaseFixture();
  try {
    let recoveryNotesPath = "";
    let recoveryManifestPath = "";
    await assert.rejects(
      () => runRealRelease(fixture, [], { FAKE_GH_FAIL_CREATE: "1" }),
      (error) => {
        assert.notEqual(error.code, 0);
        assert.match(error.stderr, /发布提交和 tag 已保留/);
        const notesMatch = error.stderr.match(/Release notes：(.+)/);
        const manifestMatch = error.stderr.match(/Manifest：(.+)/);
        assert.ok(notesMatch);
        assert.ok(manifestMatch);
        recoveryNotesPath = notesMatch[1].trim();
        recoveryManifestPath = manifestMatch[1].trim();
        return true;
      },
    );

    assert.match(await readFile(recoveryNotesPath, "utf8"), /发布说明改为结构化生成。/);
    const manifest = JSON.parse(await readFile(recoveryManifestPath, "utf8"));
    assert.equal(manifest.version, "1.0.42");
    await assert.rejects(() => readFile(path.join(fixture.ghState, "created"), "utf8"), /ENOENT/);

    const localHead = await git(fixture.repository, "rev-parse", "HEAD");
    const localTag = await git(fixture.repository, "rev-parse", "v1.0.42^{commit}");
    const remoteMain = await git(fixture.repository, "ls-remote", "origin", "refs/heads/main");
    const remoteTag = await git(fixture.repository, "ls-remote", "origin", "refs/tags/v1.0.42^{}");
    assert.equal(localTag.stdout, localHead.stdout);
    assert.equal(remoteMain.stdout.split("\t")[0], localHead.stdout.trim());
    assert.equal(remoteTag.stdout.split("\t")[0], localHead.stdout.trim());
  } finally {
    await fixture.cleanup();
  }
});

test("a packaging failure restores the owned version change without creating refs", async () => {
  const fixture = await createReleaseFixture();
  try {
    await assert.rejects(() => runRealRelease(fixture, [], { FAKE_NPM_FAIL_PACKAGE: "1" }));
    const packageJson = JSON.parse(await readFile(path.join(fixture.repository, "package.json"), "utf8"));
    assert.equal(packageJson.version, "1.0.41");
    await assert.rejects(() => git(fixture.repository, "rev-parse", "v1.0.42"));
    assert.equal(await readFile(path.join(fixture.repository, ".release-notes/release-workflow.md"), "utf8"), "---\ntype: optimization\n---\n\n发布说明改为结构化生成。\n");
  } finally {
    await fixture.cleanup();
  }
});

test("fragment changes after preview stop the release before metadata is committed", async () => {
  const fixture = await createReleaseFixture();
  try {
    await assert.rejects(
      () => runRealRelease(fixture, [], { FAKE_NPM_MUTATE_FRAGMENT: "1" }),
      (error) => error.code !== 0 && /fragments changed after initial confirmation/i.test(error.stderr),
    );
    const packageJson = JSON.parse(await readFile(path.join(fixture.repository, "package.json"), "utf8"));
    assert.equal(packageJson.version, "1.0.41");
    assert.match(await readFile(path.join(fixture.repository, ".release-notes/release-workflow.md"), "utf8"), /构建期间发生变化/);
    await assert.rejects(() => git(fixture.repository, "rev-parse", "v1.0.42"));
  } finally {
    await fixture.cleanup();
  }
});

for (const dirtyCase of ["unstaged", "staged", "untracked"]) {
  test(`release refuses a ${dirtyCase} worktree before changing the version`, async () => {
    const fixture = await createReleaseFixture();
    try {
      if (dirtyCase === "untracked") {
        await writeFile(path.join(fixture.repository, "unexpected.txt"), "unexpected\n");
      } else {
        await appendFile(path.join(fixture.repository, "CHANGELOG.md"), "dirty\n");
        if (dirtyCase === "staged") await git(fixture.repository, "add", "CHANGELOG.md");
      }
      const packageBefore = await readFile(path.join(fixture.repository, "package.json"), "utf8");

      await assert.rejects(
        () => runRelease(fixture),
        (error) => error.code !== 0 && /工作区必须保持干净/.test(error.stderr),
      );
      assert.equal(await readFile(path.join(fixture.repository, "package.json"), "utf8"), packageBefore);
    } finally {
      await fixture.cleanup();
    }
  });
}

test("release requires a fragment by default and supports an explicit empty release", async () => {
  const fixture = await createReleaseFixture({ fragment: "none" });
  try {
    await assert.rejects(
      () => runRelease(fixture),
      (error) => error.code !== 0 && /No release-note fragments/i.test(error.stderr),
    );
    const result = await runRelease(fixture, ["--allow-empty-notes"]);
    assert.match(result.stdout, /本次发布仅重新打包，不包含功能变更。/);
  } finally {
    await fixture.cleanup();
  }
});

test("allow-empty never hides a malformed fragment", async () => {
  const fixture = await createReleaseFixture({ fragment: "malformed" });
  try {
    await assert.rejects(
      () => runRelease(fixture, ["--allow-empty-notes"]),
      (error) => error.code !== 0 && /unsupported type/i.test(error.stderr),
    );
  } finally {
    await fixture.cleanup();
  }
});

test("manual notes can cover an empty release without being modified", async () => {
  const fixture = await createReleaseFixture({ fragment: "none" });
  try {
    const manualPath = path.join(fixture.root, "manual notes.md");
    const manualNotes = "## 更新内容\n\n- 修复紧急发布问题。\n";
    await writeFile(manualPath, manualNotes);

    const result = await runRelease(fixture, ["--notes-file", manualPath]);

    assert.match(result.stdout, /修复紧急发布问题。/);
    assert.equal(await readFile(manualPath, "utf8"), manualNotes);
  } finally {
    await fixture.cleanup();
  }
});

test("legacy dirty-worktree escape hatches are rejected", async () => {
  const fixture = await createReleaseFixture();
  try {
    for (const option of ["--commit-all", "--allow-dirty"]) {
      await assert.rejects(
        () => runRelease(fixture, [option]),
        (error) => error.code !== 0 && /Unknown option/.test(error.stderr),
      );
    }
  } finally {
    await fixture.cleanup();
  }
});

test("release rejects version downgrades and tags that do not match the app version", async () => {
  const fixture = await createReleaseFixture();
  try {
    await assert.rejects(
      () => runRelease(fixture, ["--version", "1.0.40"]),
      (error) => error.code !== 0 && /必须高于当前版本/.test(error.stderr),
    );
    await assert.rejects(
      () => runRelease(fixture, ["--tag", "v-custom"]),
      (error) => error.code !== 0 && /tag 必须与版本一致/.test(error.stderr),
    );
  } finally {
    await fixture.cleanup();
  }
});

test("release script never stages the entire worktree and uses a draft verification flow", async () => {
  const source = await readFile(path.join(repositoryRoot, "scripts/release.sh"), "utf8");
  assert.doesNotMatch(source, /git add -A/);
  assert.doesNotMatch(source, /--commit-all|--allow-dirty/);
  assert.match(source, /git push --atomic/);
  assert.match(source, /gh release create[\s\S]*--draft/);
  assert.match(source, /DRAFT_CREATED=1[\s\S]*gh release upload/);
  assert.match(source, /gh release edit[\s\S]*--draft=false/);
  assert.match(source, /verify_remote_release_body/);
});

test("local Apple Development packages disable secure timestamps without weakening verification", async () => {
  const source = await readFile(path.join(repositoryRoot, "script/package_swift.sh"), "utf8");
  assert.match(source, /FUND_PULSE_BUILD_CONFIGURATION=release/);
  assert.match(source, /SIGN_TIMESTAMP_OPTION="--timestamp"/);
  assert.match(source, /SIGNING_KIND="apple-development"[\s\S]*SIGN_TIMESTAMP_OPTION="--timestamp=none"/);
  assert.match(source, /codesign --force --deep --options runtime "\$SIGN_TIMESTAMP_OPTION"/);
  assert.match(source, /codesign --verify --deep --strict/);
  assert.match(source, /codesign --verify --verbose=2 "\$DMG_PATH"/);
});
