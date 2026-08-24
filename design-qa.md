# Design QA — 收益日历合并页

## Evidence

- Source visual truth: `/Users/iamzjt/.codex/generated_images/01a031b2-c821-77f0-98a0-cb08f90ec243/exec-d534b3c7-b171-4d01-b579-a148b51f8ce2.png`
- Rendered implementation: `/tmp/fund-pulse-performance-calendar-three-months.png`
- Actual main-panel entry proof: `/tmp/fund-pulse-main-entry-calendar-three-months-final.png`
- Chart hover interaction proof: `/tmp/fund-pulse-performance-chart-hover.png`
- Stable chart hover proof after 12 rapid sweeps: `/tmp/fund-pulse-performance-chart-hover-stable.png`
- Non-overlapping chart readout proof after 12 rapid sweeps: `/tmp/fund-pulse-performance-chart-readout-no-overlap.png`
- Rapid-sweep recording: `/tmp/fund-pulse-hover-rapid-sweep-v2.mov`
- Rapid-sweep frame contact sheet: `/tmp/fund-pulse-hover-rapid-sweep-contact-sheet-v2.png`
- Full-view comparison: `/tmp/fund-pulse-design-comparison-three-months.png`
- Focused summary comparison: `/tmp/fund-pulse-summary-comparison.png`
- Viewport: native macOS panel, 430 × 660 pt logical content size, light appearance
- Source pixels: 1026 × 1533 px
- Implementation pixels: 952 × 1412 px, native window capture including the window edge/shadow
- Density normalization: the source was proportionally scaled to 945 × 1412 px and placed beside the native 952 × 1412 px implementation with a 24 px comparison gutter. This avoids filing differences caused only by image density or outer canvas size. CSS size and browser device scale factor are not applicable to this native SwiftUI surface.
- State: real portfolio data; `收益日历` selected; `近3月` selected by default; August 2026 calendar; light theme. The user's follow-up instruction intentionally overrides the static mock's `近1月` selection.

## Findings

- No actionable P0, P1, or P2 mismatch remains.
- Fonts and typography: the implementation uses the product's native system typography and existing weight hierarchy. The hero amount, metric labels, metric values, controls, and calendar copy remain legible without wrapping or truncation.
- Spacing and layout rhythm: the two-tab navigation, unified summary, source strip, compact curve, and calendar follow the source hierarchy. Card radii, insets, dividers, and vertical gaps are consistent with the existing panel design system.
- Colors and visual tokens: the implementation reuses `PanelDesign` surfaces and borders plus the app's semantic red-for-gain and green-for-loss colors. Selected controls and neutral secondary text preserve the source contrast hierarchy.
- Image quality and asset fidelity: the target contains no photographic or custom raster assets. The implementation reuses the app's existing header artwork and SF Symbols for source and navigation icons; they remain sharp at native scale.
- Copy and content: the two tabs are exactly `收益日历` and `持仓收益排行`; the curve is labeled `累计收益走势`; ranges are `近1月 / 近3月 / 近6月 / 近1年 / 全部`, with `近3月` as the requested default. Live total amount and latest synchronization date intentionally differ from the static mock because the implementation renders current portfolio data.
- Interaction and accessibility: both tabs, every range segment, previous/next month navigation, and the calendar's amount-plus-return-rate accessibility labels were exercised in the running app. The real main-panel `持仓收益` card was pressed through Accessibility and verified to open `收益日历 · 近3月`; moving the pointer across the curve was verified to show the nearest record's date, daily income, and return rate with a crosshair and marker, and moving out clears the selection. A second runtime pass performed 16 high-speed left/right sweeps and sampled 24 video frames; after the pointer entered the chart, the tooltip remained continuously present on its fixed vertical track while its date and values updated. The disabled next-month state was also verified for the latest month.

## Comparison History

### Pass 1 — blocked

