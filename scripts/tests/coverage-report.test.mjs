import assert from "node:assert/strict";
import test from "node:test";

import { parseCoverageReport } from "../lib/coverage-report.mjs";

test("parses flat coverage paths emitted by Node 22", () => {
  const report = `# file                                  | line % | branch % | funcs % | uncovered lines
# scripts/lib/release-notes.mjs         |  98.71 |    95.86 |   94.74 | 342-344
# scripts/release-notes.mjs             |  98.64 |    83.33 |  100.00 | 110-112
`;

  const results = parseCoverageReport(report);

  assert.deepEqual(results.get("scripts/lib/release-notes.mjs"), {
    lines: 98.71,
    branches: 95.86,
    functions: 94.74,
  });
  assert.deepEqual(results.get("scripts/release-notes.mjs"), {
    lines: 98.64,
    branches: 83.33,
    functions: 100,
  });
});

test("reconstructs hierarchical coverage paths emitted by Node 24", () => {
  const report = `ℹ file                | line % | branch % | funcs % | uncovered lines
ℹ scripts             |        |          |         |
ℹ  lib                |        |          |         |
ℹ   release-notes.mjs |  98.71 |    95.86 |   94.74 | 342-344
ℹ  release-notes.mjs  |  98.64 |    83.33 |  100.00 | 110-112
ℹ all files           |  98.69 |    94.48 |   95.65 |
`;

  const results = parseCoverageReport(report);

  assert.deepEqual(results.get("scripts/lib/release-notes.mjs"), {
    lines: 98.71,
    branches: 95.86,
    functions: 94.74,
  });
  assert.deepEqual(results.get("scripts/release-notes.mjs"), {
    lines: 98.64,
    branches: 83.33,
    functions: 100,
  });
});
