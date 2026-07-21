import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DAY_IN_MILLISECONDS = 24 * 60 * 60 * 1_000;
const PAGE_SIZE = 100;
const DEFAULT_ICON_PATH = fileURLToPath(new URL("../../build/icons/128x128.png", import.meta.url));

const THEMES = {
  light: {
    background: "#ffffff",
    panel: "#f7f9fc",
    border: "#e6eaf0",
    text: "#18202b",
    muted: "#6d7785",
    grid: "#dce2ea",
    positive: "#e34a59",
    positiveSoft: "#fff0f2",
    negative: "#16a56a",
    accent: "#ff5968",
  },
  dark: {
    background: "#11151c",
    panel: "#181e27",
    border: "#2b3441",
    text: "#f4f7fb",
    muted: "#9aa5b3",
    grid: "#303947",
    positive: "#ff6a78",
    positiveSoft: "#342027",
    negative: "#34c98a",
    accent: "#ff6a78",
  },
};

export function escapeXML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function utcDate(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid date received from GitHub: ${String(value)}`);
  }
  return date.toISOString().slice(0, 10);
}

export function aggregateStarHistory(stargazers, now = new Date()) {
  const currentDate = utcDate(now);
  if (stargazers.length === 0) {
    return [{ date: currentDate, value: 0 }];
  }

  const starsPerDay = new Map();
  for (const entry of stargazers) {
    if (!entry || typeof entry.starred_at !== "string") {
      throw new Error("GitHub stargazer data is missing starred_at; the star media type may not be enabled");
    }
    const date = utcDate(entry.starred_at);
    starsPerDay.set(date, (starsPerDay.get(date) ?? 0) + 1);
  }

  let cumulative = 0;
  const history = [...starsPerDay.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([date, count]) => {
      cumulative += count;
      return { date, value: cumulative };
    });

  if (history.at(-1).date < currentDate) {
    history.push({ date: currentDate, value: cumulative });
  }
  return history;
}

export function downsampleHistory(history, maxPoints = 180) {
  if (!Number.isInteger(maxPoints) || maxPoints < 2) {
    throw new Error("maxPoints must be an integer greater than or equal to 2");
  }
  if (history.length <= maxPoints) {
    return history.map((point) => ({ ...point }));
  }

  const result = [];
  for (let index = 0; index < maxPoints; index += 1) {
    const sourceIndex = Math.round((index * (history.length - 1)) / (maxPoints - 1));
    const point = history[sourceIndex];
    if (result.at(-1)?.date !== point.date) {
      result.push({ ...point });
    }
  }
  return result;
}

async function requestJSON(url, { fetchImpl, headers }) {
  let response;
  try {
    response = await fetchImpl(url, { headers });
  } catch (error) {
    throw new Error(`GitHub API request failed: ${error instanceof Error ? error.message : String(error)}`);
  }

  if (!response.ok) {
    throw new Error(`GitHub API request failed (${response.status}) for ${new URL(url).pathname}`);
  }

  try {
    return await response.json();
  } catch {
    throw new Error(`GitHub API returned invalid JSON for ${new URL(url).pathname}`);
  }
}

export async function collectPaginated(baseURL, { fetchImpl = globalThis.fetch, headers = {} } = {}) {
  if (typeof fetchImpl !== "function") {
    throw new Error("A fetch implementation is required");
  }

  const items = [];
  for (let page = 1; ; page += 1) {
    const url = new URL(baseURL);
    url.searchParams.set("per_page", String(PAGE_SIZE));
    url.searchParams.set("page", String(page));
    const payload = await requestJSON(url.toString(), { fetchImpl, headers });
    if (!Array.isArray(payload)) {
      throw new Error(`GitHub API returned a non-array page for ${url.pathname}`);
    }
    items.push(...payload);
    if (payload.length < PAGE_SIZE) {
      return items;
    }
  }
}

function countRecentStars(stargazers, now, days) {
  const cutoff = now.getTime() - days * DAY_IN_MILLISECONDS;
  return stargazers.filter((entry) => {
    const timestamp = new Date(entry.starred_at).getTime();
    return Number.isFinite(timestamp) && timestamp >= cutoff && timestamp <= now.getTime();
  }).length;
}

function countContributors(contributors) {
  const identities = new Set();
  for (const contributor of contributors) {
    const identity = contributor?.login ?? contributor?.name ?? contributor?.email;
    const isBot = contributor?.type === "Bot" || String(identity ?? "").endsWith("[bot]");
    if (identity && !isBot) {
      identities.add(String(identity));
    }
  }
  return identities.size;
}

function numberMetric(value) {
  return new Intl.NumberFormat("en-US").format(value);
}

function recentMetric(value) {
  return value > 0 ? `+${numberMetric(value)}` : "0";
}

function chartGeometry(history, stars) {
  const points = downsampleHistory(history);
  const left = 60;
  const top = 208;
  const width = 980;
  const height = 132;
  const bottom = top + height;
  const start = Date.parse(`${points[0].date}T00:00:00Z`);
  const end = Date.parse(`${points.at(-1).date}T00:00:00Z`);
  const duration = Math.max(end - start, 1);
  const maximum = Math.max(stars, 1);
  const coordinates = points.map((point, index) => ({
    x: points.length === 1 ? left + width : left + ((Date.parse(`${point.date}T00:00:00Z`) - start) / duration) * width,
    y: bottom - (point.value / maximum) * height,
    index,
  }));
  const line = coordinates.map((point, index) => `${index === 0 ? "M" : "L"}${point.x.toFixed(2)},${point.y.toFixed(2)}`).join(" ");
  const area = `M${coordinates[0].x.toFixed(2)},${bottom} ${line.replace(/^M/, "L")} L${coordinates.at(-1).x.toFixed(2)},${bottom} Z`;
  return { points, coordinates, line, area, left, top, width, height, bottom };
}

function metricCell({ x, label, value, color, palette }) {
  return [
    `<text x="${x}" y="72" fill="${color ?? palette.text}" font-size="26" font-weight="700">${escapeXML(value)}</text>`,
    `<text x="${x}" y="94" fill="${palette.muted}" font-size="12" font-weight="500">${escapeXML(label)}</text>`,
  ].join("\n  ");
}

export function renderGrowthCard(data, { theme, iconDataURI }) {
  const palette = THEMES[theme];
  if (!palette) {
    throw new Error(`Unsupported growth-card theme: ${theme}`);
  }
  if (!iconDataURI?.startsWith("data:image/")) {
    throw new Error("A data URI for the Fund Pulse icon is required");
  }

  const history = data.history.length > 0 ? data.history : [{ date: utcDate(new Date()), value: 0 }];
  const chart = chartGeometry(history, data.stars);
  const firstDate = chart.points[0].date;
  const lastDate = chart.points.at(-1).date;
  const metrics = [
    { x: 535, label: "Stars", value: numberMetric(data.stars) },
    { x: 635, label: "最近 7 天", value: recentMetric(data.stars7d), color: palette.positive },
    { x: 755, label: "最近 30 天", value: recentMetric(data.stars30d), color: palette.positive },
    { x: 885, label: "Forks", value: numberMetric(data.forks) },
    { x: 975, label: "Contributors", value: numberMetric(data.contributors) },
  ];

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="410" viewBox="0 0 1100 410" role="img" aria-labelledby="title description" data-theme="${theme}">
  <title id="title">Fund Pulse 项目成长卡</title>
  <desc id="description">${escapeXML(`${data.repository} 当前 ${data.stars} Stars，展示从首个 Star 到现在的累计增长趋势`)}</desc>
  <defs>
    <linearGradient id="area-${theme}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${palette.positive}" stop-opacity="0.30"/>
      <stop offset="1" stop-color="${palette.positive}" stop-opacity="0.02"/>
    </linearGradient>
    <linearGradient id="brand-${theme}" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${palette.positive}"/>
      <stop offset="1" stop-color="${palette.negative}"/>
    </linearGradient>
    <clipPath id="icon-${theme}"><rect x="40" y="34" width="74" height="74" rx="17"/></clipPath>
  </defs>
  <rect x="1" y="1" width="1098" height="408" rx="22" fill="${palette.background}" stroke="${palette.border}" stroke-width="2"/>
  <rect x="24" y="20" width="1052" height="108" rx="18" fill="${palette.panel}"/>
  <image x="40" y="34" width="74" height="74" href="${escapeXML(iconDataURI)}" clip-path="url(#icon-${theme})"/>
  <text x="132" y="63" fill="${palette.text}" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="24" font-weight="750">Fund Pulse</text>
  <text x="132" y="87" fill="${palette.muted}" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="14">${escapeXML(data.repository)}</text>
  <text x="132" y="108" fill="${palette.muted}" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="12">${escapeXML(data.description || "原生 macOS 基金收益助手")}</text>
  <g font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">
  ${metrics.map((metric) => metricCell({ ...metric, palette })).join("\n  ")}
  </g>
  <text x="60" y="167" fill="${palette.text}" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="18" font-weight="700">累计 Star 增长</text>
  <text x="1040" y="167" text-anchor="end" fill="${palette.muted}" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="12">从首个 Star 到现在</text>
  <line x1="60" y1="208" x2="1040" y2="208" stroke="${palette.grid}" stroke-width="1" stroke-dasharray="4 6"/>
  <line x1="60" y1="274" x2="1040" y2="274" stroke="${palette.grid}" stroke-width="1" stroke-dasharray="4 6"/>
  <line x1="60" y1="340" x2="1040" y2="340" stroke="${palette.grid}" stroke-width="1"/>
  <path d="${chart.area}" fill="url(#area-${theme})"/>
  <path d="${chart.line}" fill="none" stroke="url(#brand-${theme})" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="${chart.coordinates.at(-1).x.toFixed(2)}" cy="${chart.coordinates.at(-1).y.toFixed(2)}" r="6" fill="${palette.background}" stroke="${palette.positive}" stroke-width="4"/>
  <text x="60" y="367" fill="${palette.muted}" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="12">${escapeXML(firstDate)}</text>
  <text x="1040" y="367" text-anchor="end" fill="${palette.muted}" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="12">${escapeXML(lastDate)}</text>
  <circle cx="60" cy="389" r="4" fill="${palette.positive}"/>
  <circle cx="72" cy="389" r="4" fill="${palette.negative}"/>
  <text x="84" y="393" fill="${palette.muted}" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="11">由仓库 GitHub 数据每日生成 · 无第三方统计服务</text>
</svg>
`;
}

