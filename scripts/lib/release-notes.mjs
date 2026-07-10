import { createHash, randomUUID } from "node:crypto";
import {
  readdir,
  readFile,
  rename,
  rm,
  unlink,
  writeFile,
} from "node:fs/promises";
import path from "node:path";

const TYPE_DEFINITIONS = Object.freeze([
  ["breaking", "重要变更"],
  ["feature", "新功能"],
  ["fix", "问题修复"],
  ["optimization", "功能优化"],
  ["other", "其他变更"],
]);

export const RELEASE_NOTE_TYPES = Object.freeze(TYPE_DEFINITIONS.map(([type]) => type));

const BUILD_DETAIL_PATTERN = /^(?:[-*]\s*)?(?:App 版本|ZIP|ZIP SHA-256|DMG|DMG SHA-256|更新索引|更新索引 SHA-256)[：:]/i;
const PLACEHOLDER_PATTERN = /^(?:todo|tbd|待补充|待完善|稍后补充)[.!。！]?$/i;
const RELEASE_ONLY_PATTERN = /^(?:[-*]\s*)?chore:\s*release\b/i;
const REPACKAGE_ONLY_PATTERN = /^(?:[-*]\s*)?(?:本次发布包含重新打包和发布产物更新|本次发布仅重新打包，不包含功能变更)。?$/;

function normalizeNewlines(value) {
  return String(value).replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n");
}

function normalizeSentence(value) {
  return normalizeNewlines(value)
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .replace(/([，。；：！？、])\s+/g, "$1")
    .trim();
}

function isMeaningfulText(value) {
  const normalized = normalizeSentence(value);
  return normalized.length >= 4
    && !PLACEHOLDER_PATTERN.test(normalized)
    && !RELEASE_ONLY_PATTERN.test(normalized)
    && !REPACKAGE_ONLY_PATTERN.test(normalized);
}

function assertSupportedFragment(fragment) {
  if (!fragment || !RELEASE_NOTE_TYPES.includes(fragment.type)) {
    throw new Error(`Unsupported release-note type: ${fragment?.type ?? "<missing>"}`);
  }
  if (!isMeaningfulText(fragment.text)) {
    throw new Error(`Release-note fragment ${fragment.source ?? "<unknown>"} must contain meaningful content.`);
  }
}

export function parseReleaseNoteFragment(content, source = "<fragment>") {
  const normalized = normalizeNewlines(content);
  const match = normalized.match(/^---[ \t]*\n([\s\S]*?)\n---[ \t]*(?:\n|$)([\s\S]*)$/);
  if (!match) {
    throw new Error(`Release-note fragment ${source} must contain valid front matter delimited by --- lines.`);
  }

  const metadata = new Map();
  for (const rawLine of match[1].split("\n")) {
    const line = rawLine.trim();
    if (!line) continue;
    const fieldMatch = line.match(/^([a-z][a-z0-9-]*):\s*(.*?)$/i);
    if (!fieldMatch) {
      throw new Error(`Release-note fragment ${source} has invalid metadata: ${line}`);
    }
    const key = fieldMatch[1].toLowerCase();
    if (metadata.has(key)) {
      throw new Error(`Release-note fragment ${source} has duplicate metadata field: ${key}`);
    }
    if (key !== "type") {
      throw new Error(`Release-note fragment ${source} has unknown metadata field: ${key}`);
    }
    metadata.set(key, fieldMatch[2].trim().toLowerCase());
  }

  const type = metadata.get("type");
  if (!type) {
    throw new Error(`Release-note fragment ${source} is missing required type metadata.`);
  }
  if (!RELEASE_NOTE_TYPES.includes(type)) {
    throw new Error(`Release-note fragment ${source} has unsupported type: ${type}`);
  }

  const rawBody = match[2].trim();
  if (!rawBody) {
    throw new Error(`Release-note fragment ${source} has empty content.`);
  }
  if (/^[-*#>]/.test(rawBody)) {
    throw new Error(`Release-note fragment ${source} must use a plain sentence, not Markdown list or heading syntax.`);
  }

  const text = normalizeSentence(rawBody);
  if (!isMeaningfulText(text)) {
    throw new Error(`Release-note fragment ${source} must contain meaningful content.`);
  }

  return { source, type, text };
}

function digest(content) {
  return createHash("sha256").update(content).digest("hex");
}

export async function loadReleaseNoteFragments(directory) {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error?.code === "ENOENT") return { fragments: [], manifest: [] };
    throw error;
  }

  const fragments = [];
  const manifest = [];
  const descriptions = new Map();
  const sortedEntries = entries.toSorted((left, right) => left.name.localeCompare(right.name, "en"));

  for (const entry of sortedEntries) {
    if (entry.name === "README.md" || entry.name === ".gitkeep" || !entry.name.endsWith(".md")) {
      continue;
    }
    if (entry.name.includes("\n") || entry.name.includes("\r")) {
      throw new Error(`Release-note fragment has an unsafe file name: ${JSON.stringify(entry.name)}`);
    }
    if (entry.isDirectory()) {
      throw new Error(`Nested release-note directories are not supported: ${entry.name}`);
    }
    if (entry.isSymbolicLink() || !entry.isFile()) {
      throw new Error(`Release-note fragment must be a regular file: ${entry.name}`);
    }

    const filePath = path.join(directory, entry.name);
    const rawContent = await readFile(filePath);
    const fragment = parseReleaseNoteFragment(rawContent.toString("utf8"), entry.name);
    const duplicateKey = fragment.text.toLocaleLowerCase("en-US");
    const existing = descriptions.get(duplicateKey);
    if (existing) {
      throw new Error(`Duplicate release-note description in ${existing} and ${entry.name}: ${fragment.text}`);
    }
    descriptions.set(duplicateKey, entry.name);
    fragments.push(fragment);
    manifest.push({ fileName: entry.name, sha256: digest(rawContent) });
  }

  return { fragments, manifest };
}