- Earlier implementation: `/tmp/fund-pulse-performance-calendar-implementation.png`
- Comparison: `/tmp/fund-pulse-design-comparison-initial.png`
- [P2] The 150 pt curve and redundant gain/loss legend made the curve dominate the page and pushed the calendar too far below the fold; the broader `近3月` state made that excess density more apparent.
- Fixes: reduced the chart to 105 pt and removed the redundant legend while preserving date endpoints. The range was temporarily set to `近1月` to align Pass 2 with the static source state.

### Pass 2 — passed

- Revised implementation: `/tmp/fund-pulse-performance-calendar-window.png`
- Full comparison: `/tmp/fund-pulse-design-comparison.png`
- Focused summary comparison: `/tmp/fund-pulse-summary-comparison.png`
- Post-fix evidence shows the curve as a compact supporting region and restores the calendar as the page's primary task. No actionable P0/P1/P2 finding remains.

### Pass 3 — passed, user-directed default state

- Revised implementation: `/tmp/fund-pulse-performance-calendar-three-months.png`
- Full comparison: `/tmp/fund-pulse-design-comparison-three-months.png`
- The requested `近3月` default is visibly selected while `收益日历` remains the first and selected tab. The compact 105 pt curve continues to preserve the intended hierarchy, so restoring the broader default range introduces no P0/P1/P2 issue.

### Pass 4 — passed, production entry-state correction

- Actual main-panel entry proof: `/tmp/fund-pulse-main-entry-calendar-three-months-final.png`
- The legacy main-panel callbacks previously forced `.ranking`, overriding the view's default state. Both callbacks now reset through one shared default-entry policy, and the real `持仓收益` click path visibly opens `收益日历 · 近3月`.

### Pass 5 — passed, chart hover inspection

- Hover interaction proof: `/tmp/fund-pulse-performance-chart-hover.png`
- The compact tooltip stays within the 386 × 105 pt chart region, preserves the curve's primary point marker, and displays `日期 / 收益 / 收益率` without truncation. Semantic gain/loss colors and privacy-mode amount hiding remain consistent with the rest of the page.

### Pass 6 — passed, rapid-hover stability

- Stable endpoint proof: `/tmp/fund-pulse-performance-chart-hover-stable.png`
- Motion evidence: `/tmp/fund-pulse-hover-rapid-sweep-v2.mov`
- Sampled frames: `/tmp/fund-pulse-hover-rapid-sweep-contact-sheet-v2.png`
- The pointer completed 16 rapid left/right sweeps through the chart. Once inside the chart, every sampled frame retains one tooltip; the marker, crosshair, and tooltip no longer steal hit testing from the stable tracking surface. The tooltip keeps one vertical anchor and only its horizontal position and content change, eliminating the prior hide/show and above/below flicker.

### Pass 7 — passed, unobstructed chart readout

- Runtime proof: `/tmp/fund-pulse-performance-chart-readout-no-overlap.png`
- Date, daily income, and return rate now render in a dedicated 26 pt readout strip above the plot. The plot preserves its previous usable height, while the full red/green path, zero line, crosshair, and selected marker remain visible below the readout with no overlap. Twelve rapid left/right sweeps confirmed the non-hit-testing readout remains stable.

## Follow-up Polish

- [P3] The full six-row month grid requires vertical scrolling in the native 430 × 660 pt panel. This is accepted because the 50 pt day cells preserve readable date, amount, and return-rate lines instead of compressing financial data below a comfortable size.
- [P3] The static mock's curve shape and color transitions are illustrative. The native implementation correctly reflects the selected range and current persisted history, so the live curve can be entirely green when every visible cumulative point is below zero.

## Implementation Checklist

- [x] Make `收益日历` the first and default tab.
- [x] Make `近3月` the default cumulative-trend range.
- [x] Remove the standalone curve tab.
- [x] Embed the cumulative-income curve in the calendar page.
- [x] Replace the three detached summary cards with one JD-style asset summary.
- [x] Preserve daily amount and return-rate display in calendar cells.
- [x] Keep the chart tooltip stable during rapid pointer movement.
- [x] Keep hover details outside the plot so the trend line is never covered.
- [x] Verify core interactions, accessibility text, tests, and native rendering.

final result: passed