async function loadIconDataURI(iconPath) {
  const icon = await readFile(iconPath);
  return `data:image/png;base64,${icon.toString("base64")}`;
}

export async function generateGrowthCards({
  repository,
  outputDirectory,
  token,
  fetchImpl = globalThis.fetch,
  now = new Date(),
  iconDataURI,
  iconPath = DEFAULT_ICON_PATH,
}) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository ?? "")) {
    throw new Error("--repo must use the owner/repository format");
  }
  if (!outputDirectory) {
    throw new Error("--output-dir is required");
  }
  if (!token) {
    throw new Error("GITHUB_TOKEN is required");
  }
  if (typeof fetchImpl !== "function") {
    throw new Error("A fetch implementation is required");
  }

  const requestHeaders = {
    accept: "application/vnd.github+json",
    authorization: `Bearer ${token}`,
    "user-agent": "fund-pulse-growth-card",
    "x-github-api-version": "2026-03-10",
  };
  const apiBase = `https://api.github.com/repos/${repository}`;

  const metadata = await requestJSON(apiBase, { fetchImpl, headers: requestHeaders });
  const stargazers = await collectPaginated(`${apiBase}/stargazers`, {
    fetchImpl,
    headers: { ...requestHeaders, accept: "application/vnd.github.star+json" },
  });
  const contributors = await collectPaginated(`${apiBase}/contributors?anon=1`, {
    fetchImpl,
    headers: requestHeaders,
  });

  if (!Number.isInteger(metadata.stargazers_count) || !Number.isInteger(metadata.forks_count)) {
    throw new Error("GitHub repository metadata is missing star or fork counts");
  }
  if (metadata.stargazers_count !== stargazers.length) {
    throw new Error(`GitHub star count mismatch: metadata=${metadata.stargazers_count}, history=${stargazers.length}`);
  }

  const effectiveNow = now instanceof Date ? now : new Date(now);
  const data = {
    repository,
    description: metadata.description ?? "原生 macOS 基金收益助手",
    stars: metadata.stargazers_count,
    stars7d: countRecentStars(stargazers, effectiveNow, 7),
    stars30d: countRecentStars(stargazers, effectiveNow, 30),
    forks: metadata.forks_count,
    contributors: countContributors(contributors),
    history: aggregateStarHistory(stargazers, effectiveNow),
  };

  const embeddedIcon = iconDataURI ?? await loadIconDataURI(iconPath);
  const lightSVG = renderGrowthCard(data, { theme: "light", iconDataURI: embeddedIcon });
  const darkSVG = renderGrowthCard(data, { theme: "dark", iconDataURI: embeddedIcon });

  await mkdir(outputDirectory, { recursive: true });
  const nonce = `${process.pid}-${Date.now()}`;
  const outputs = {
    light: path.join(outputDirectory, "star-growth-light.svg"),
    dark: path.join(outputDirectory, "star-growth-dark.svg"),
  };
  const temporary = {
    light: path.join(outputDirectory, `.star-growth-light.${nonce}.tmp`),
    dark: path.join(outputDirectory, `.star-growth-dark.${nonce}.tmp`),
  };

  try {
    await writeFile(temporary.light, lightSVG, { encoding: "utf8", mode: 0o644 });
    await writeFile(temporary.dark, darkSVG, { encoding: "utf8", mode: 0o644 });
    await rename(temporary.light, outputs.light);
    await rename(temporary.dark, outputs.dark);
  } finally {
    await Promise.all([
      rm(temporary.light, { force: true }),
      rm(temporary.dark, { force: true }),
    ]);
  }

  return { data, outputs };
}
