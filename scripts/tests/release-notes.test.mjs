import assert from "node:assert/strict";
import { chmod, mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  applyReleaseMetadata,
  buildChangelogEntry,
  buildReleaseNotes,
  loadReleaseNoteFragments,
  parseReleaseNoteFragment,
  prependChangelogEntry,
  validateManualReleaseNotes,
} from "../lib/release-notes.mjs";

const validFragment = (type, body) => `---\ntype: ${type}\n---\n\n${body}\n`;

async function withTempDirectory(run) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "fund-pulse-release-notes-test-"));
  try {
    return await run(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function releaseContext(overrides = {}) {
  return {
    version: "1.0.42",
    tag: "v1.0.42",
    previousTag: "v1.0.41",
    repository: "iamzjt-front-end/fund-pulse",
    assets: {
      zip: { name: "fund-pulse-1.0.42-arm64-swift.zip", sha256: "zip-sha" },
      dmg: { name: "fund-pulse-1.0.42-arm64-swift.dmg", sha256: "dmg-sha" },
      feed: { name: "latest-mac.yml", sha256: "feed-sha" },
    },
    ...overrides,
  };
}

test("parses a valid fragment and normalizes BOM, CRLF, and wrapped text", () => {
  const fragment = parseReleaseNoteFragment(
    "\uFEFF---\r\ntype: optimization\r\n---\r\n\r\n行情刷新改为串行合并，\r\n避免重复请求。\r\n",
    "quote-refresh.md",
  );

  assert.deepEqual(fragment, {
    source: "quote-refresh.md",
    type: "optimization",
    text: "行情刷新改为串行合并，避免重复请求。",
  });
});

test("accepts every supported fragment type", () => {
  for (const type of ["breaking", "feature", "fix", "optimization", "other"]) {
    assert.equal(parseReleaseNoteFragment(validFragment(type, `${type} change`)).type, type);
  }
});

test("rejects malformed fragment metadata and content", () => {
  const cases = [
    ["missing front matter", "type: feature\n功能说明", /front matter/i],
    ["unterminated front matter", "---\ntype: feature\n功能说明", /front matter/i],
    ["missing type", "---\n\n---\n功能说明", /missing required type metadata/i],
    ["invalid metadata syntax", "---\ntype feature\n---\n功能说明", /invalid metadata/i],
    ["unsupported type", validFragment("docs", "功能说明"), /unsupported.*type/i],
    ["unknown metadata", "---\ntype: feature\nscope: panel\n---\n功能说明", /unknown.*scope/i],
    ["duplicate metadata", "---\ntype: feature\ntype: fix\n---\n功能说明", /duplicate.*type/i],
    ["empty content", validFragment("feature", "   "), /empty/i],
    ["markdown list content", validFragment("feature", "- 功能说明"), /plain sentence/i],
  ];

  for (const [name, content, expectation] of cases) {
    assert.throws(() => parseReleaseNoteFragment(content, `${name}.md`), expectation, name);
  }
});

test("rejects invalid fragment objects passed directly to renderers", () => {
  assert.throws(
    () => buildReleaseNotes({ ...releaseContext(), fragments: [{ source: "bad.md", type: "docs", text: "无效类型。" }] }),
    /unsupported release-note type/i,
  );
  assert.throws(
    () => buildReleaseNotes({ ...releaseContext(), fragments: [{ source: "bad.md", type: "fix", text: "TODO" }] }),
    /meaningful content/i,
  );
});

test("rejects placeholder and generic release-only descriptions", () => {
  for (const body of [
    "TODO",
    "TBD",
    "待补充",
    "chore: release v1.0.42",
    "本次发布包含重新打包和发布产物更新。",
    "本次发布仅重新打包，不包含功能变更。",
  ]) {
    assert.throws(
      () => parseReleaseNoteFragment(validFragment("other", body), "placeholder.md"),
      /meaningful/i,
      body,
    );
  }
});

test("loads fragments deterministically while ignoring documentation and non-Markdown files", async () => {
  await withTempDirectory(async (directory) => {
    await writeFile(path.join(directory, "README.md"), "fragment guide");
    await writeFile(path.join(directory, ".DS_Store"), "ignored");
    await writeFile(path.join(directory, "notes.txt"), "ignored");
    await writeFile(path.join(directory, "z-fix.md"), validFragment("fix", "修复刷新失败后的状态残留。"));
    await writeFile(path.join(directory, "a-feature.md"), validFragment("feature", "新增结构化发布说明。"));

    const result = await loadReleaseNoteFragments(directory);

    assert.deepEqual(result.fragments.map(({ source, type, text }) => ({ source, type, text })), [
      { source: "a-feature.md", type: "feature", text: "新增结构化发布说明。" },
      { source: "z-fix.md", type: "fix", text: "修复刷新失败后的状态残留。" },
    ]);
    assert.equal(result.manifest.length, 2);
    assert.match(result.manifest[0].sha256, /^[a-f0-9]{64}$/);
  });
});

test("treats a missing fragment directory as empty and rejects nested or linked Markdown entries", async () => {
  await withTempDirectory(async (directory) => {
    assert.deepEqual(await loadReleaseNoteFragments(path.join(directory, "missing")), { fragments: [], manifest: [] });

    const fragmentsDirectory = path.join(directory, "fragments");
    await mkdir(fragmentsDirectory);
    await mkdir(path.join(fragmentsDirectory, "nested.md"));
    await assert.rejects(() => loadReleaseNoteFragments(fragmentsDirectory), /nested release-note directories/i);
    await rm(path.join(fragmentsDirectory, "nested.md"), { recursive: true });

    const target = path.join(directory, "target.md");
    await writeFile(target, validFragment("fix", "修复符号链接问题。"));
    await symlink(target, path.join(fragmentsDirectory, "linked.md"));
    await assert.rejects(() => loadReleaseNoteFragments(fragmentsDirectory), /regular file/i);
  });
});

test("rejects duplicate release-note descriptions across fragments", async () => {
  await withTempDirectory(async (directory) => {
    await writeFile(path.join(directory, "one.md"), validFragment("feature", "新增结构化发布说明。"));
    await writeFile(path.join(directory, "two.md"), validFragment("optimization", "新增结构化发布说明。"));

    await assert.rejects(() => loadReleaseNoteFragments(directory), /duplicate.*新增结构化发布说明/i);
  });
});

test("builds categorized release notes in stable product-facing order", () => {
  const notes = buildReleaseNotes({
    ...releaseContext(),
    fragments: [
      { source: "z.md", type: "other", text: "补充发布流程文档。" },
      { source: "b.md", type: "optimization", text: "行情刷新改为串行合并。" },
      { source: "a.md", type: "feature", text: "新增结构化发布说明。" },
      { source: "c.md", type: "fix", text: "修复保存失败污染内存状态的问题。" },
      { source: "d.md", type: "breaking", text: "发布前现在要求工作区保持干净。" },
    ],
  });

  const headings = ["### 重要变更", "### 新功能", "### 问题修复", "### 功能优化", "### 其他变更"];
  for (let index = 1; index < headings.length; index += 1) {
    assert.ok(notes.indexOf(headings[index - 1]) < notes.indexOf(headings[index]));
  }
  assert.match(notes, /- 新增结构化发布说明。/);
  assert.match(notes, /ZIP SHA-256：zip-sha/);
  assert.match(notes, /\[v1\.0\.41\.\.\.v1\.0\.42\]\(https:\/\/github\.com\/iamzjt-front-end\/fund-pulse\/compare\/v1\.0\.41\.\.\.v1\.0\.42\)/);
});

test("sorts entries by source within each category", () => {
  const notes = buildReleaseNotes({
    ...releaseContext(),
    fragments: [
      { source: "z-last.md", type: "fix", text: "第二条修复。" },
      { source: "a-first.md", type: "fix", text: "第一条修复。" },
    ],
  });

  assert.ok(notes.indexOf("第一条修复") < notes.indexOf("第二条修复"));
});

test("rejects empty generated notes unless explicitly allowed", () => {
  assert.throws(() => buildReleaseNotes({ ...releaseContext(), fragments: [] }), /no release-note fragments/i);

  const notes = buildReleaseNotes({ ...releaseContext(), fragments: [], allowEmpty: true });
  assert.match(notes, /本次发布仅重新打包，不包含功能变更。/);
});

test("validates release context and omits compare links without a previous tag", () => {
  const invalidCases = [
    [{ version: "1.0" }, /invalid release version/i],
    [{ tag: "" }, /release tag is required/i],
    [{ repository: "invalid" }, /invalid github repository/i],
    [{ assets: { ...releaseContext().assets, zip: { name: "app.zip", sha256: "" } } }, /incomplete for zip/i],
  ];
  for (const [overrides, expectation] of invalidCases) {
    assert.throws(
      () => buildReleaseNotes({ ...releaseContext(overrides), fragments: [], allowEmpty: true }),
      expectation,
    );
  }

  const notes = buildReleaseNotes({ ...releaseContext({ previousTag: "" }), fragments: [], allowEmpty: true });
  assert.doesNotMatch(notes, /## 完整变更/);
});

test("uses a validated manual notes file as an exact GitHub body override", () => {
  const manual = "## 更新内容\n\n- 修复菜单栏刷新问题。\n\n## 补充说明\n\n无需迁移数据。\n";
  assert.equal(validateManualReleaseNotes(manual, "manual.md"), manual.trimEnd());
  assert.equal(
    buildReleaseNotes({ ...releaseContext(), fragments: [], manualNotes: manual }),
    manual.trimEnd() + "\n",
  );
});

test("rejects empty, placeholder, build-only, and generic manual notes", () => {
  for (const notes of [
    "",
    "## 更新内容\n\nTODO\n",
    "## 构建信息\n\n- App 版本：1.0.42\n- ZIP：app.zip\n",
    "## 构建信息\n\n- App 版本: 1.0.42\n- ZIP: app.zip\n",
    "## 更新内容\n\n- App 版本: 1.0.42\n",
    "## 更新内容\n\n- chore: release v1.0.42\n",
    "## 更新内容\n\n- 本次发布仅重新打包，不包含功能变更。\n",
    "## 更新内容\n\nTODO\n\n## 补充说明\n\n无需迁移数据。\n",
  ]) {
    assert.throws(() => validateManualReleaseNotes(notes, "manual.md"), /meaningful/i);
  }
});

test("builds a categorized changelog entry from fragments", () => {
  const entry = buildChangelogEntry({
    version: "1.0.42",
    date: "2026-07-10",
    fragments: [
      { source: "feature.md", type: "feature", text: "新增结构化发布说明。" },
      { source: "fix.md", type: "fix", text: "修复空说明仍可发布的问题。" },
    ],
  });

  assert.match(entry, /^## v1\.0\.42 - 2026-07-10/m);
  assert.match(entry, /### 新功能\n\n- 新增结构化发布说明。/);
  assert.match(entry, /### 问题修复\n\n- 修复空说明仍可发布的问题。/);
  assert.doesNotMatch(entry, /构建信息/);
});

test("extracts the update section from manual notes for the changelog", () => {
  const entry = buildChangelogEntry({
    version: "1.0.42",
    date: "2026-07-10",
    fragments: [],
    manualNotes: "## 更新内容\n\n- 修复菜单栏刷新问题。\n\n## 构建信息\n\n- ZIP：app.zip\n",
  });

  assert.match(entry, /- 修复菜单栏刷新问题。/);
  assert.doesNotMatch(entry, /ZIP：app\.zip/);
});

test("uses meaningful manual prose when no update heading exists", () => {
  const entry = buildChangelogEntry({
    version: "1.0.42",
    date: "2026-07-10",
    fragments: [],
    manualNotes: "修复菜单栏刷新问题。\n无需迁移数据。\n",
  });
  assert.match(entry, /- 修复菜单栏刷新问题。/);
  assert.match(entry, /- 无需迁移数据。/);
});

test("validates changelog entry version, date, and empty input", () => {
  assert.throws(
    () => buildChangelogEntry({ version: "1.0", date: "2026-07-10", fragments: [], allowEmpty: true }),
    /invalid release version/i,
  );
  assert.throws(
    () => buildChangelogEntry({ version: "1.0.42", date: "10-07-2026", fragments: [], allowEmpty: true }),
    /invalid release date/i,
  );
  assert.throws(
    () => buildChangelogEntry({ version: "1.0.42", date: "2026-07-10", fragments: [] }),
    /no release-note fragments/i,
  );

  assert.equal(
    prependChangelogEntry("# Changelog\n", "## v1.0.42 - 2026-07-10\n\n- 新版本。\n", "1.0.42"),
    "# Changelog\n\n## v1.0.42 - 2026-07-10\n\n- 新版本。\n",
  );
});

test("prepends a changelog entry and rejects duplicates or malformed changelogs", () => {
  const existing = "# Changelog\n\n## v1.0.41 - 2026-07-08\n\n- 旧版本。\n";
  const entry = "## v1.0.42 - 2026-07-10\n\n- 新版本。\n";
  const updated = prependChangelogEntry(existing, entry, "1.0.42");

  assert.ok(updated.indexOf("v1.0.42") < updated.indexOf("v1.0.41"));
  assert.throws(() => prependChangelogEntry(updated, entry, "1.0.42"), /already contains.*v1\.0\.42/i);
  assert.throws(() => prependChangelogEntry("No changelog heading\n", entry, "1.0.42"), /# Changelog/);
});

test("applies release metadata atomically and consumes only manifested fragments", async () => {
  await withTempDirectory(async (directory) => {
    const fragmentsDirectory = path.join(directory, ".release-notes");
    const changelogPath = path.join(directory, "CHANGELOG.md");
    await mkdir(fragmentsDirectory);
    await writeFile(path.join(fragmentsDirectory, "README.md"), "guide");
    await writeFile(path.join(fragmentsDirectory, "feature.md"), validFragment("feature", "新增结构化发布说明。"));
    await writeFile(path.join(fragmentsDirectory, "ignored.txt"), "keep me");
    await writeFile(changelogPath, "# Changelog\n\n## v1.0.41 - 2026-07-08\n\n- 旧版本。\n");

    const loaded = await loadReleaseNoteFragments(fragmentsDirectory);
    const entry = buildChangelogEntry({ version: "1.0.42", date: "2026-07-10", fragments: loaded.fragments });
    await applyReleaseMetadata({
      changelogPath,
      fragmentsDirectory,
      entry,
      version: "1.0.42",
      manifest: loaded.manifest,
    });

    assert.match(await readFile(changelogPath, "utf8"), /v1\.0\.42/);
    await assert.rejects(() => readFile(path.join(fragmentsDirectory, "feature.md"), "utf8"), /ENOENT/);
    assert.equal(await readFile(path.join(fragmentsDirectory, "README.md"), "utf8"), "guide");
    assert.equal(await readFile(path.join(fragmentsDirectory, "ignored.txt"), "utf8"), "keep me");
  });
});

test("refuses to apply a stale manifest without changing the changelog or fragments", async () => {
  await withTempDirectory(async (directory) => {
    const fragmentsDirectory = path.join(directory, ".release-notes");
    const changelogPath = path.join(directory, "CHANGELOG.md");
    const fragmentPath = path.join(fragmentsDirectory, "feature.md");
    const originalChangelog = "# Changelog\n\n## v1.0.41 - 2026-07-08\n\n- 旧版本。\n";
    await mkdir(fragmentsDirectory);
    await writeFile(fragmentPath, validFragment("feature", "新增结构化发布说明。"));
    await writeFile(changelogPath, originalChangelog);
    const loaded = await loadReleaseNoteFragments(fragmentsDirectory);
    await writeFile(fragmentPath, validFragment("feature", "片段在生成后被修改。"));

    await assert.rejects(
      () => applyReleaseMetadata({
        changelogPath,
        fragmentsDirectory,
        entry: "## v1.0.42 - 2026-07-10\n\n- 新版本。\n",
        version: "1.0.42",
        manifest: loaded.manifest,
      }),
      /changed after generation/i,
    );
    assert.equal(await readFile(changelogPath, "utf8"), originalChangelog);
    assert.match(await readFile(fragmentPath, "utf8"), /片段在生成后被修改/);
  });
});

test("restores the changelog when fragment deletion fails", async () => {
  await withTempDirectory(async (directory) => {
    const fragmentsDirectory = path.join(directory, ".release-notes");
    const changelogPath = path.join(directory, "CHANGELOG.md");
    const originalChangelog = "# Changelog\n\n## v1.0.41 - 2026-07-08\n\n- 旧版本。\n";
    await mkdir(fragmentsDirectory);
    await writeFile(path.join(fragmentsDirectory, "feature.md"), validFragment("feature", "新增结构化发布说明。"));
    await writeFile(changelogPath, originalChangelog);
    const loaded = await loadReleaseNoteFragments(fragmentsDirectory);
    await chmod(fragmentsDirectory, 0o555);
    try {
      await assert.rejects(
        () => applyReleaseMetadata({
          changelogPath,
          fragmentsDirectory,
          entry: "## v1.0.42 - 2026-07-10\n\n- 新版本。\n",
          version: "1.0.42",
          manifest: loaded.manifest,
        }),
        /EACCES|EPERM/,
      );
      assert.equal(await readFile(changelogPath, "utf8"), originalChangelog);
    } finally {
      await chmod(fragmentsDirectory, 0o755);
    }
  });
});
