function stripTapPrefix(line) {
  for (const prefix of ["#", "ℹ"]) {
    if (line.startsWith(`${prefix} `)) return line.slice(prefix.length + 1);
    if (line.startsWith(prefix)) return line.slice(prefix.length);
  }
  return line;
}

function normalizeCoveragePath(filePath) {
  return filePath.replaceAll("\\", "/").replace(/^\.\//, "");
}

export function parseCoverageReport(output) {
  const results = new Map();
  const ancestors = [];

  for (const rawLine of output.split(/\r?\n/)) {
    const line = stripTapPrefix(rawLine);
    const match = line.match(
      /^(\s*)([^|]+?)\s*\|\s*([\d.]*)\s*\|\s*([\d.]*)\s*\|\s*([\d.]*)\s*(?:\||$)/,
    );
    if (!match) continue;

    const indent = match[1].replaceAll("\t", "    ").length;
    const name = match[2].trim();
    const values = match.slice(3, 6);
    const isFileResult = values.every((value) => value !== "");

    if (!isFileResult) {
      if (name.toLowerCase() === "file") continue;
      ancestors.length = indent;
      ancestors[indent] = name;
      continue;
    }

    const filePath = name.includes("/") || name.includes("\\")
      ? normalizeCoveragePath(name)
      : normalizeCoveragePath([...ancestors.slice(0, indent).filter(Boolean), name].join("/"));

    results.set(filePath, {
      lines: Number(values[0]),
      branches: Number(values[1]),
      functions: Number(values[2]),
    });
  }

  return results;
}