function sortedFragments(fragments) {
  const copy = fragments.map((fragment) => ({ ...fragment }));
  for (const fragment of copy) assertSupportedFragment(fragment);
  return copy.toSorted((left, right) => left.source.localeCompare(right.source, "en"));
}

function categorizedSections(fragments) {
  const normalized = sortedFragments(fragments);
  const sections = [];
  for (const [type, title] of TYPE_DEFINITIONS) {
    const entries = normalized.filter((fragment) => fragment.type === type);
    if (entries.length === 0) continue;
    sections.push(`### ${title}\n\n${entries.map((fragment) => `- ${fragment.text}`).join("\n")}`);
  }
  return sections.join("\n\n");
}

function meaningfulManualLines(content) {
  return normalizeNewlines(content)
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => !line.startsWith("#"))
    .filter((line) => !/^自\s+\S+\s+以来的变更[：:]?$/.test(line))
    .filter((line) => !BUILD_DETAIL_PATTERN.test(line))
    .filter((line) => !/^\[.*\.\.\..*\]\(https:\/\/github\.com\/.*\/compare\//.test(line))
    .map((line) => line.replace(/^[-*]\s*/, "").trim());
}

export function validateManualReleaseNotes(content, source = "<notes-file>") {
  const normalized = normalizeNewlines(content).trimEnd();
  const lines = normalized.split("\n");
  const updateIndex = lines.findIndex((line) => /^##\s+更新内容\s*$/.test(line.trim()));
  let validationContent = normalized;
  if (updateIndex !== -1) {
    const updateLines = [];
    for (let index = updateIndex + 1; index < lines.length; index += 1) {
      if (/^##\s+/.test(lines[index].trim())) break;
      updateLines.push(lines[index]);
    }
    validationContent = updateLines.join("\n");
  }
  const meaningful = meaningfulManualLines(validationContent).filter(isMeaningfulText);
  if (!normalized.trim() || meaningful.length === 0) {
    throw new Error(`Manual release notes ${source} must contain meaningful update content.`);
  }
  return normalized;
}

function assertReleaseContext({ version, tag, repository, assets }) {
  if (!/^\d+\.\d+\.\d+$/.test(version ?? "")) {
    throw new Error(`Invalid release version: ${version ?? "<missing>"}`);
  }
  if (!tag) throw new Error("Release tag is required.");
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository ?? "")) {
    throw new Error(`Invalid GitHub repository: ${repository ?? "<missing>"}`);
  }
  for (const key of ["zip", "dmg", "feed"]) {
    if (!assets?.[key]?.name || !assets?.[key]?.sha256) {
      throw new Error(`Release asset metadata is incomplete for ${key}.`);
    }
  }
}

export function buildReleaseNotes({
  fragments = [],
  manualNotes,
  allowEmpty = false,
  version,
  tag,
  previousTag,
  repository,
  assets,
}) {
  assertReleaseContext({ version, tag, repository, assets });
  const normalizedFragments = sortedFragments(fragments);

  if (manualNotes !== undefined && manualNotes !== null) {
    return `${validateManualReleaseNotes(manualNotes)}\n`;
  }

  if (normalizedFragments.length === 0 && !allowEmpty) {
    throw new Error("No release-note fragments found. Add one or pass --allow-empty-notes explicitly.");
  }

  const updateContent = normalizedFragments.length > 0
    ? categorizedSections(normalizedFragments)
    : "- 本次发布仅重新打包，不包含功能变更。";
  const parts = ["## 更新内容", updateContent];

  if (previousTag) {
    const base = encodeURIComponent(previousTag);
    const head = encodeURIComponent(tag);
    parts.push(
      "## 完整变更",
      `[${previousTag}...${tag}](https://github.com/${repository}/compare/${base}...${head})`,
    );
  }

  parts.push(
    "## 构建信息",
    [
      `- App 版本：${version}`,
      `- ZIP：${assets.zip.name}`,
      `- ZIP SHA-256：${assets.zip.sha256}`,
      `- DMG：${assets.dmg.name}`,
      `- DMG SHA-256：${assets.dmg.sha256}`,
      `- 更新索引：${assets.feed.name}`,
      `- 更新索引 SHA-256：${assets.feed.sha256}`,
    ].join("\n"),
  );

  return `${parts.join("\n\n")}\n`;
}

function manualUpdateSection(content) {
  const normalized = validateManualReleaseNotes(content);
  const lines = normalized.split("\n");
  const updateIndex = lines.findIndex((line) => /^##\s+更新内容\s*$/.test(line.trim()));
  if (updateIndex === -1) {
    return meaningfulManualLines(normalized).map((line) => `- ${line}`).join("\n");
  }
  const section = [];
  for (let index = updateIndex + 1; index < lines.length; index += 1) {
    if (/^##\s+/.test(lines[index].trim())) break;
    section.push(lines[index]);
  }
  return section.join("\n").trim();
}

export function buildChangelogEntry({
  version,
  date,
  fragments = [],
  manualNotes,
  allowEmpty = false,
}) {
  if (!/^\d+\.\d+\.\d+$/.test(version ?? "")) {
    throw new Error(`Invalid release version: ${version ?? "<missing>"}`);
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date ?? "")) {
    throw new Error(`Invalid release date: ${date ?? "<missing>"}`);
  }

  const normalizedFragments = sortedFragments(fragments);
  let content;
  if (normalizedFragments.length > 0) {
    content = categorizedSections(normalizedFragments);
  } else if (manualNotes !== undefined && manualNotes !== null) {
    content = manualUpdateSection(manualNotes);
  } else if (allowEmpty) {
    content = "- 本次发布仅重新打包，不包含功能变更。";
  } else {
    throw new Error("No release-note fragments found for the changelog entry.");
  }

  return `## v${version} - ${date}\n\n${content.trim()}\n`;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function prependChangelogEntry(changelog, entry, version) {
  const normalized = normalizeNewlines(changelog);
  const heading = normalized.match(/^# Changelog[ \t]*(?:\n|$)/);
  if (!heading) throw new Error("CHANGELOG.md must start with # Changelog.");
  const duplicate = new RegExp(`^## v${escapeRegExp(version)}(?:\\s|$)`, "m");
  if (duplicate.test(normalized)) {
    throw new Error(`CHANGELOG.md already contains v${version}.`);
  }

  const remainder = normalized.slice(heading[0].length).replace(/^\n+/, "");
  const prefix = `# Changelog\n\n${normalizeNewlines(entry).trim()}\n`;
  return remainder ? `${prefix}\n${remainder.trimEnd()}\n` : prefix;
}

async function atomicWrite(filePath, content) {
  const temporaryPath = path.join(
    path.dirname(filePath),
    `.${path.basename(filePath)}.${process.pid}.${randomUUID()}.tmp`,
  );
  try {
    await writeFile(temporaryPath, content);
    await rename(temporaryPath, filePath);
  } catch (error) {
    await rm(temporaryPath, { force: true });
    throw error;
  }
}

function assertManifestMatches(expected, actual) {
  const expectedSorted = [...expected].toSorted((left, right) => left.fileName.localeCompare(right.fileName, "en"));
  const actualSorted = [...actual].toSorted((left, right) => left.fileName.localeCompare(right.fileName, "en"));
  if (JSON.stringify(expectedSorted) !== JSON.stringify(actualSorted)) {
    throw new Error("Release-note fragments changed after generation; regenerate the release metadata.");
  }
}

export async function applyReleaseMetadata({
  changelogPath,
  fragmentsDirectory,
  entry,
  version,
  manifest,
}) {
  const loaded = await loadReleaseNoteFragments(fragmentsDirectory);
  assertManifestMatches(manifest, loaded.manifest);

  const originalChangelog = await readFile(changelogPath, "utf8");
  const updatedChangelog = prependChangelogEntry(originalChangelog, entry, version);
  const fragmentContents = new Map();
  for (const item of manifest) {
    const fragmentPath = path.join(fragmentsDirectory, item.fileName);
    fragmentContents.set(fragmentPath, await readFile(fragmentPath));
  }

  await atomicWrite(changelogPath, updatedChangelog);
  const deleted = [];
  try {
    for (const item of manifest) {
      const fragmentPath = path.join(fragmentsDirectory, item.fileName);
      await unlink(fragmentPath);
      deleted.push(fragmentPath);
    }
  } catch (error) {
    await atomicWrite(changelogPath, originalChangelog);
    for (const fragmentPath of deleted) {
      await atomicWrite(fragmentPath, fragmentContents.get(fragmentPath));
    }
    throw error;
  }
}
