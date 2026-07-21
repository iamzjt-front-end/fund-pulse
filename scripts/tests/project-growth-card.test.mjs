import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  aggregateStarHistory,
  collectPaginated,
  downsampleHistory,
  escapeXML,
  generateGrowthCards,
  renderGrowthCard,
} from "../lib/project-growth-card.mjs";

const DAY = 24 * 60 * 60 * 1_000;
const NOW = new Date("2026-07-21T12:00:00.000Z");

async function withTempDirectory(run) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "fund-pulse-growth-card-test-"));
  try {
    return await run(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function star(starredAt) {
  return { starred_at: starredAt, user: { login: `reader-${starredAt}` } };
}

function cardData(overrides = {}) {
  return {
    repository: "iamzjt-front-end/fund-pulse",
    description: "轻量、原生、隐私优先的 macOS 基金收益助手",
    stars: 8,
    stars7d: 5,
    stars30d: 8,
    forks: 1,
    contributors: 2,
    history: [
      { date: "2026-06-22", value: 1 },
      { date: "2026-06-29", value: 3 },
      { date: "2026-07-21", value: 8 },
    ],
    ...overrides,
  };
}

test("aggregates zero stars into a stable zero-value timeline", () => {
  assert.deepEqual(aggregateStarHistory([], NOW), [
    { date: "2026-07-21", value: 0 },
  ]);
});

test("aggregates a single star and keeps the current cumulative value", () => {
  assert.deepEqual(aggregateStarHistory([star("2026-07-20T18:30:00Z")], NOW), [
    { date: "2026-07-20", value: 1 },
    { date: "2026-07-21", value: 1 },
  ]);
});

test("groups stars from the same UTC day and sorts unordered input", () => {
  const history = aggregateStarHistory([
    star("2026-07-21T08:00:00Z"),
    star("2026-06-29T20:00:00Z"),
    star("2026-06-29T01:00:00Z"),
    star("2026-06-22T11:00:00Z"),
  ], NOW);

  assert.deepEqual(history, [
    { date: "2026-06-22", value: 1 },
    { date: "2026-06-29", value: 3 },
    { date: "2026-07-21", value: 4 },
  ]);
});

test("keeps cross-month cumulative totals and derives rolling windows", () => {
  const history = aggregateStarHistory([
    star("2026-05-31T23:59:59Z"),
    star("2026-06-22T00:00:00Z"),
    star("2026-07-15T00:00:00Z"),
    star("2026-07-21T00:00:00Z"),
  ], NOW);

  assert.equal(history.at(-1).value, 4);
  assert.equal(history.find((point) => point.date === "2026-06-22").value, 2);
});

test("downsamples long histories without losing endpoints or monotonicity", () => {
  const history = Array.from({ length: 500 }, (_, index) => ({
    date: new Date(Date.UTC(2025, 0, 1) + index * DAY).toISOString().slice(0, 10),
    value: index,
  }));

  const compressed = downsampleHistory(history, 120);

  assert.ok(compressed.length <= 120);
  assert.deepEqual(compressed[0], history[0]);
  assert.deepEqual(compressed.at(-1), history.at(-1));
  for (let index = 1; index < compressed.length; index += 1) {
    assert.ok(compressed[index].value >= compressed[index - 1].value);
  }
});

test("follows GitHub pagination until a short page is returned", async () => {
  const requestedPages = [];
  const fetchImpl = async (url) => {
    const page = Number(new URL(url).searchParams.get("page"));
    requestedPages.push(page);
    const length = page === 1 ? 100 : 3;
    return new Response(JSON.stringify(Array.from({ length }, (_, index) => ({ page, index }))), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  const items = await collectPaginated("https://api.github.com/example", {
    fetchImpl,
    headers: { accept: "application/json" },
  });

  assert.equal(items.length, 103);
  assert.deepEqual(requestedPages, [1, 2]);
});

test("renders valid standalone light and dark SVGs with escaped external text", () => {
  const unsafe = cardData({
    repository: "owner/<fund&pulse>",
    description: "收益 < 预期 & 隐私 \"优先\" '可靠'",
  });
  const light = renderGrowthCard(unsafe, { theme: "light", iconDataURI: "data:image/png;base64,AA==" });
  const dark = renderGrowthCard(unsafe, { theme: "dark", iconDataURI: "data:image/png;base64,AA==" });

  for (const svg of [light, dark]) {
    assert.match(svg, /^<svg xmlns="http:\/\/www\.w3\.org\/2000\/svg"/);
    assert.match(svg, /owner\/&lt;fund&amp;pulse&gt;/);
    assert.match(svg, /收益 &lt; 预期 &amp; 隐私 &quot;优先&quot; &apos;可靠&apos;/);
    assert.match(svg, />8<\/text>/);
    assert.match(svg, /data:image\/png;base64,AA==/);
    assert.doesNotMatch(svg, /<script|@import|<link|href="https?:\/\//i);
  }
  assert.notEqual(light, dark);
  assert.match(light, /data-theme="light"/);
  assert.match(dark, /data-theme="dark"/);
});

test("escapes all XML metacharacters", () => {
  assert.equal(escapeXML(`<tag attr="x">Tom & 'Jerry'</tag>`), "&lt;tag attr=&quot;x&quot;&gt;Tom &amp; &apos;Jerry&apos;&lt;/tag&gt;");
});

test("API failures preserve both previously valid cards", async () => {
  await withTempDirectory(async (directory) => {
    const lightPath = path.join(directory, "star-growth-light.svg");
    const darkPath = path.join(directory, "star-growth-dark.svg");
    await writeFile(lightPath, "previous-light");
    await writeFile(darkPath, "previous-dark");

    const fetchImpl = async () => new Response("rate limited", { status: 403 });

    await assert.rejects(
      () => generateGrowthCards({
        repository: "iamzjt-front-end/fund-pulse",
        outputDirectory: directory,
        token: "super-secret-token",
        fetchImpl,
        now: NOW,
        iconDataURI: "data:image/png;base64,AA==",
      }),
      /GitHub API request failed \(403\)/,
    );

    assert.equal(await readFile(lightPath, "utf8"), "previous-light");
    assert.equal(await readFile(darkPath, "utf8"), "previous-dark");
  });
});

test("generates both themes with rolling star counts, forks, and unique human contributors", async () => {
  await withTempDirectory(async (directory) => {
    const fetchImpl = async (url) => {
      if (url.endsWith("/repos/iamzjt-front-end/fund-pulse")) {
        return new Response(JSON.stringify({
          stargazers_count: 3,
          forks_count: 4,
          description: "Fund & Pulse",
        }), { status: 200, headers: { "content-type": "application/json" } });
      }
      if (url.includes("/stargazers?")) {
        return new Response(JSON.stringify([
          star("2026-06-01T00:00:00Z"),
          star("2026-07-14T13:00:00Z"),
          star("2026-07-20T13:00:00Z"),
        ]), { status: 200, headers: { "content-type": "application/json" } });
      }
      if (url.includes("/contributors?")) {
        return new Response(JSON.stringify([
          { login: "alice", type: "User" },
          { login: "alice", type: "User" },
          { login: "dependabot[bot]", type: "Bot" },
          { name: "anonymous" },
        ]), { status: 200, headers: { "content-type": "application/json" } });
      }
      return new Response("not found", { status: 404 });
    };

    const result = await generateGrowthCards({
      repository: "iamzjt-front-end/fund-pulse",
      outputDirectory: directory,
      token: "super-secret-token",
      fetchImpl,
      now: NOW,
      iconDataURI: "data:image/png;base64,AA==",
    });

    assert.deepEqual({
      stars: result.data.stars,
      stars7d: result.data.stars7d,
      stars30d: result.data.stars30d,
      forks: result.data.forks,
      contributors: result.data.contributors,
    }, {
      stars: 3,
      stars7d: 2,
      stars30d: 2,
      forks: 4,
      contributors: 2,
    });

    const light = await readFile(path.join(directory, "star-growth-light.svg"), "utf8");
    const dark = await readFile(path.join(directory, "star-growth-dark.svg"), "utf8");
    assert.match(light, /data-theme="light"/);
    assert.match(dark, /data-theme="dark"/);
    assert.match(light, /Fund &amp; Pulse/);
    assert.doesNotMatch(light + dark, /super-secret-token/);
  });
});

test("rejects a star-list total that disagrees with repository metadata without writing", async () => {
  await withTempDirectory(async (directory) => {
    const responses = [
      { stargazers_count: 2, forks_count: 0, description: "Fund Pulse" },
      [star("2026-07-21T00:00:00Z")],
      [],
      [],
    ];
    const fetchImpl = async () => new Response(JSON.stringify(responses.shift()), {
      status: 200,
      headers: { "content-type": "application/json" },
    });

    await assert.rejects(
      () => generateGrowthCards({
        repository: "iamzjt-front-end/fund-pulse",
        outputDirectory: directory,
        token: "token",
        fetchImpl,
        now: NOW,
        iconDataURI: "data:image/png;base64,AA==",
      }),
      /star count mismatch/i,
    );
  });
});
