# Inventory Report Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a static, PDF-first inventory report frontend from `库存盘点表-20260430 copy.xls`.

**Architecture:** A Python script parses the `.xls` file and generates normalized report data. A static HTML/CSS/JavaScript frontend renders summary cards, brand/series board, attention list, filters, and a print-ready detail table from that generated data.

**Tech Stack:** Python 3, `xlrd`, standard-library `unittest`, static HTML, CSS, vanilla JavaScript.

---

## File Structure

- Create `requirements.txt`: documents the `xlrd` dependency used by the generator and tests.
- Create `scripts/generate_data.py`: owns Excel parsing, grouping/status rules, summary calculation, and JSON/JS data output.
- Create `tests/test_generate_data.py`: verifies grouping/status helpers and the current workbook statistics.
- Create `index.html`: static report shell with toolbar, summary, group board, attention panel, table, and empty/error states.
- Create `styles.css`: screen and A4 landscape print styles.
- Create `app.js`: renders the report, handles search/filter controls, and triggers browser print.
- Generate `public/data/inventory.json`: normalized report data.
- Generate `public/data/inventory-data.js`: assigns the same data to `window.INVENTORY_DATA` so `index.html` can also work from `file://`.

## Task 1: Data Generator And Tests

**Files:**
- Create: `requirements.txt`
- Create: `scripts/generate_data.py`
- Create: `tests/test_generate_data.py`

- [ ] **Step 1: Add dependency file**

Create `requirements.txt`:

```txt
xlrd>=2.0.1
```

- [ ] **Step 2: Write failing tests**

Create `tests/test_generate_data.py`:

```python
from pathlib import Path
import unittest

from scripts.generate_data import (
    DEFAULT_SOURCE_PATH,
    build_report,
    classify_group,
    classify_status,
)


class InventoryDataGenerationTests(unittest.TestCase):
    def test_classify_group_uses_business_priority(self):
        self.assertEqual(classify_group("五粮液八代（0191）"), "八代/纪念系列")
        self.assertEqual(classify_group("八代元旦纪念"), "八代/纪念系列")
        self.assertEqual(classify_group("52%1618五粮液"), "五粮液")
        self.assertEqual(classify_group("泸州老窖特曲96版"), "泸州老窖")
        self.assertEqual(classify_group("六和液小酒"), "六和液")
        self.assertEqual(classify_group("珍品礼盒"), "其他")

    def test_classify_status_priority(self):
        self.assertEqual(classify_status("", ""), "待确认")
        self.assertEqual(classify_status("35件", "（外箱标识为60版）"), "有备注")
        self.assertEqual(classify_status("20件", ""), "正常")

    def test_current_workbook_summary(self):
        source = Path(DEFAULT_SOURCE_PATH)
        self.assertTrue(source.exists(), f"Missing workbook: {source}")

        report = build_report(source)

        self.assertEqual(report["summary"]["totalItems"], 77)
        self.assertEqual(report["summary"]["attentionItems"], 4)
        self.assertEqual(report["summary"]["quantityGaps"], 1)
        self.assertEqual(report["summary"]["brandSeriesCount"], 5)
        self.assertEqual(
            report["summary"]["groupCounts"],
            {
                "五粮液": 34,
                "八代/纪念系列": 9,
                "其他": 31,
                "泸州老窖": 1,
                "六和液": 2,
            },
        )


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
python3 -m unittest tests.test_generate_data -v
```

Expected: FAIL because `scripts.generate_data` does not exist yet.

- [ ] **Step 4: Implement the data generator**

Create `scripts/generate_data.py`:

```python
from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any

import xlrd


DEFAULT_SOURCE_PATH = "/Users/deviny/Main-2F-Office/SynologyDrive/库存核对（暂估-库存-发票）/库存盘点表-20260430 copy.xls"
DEFAULT_JSON_OUTPUT = Path("public/data/inventory.json")
DEFAULT_JS_OUTPUT = Path("public/data/inventory-data.js")

HEADERS = ["序号", "存货编号", "品名", "规格", "单位", "实盘数量", "备注"]
GROUP_ORDER = ["五粮液", "八代/纪念系列", "其他", "泸州老窖", "六和液"]
STATUS_ORDER = ["待确认", "有备注", "正常"]


def cell_text(sheet: xlrd.sheet.Sheet, row: int, col: int) -> str:
    if col >= sheet.ncols:
        return ""
    value = sheet.cell_value(row, col)
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value).strip()


def classify_group(name: str) -> str:
    memorial_keywords = ("八代", "元旦纪念", "国庆纪念", "中秋纪念", "春节纪念", "牛年纪念")
    if any(keyword in name for keyword in memorial_keywords):
        return "八代/纪念系列"
    if "五粮液" in name:
        return "五粮液"
    if "泸州老窖" in name:
        return "泸州老窖"
    if "六和液" in name:
        return "六和液"
    return "其他"


def classify_status(physical_count: str, remark: str) -> str:
    if not physical_count.strip():
        return "待确认"
    if remark.strip():
        return "有备注"
    return "正常"


def find_populated_sheet(workbook: xlrd.book.Book) -> xlrd.sheet.Sheet:
    for sheet in workbook.sheets():
        if sheet.nrows and sheet.ncols:
            return sheet
    raise ValueError("Workbook has no populated sheet.")


def find_header_row(sheet: xlrd.sheet.Sheet) -> int:
    for row_index in range(sheet.nrows):
        row_values = [cell_text(sheet, row_index, col) for col in range(sheet.ncols)]
        joined = " ".join(row_values)
        if "序号" in joined and "品名" in joined and "实盘数量" in joined:
            return row_index
    raise ValueError("Could not find required inventory table header row.")


def parse_rows(sheet: xlrd.sheet.Sheet, header_row: int) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for row_index in range(header_row + 1, sheet.nrows):
        values = [cell_text(sheet, row_index, col) for col in range(max(sheet.ncols, 7))]
        if not any(values):
            continue

        item_name = values[2]
        if not item_name:
            continue

        physical_count = values[5]
        remark = values[6]
        group = classify_group(item_name)
        status = classify_status(physical_count, remark)

        rows.append(
            {
                "sequence": values[0],
                "inventoryCode": values[1],
                "name": item_name,
                "spec": values[3],
                "unit": values[4],
                "physicalCount": physical_count,
                "remark": remark,
                "group": group,
                "status": status,
            }
        )
    return rows


def ordered_counts(counter: Counter[str], preferred_order: list[str]) -> dict[str, int]:
    ordered: dict[str, int] = {}
    for key in preferred_order:
        if key in counter:
            ordered[key] = counter[key]
    for key, value in counter.items():
        if key not in ordered:
            ordered[key] = value
    return ordered


def build_report(source_path: Path) -> dict[str, Any]:
    if not source_path.exists():
        raise FileNotFoundError(f"Source workbook not found: {source_path}")

    workbook = xlrd.open_workbook(str(source_path))
    sheet = find_populated_sheet(workbook)
    header_row = find_header_row(sheet)
    title = cell_text(sheet, 0, 0) or "库存盘点表"
    rows = parse_rows(sheet, header_row)
    if not rows:
        raise ValueError("No inventory rows were parsed.")

    group_counts = Counter(row["group"] for row in rows)
    status_counts = Counter(row["status"] for row in rows)
    unit_counts = Counter(row["unit"] or "未填写" for row in rows)
    attention_rows = [row for row in rows if row["status"] != "正常"]

    return {
        "metadata": {
            "title": title,
            "reportDate": "2026-04-30",
            "sourceFile": source_path.name,
            "sheetName": sheet.name,
            "generatedAt": datetime.now().isoformat(timespec="seconds"),
        },
        "summary": {
            "totalItems": len(rows),
            "brandSeriesCount": len(group_counts),
            "attentionItems": len(attention_rows),
            "quantityGaps": status_counts.get("待确认", 0),
            "groupCounts": ordered_counts(group_counts, GROUP_ORDER),
            "statusCounts": ordered_counts(status_counts, STATUS_ORDER),
            "unitCounts": dict(unit_counts),
        },
        "attentionRows": attention_rows,
        "rows": rows,
    }


def write_outputs(report: dict[str, Any], json_output: Path, js_output: Path) -> None:
    json_output.parent.mkdir(parents=True, exist_ok=True)
    js_output.parent.mkdir(parents=True, exist_ok=True)
    json_text = json.dumps(report, ensure_ascii=False, indent=2)
    json_output.write_text(json_text + "\n", encoding="utf-8")
    js_output.write_text("window.INVENTORY_DATA = " + json_text + ";\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate static inventory report data.")
    parser.add_argument("--source", default=DEFAULT_SOURCE_PATH, help="Path to the source .xls workbook.")
    parser.add_argument("--json-output", default=str(DEFAULT_JSON_OUTPUT), help="Path for generated JSON output.")
    parser.add_argument("--js-output", default=str(DEFAULT_JS_OUTPUT), help="Path for generated browser JS output.")
    args = parser.parse_args()

    report = build_report(Path(args.source))
    write_outputs(report, Path(args.json_output), Path(args.js_output))
    print(
        f"Generated {args.json_output} and {args.js_output} "
        f"with {report['summary']['totalItems']} inventory rows."
    )


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run tests to verify pass**

Run:

```bash
python3 -m unittest tests.test_generate_data -v
```

Expected: PASS for all 3 tests.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
git add requirements.txt scripts/generate_data.py tests/test_generate_data.py
git commit -m "feat: add inventory data generator"
```

## Task 2: Static Report UI

**Files:**
- Create: `index.html`
- Create: `styles.css`
- Create: `app.js`

- [ ] **Step 1: Generate data for frontend consumption**

Run:

```bash
python3 scripts/generate_data.py
```

Expected: `public/data/inventory.json` and `public/data/inventory-data.js` are created with 77 rows.

- [ ] **Step 2: Create the HTML shell**

Create `index.html` with:

```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>库存盘点报告</title>
    <link rel="stylesheet" href="styles.css">
  </head>
  <body>
    <main class="report-shell">
      <header class="report-header">
        <div>
          <p class="eyebrow">库存盘点报告</p>
          <h1 id="report-title">库存盘点表</h1>
          <p class="subtitle" id="report-subtitle">正在加载数据...</p>
        </div>
        <div class="report-actions" aria-label="报告操作">
          <button type="button" id="print-button">打印 / 导出 PDF</button>
        </div>
      </header>

      <section class="toolbar" aria-label="筛选工具">
        <label>
          <span>搜索</span>
          <input id="search-input" type="search" placeholder="品名、编号、规格、备注">
        </label>
        <label>
          <span>品牌/系列</span>
          <select id="group-filter"></select>
        </label>
        <label>
          <span>状态</span>
          <select id="status-filter"></select>
        </label>
      </section>

      <section id="error-state" class="state-message" hidden></section>

      <section class="summary-grid" id="summary-grid" aria-label="库存摘要"></section>

      <section class="report-grid">
        <aside class="insight-column">
          <section class="panel">
            <div class="panel-heading">
              <h2>品牌/系列看板</h2>
              <span id="group-total"></span>
            </div>
            <div id="group-board" class="group-board"></div>
          </section>

          <section class="panel attention-panel">
            <div class="panel-heading">
              <h2>关注清单</h2>
              <span id="attention-total"></span>
            </div>
            <div id="attention-list" class="attention-list"></div>
          </section>
        </aside>

        <section class="table-panel">
          <div class="table-heading">
            <div>
              <h2>盘点明细</h2>
              <p id="table-count"></p>
            </div>
          </div>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>序号</th>
                  <th>存货编号</th>
                  <th>品名</th>
                  <th>品牌/系列</th>
                  <th>规格</th>
                  <th>单位</th>
                  <th>实盘数量</th>
                  <th>状态</th>
                  <th>备注</th>
                </tr>
              </thead>
              <tbody id="inventory-body"></tbody>
            </table>
          </div>
        </section>
      </section>
    </main>

    <script src="public/data/inventory-data.js"></script>
    <script src="app.js"></script>
  </body>
</html>
```

- [ ] **Step 3: Create report styles**

Create `styles.css` with screen and print styles for the report:

```css
:root {
  color-scheme: light;
  --bg: #eef2f7;
  --surface: #ffffff;
  --surface-soft: #f8fafc;
  --text: #172033;
  --muted: #667085;
  --line: #d9e2ef;
  --blue: #2563eb;
  --teal: #0f766e;
  --amber: #b45309;
  --amber-bg: #fff7ed;
  --warning-bg: #fffbeb;
  --danger: #991b1b;
  --danger-bg: #fef2f2;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", sans-serif;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
}

button,
input,
select {
  font: inherit;
}

.report-shell {
  width: min(1440px, calc(100% - 32px));
  margin: 24px auto;
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 24px;
  box-shadow: 0 18px 42px rgba(15, 23, 42, 0.08);
}

.report-header {
  display: flex;
  justify-content: space-between;
  gap: 20px;
  align-items: flex-start;
  border-bottom: 1px solid var(--line);
  padding-bottom: 18px;
}

.eyebrow {
  margin: 0 0 6px;
  color: var(--blue);
  font-size: 13px;
  font-weight: 700;
}

h1,
h2,
p {
  margin-top: 0;
}

h1 {
  margin-bottom: 8px;
  font-size: 30px;
  line-height: 1.2;
}

h2 {
  margin-bottom: 0;
  font-size: 16px;
}

.subtitle,
.table-heading p,
.panel-heading span {
  color: var(--muted);
}

.report-actions button {
  min-height: 40px;
  border: 1px solid var(--blue);
  border-radius: 6px;
  background: var(--blue);
  color: white;
  padding: 0 14px;
  cursor: pointer;
}

.toolbar {
  display: grid;
  grid-template-columns: minmax(240px, 1fr) 180px 160px;
  gap: 12px;
  padding: 18px 0;
}

.toolbar label {
  display: grid;
  gap: 6px;
  color: var(--muted);
  font-size: 13px;
  font-weight: 600;
}

.toolbar input,
.toolbar select {
  min-height: 38px;
  border: 1px solid var(--line);
  border-radius: 6px;
  background: white;
  color: var(--text);
  padding: 0 10px;
}

.summary-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
  margin-bottom: 16px;
}

.summary-card,
.panel,
.table-panel,
.state-message {
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--surface);
}

.summary-card {
  padding: 14px;
}

.summary-card strong {
  display: block;
  font-size: 28px;
  line-height: 1;
}

.summary-card span {
  display: block;
  margin-top: 8px;
  color: var(--muted);
  font-size: 13px;
}

.summary-card.attention {
  background: var(--amber-bg);
  border-color: #fed7aa;
}

.summary-card.gap {
  background: var(--danger-bg);
  border-color: #fecaca;
}

.report-grid {
  display: grid;
  grid-template-columns: 320px minmax(0, 1fr);
  gap: 16px;
  align-items: start;
}

.insight-column {
  display: grid;
  gap: 16px;
}

.panel,
.table-panel,
.state-message {
  padding: 16px;
}

.panel-heading,
.table-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}

.group-board {
  display: grid;
  gap: 10px;
}

.group-row {
  display: grid;
  grid-template-columns: 92px 1fr 36px;
  gap: 10px;
  align-items: center;
  font-size: 13px;
}

.bar-track {
  height: 10px;
  overflow: hidden;
  border-radius: 999px;
  background: #e5e7eb;
}

.bar-fill {
  height: 100%;
  border-radius: inherit;
  background: var(--blue);
}

.attention-list {
  display: grid;
  gap: 10px;
}

.attention-item {
  border: 1px solid #fed7aa;
  border-radius: 6px;
  background: var(--amber-bg);
  padding: 10px;
}

.attention-item strong,
.attention-item span {
  display: block;
}

.attention-item span {
  margin-top: 4px;
  color: #7c2d12;
  font-size: 12px;
}

.table-wrap {
  overflow-x: auto;
}

table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

th,
td {
  border-bottom: 1px solid #e5e7eb;
  padding: 9px 8px;
  text-align: left;
  vertical-align: top;
}

th {
  position: sticky;
  top: 0;
  z-index: 1;
  background: #e2e8f0;
  color: #334155;
  font-size: 12px;
}

tbody tr.status-gap {
  background: var(--warning-bg);
}

tbody tr.status-note {
  background: var(--amber-bg);
}

.status-pill {
  display: inline-block;
  border-radius: 999px;
  padding: 3px 8px;
  background: #e8f5e9;
  color: #166534;
  font-size: 12px;
  font-weight: 700;
  white-space: nowrap;
}

.status-pill.status-gap {
  background: var(--warning-bg);
  color: var(--amber);
}

.status-pill.status-note {
  background: var(--amber-bg);
  color: #9a3412;
}

@media (max-width: 980px) {
  .report-shell {
    width: calc(100% - 20px);
    padding: 16px;
  }

  .report-header,
  .report-grid {
    grid-template-columns: 1fr;
    display: grid;
  }

  .toolbar,
  .summary-grid {
    grid-template-columns: 1fr 1fr;
  }
}

@media print {
  @page {
    size: A4 landscape;
    margin: 10mm;
  }

  body {
    background: white;
  }

  .report-shell {
    width: 100%;
    margin: 0;
    border: 0;
    border-radius: 0;
    box-shadow: none;
    padding: 0;
  }

  .toolbar,
  .report-actions {
    display: none !important;
  }

  .summary-grid {
    grid-template-columns: repeat(4, 1fr);
  }

  .report-grid {
    grid-template-columns: 300px 1fr;
    gap: 12px;
  }

  .panel,
  .table-panel,
  .summary-card {
    break-inside: avoid;
  }

  table {
    font-size: 10px;
  }

  thead {
    display: table-header-group;
  }

  th,
  td {
    padding: 5px 4px;
  }
}
```

- [ ] **Step 4: Create frontend rendering logic**

Create `app.js` with:

```javascript
const state = {
  report: window.INVENTORY_DATA,
  search: "",
  group: "全部",
  status: "全部",
};

const els = {
  title: document.querySelector("#report-title"),
  subtitle: document.querySelector("#report-subtitle"),
  printButton: document.querySelector("#print-button"),
  searchInput: document.querySelector("#search-input"),
  groupFilter: document.querySelector("#group-filter"),
  statusFilter: document.querySelector("#status-filter"),
  errorState: document.querySelector("#error-state"),
  summaryGrid: document.querySelector("#summary-grid"),
  groupBoard: document.querySelector("#group-board"),
  groupTotal: document.querySelector("#group-total"),
  attentionList: document.querySelector("#attention-list"),
  attentionTotal: document.querySelector("#attention-total"),
  tableCount: document.querySelector("#table-count"),
  inventoryBody: document.querySelector("#inventory-body"),
};

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function statusClass(status) {
  if (status === "待确认") return "status-gap";
  if (status === "有备注") return "status-note";
  return "status-normal";
}

function matchesSearch(row, search) {
  if (!search) return true;
  const haystack = [row.sequence, row.inventoryCode, row.name, row.group, row.spec, row.unit, row.physicalCount, row.status, row.remark]
    .join(" ")
    .toLowerCase();
  return haystack.includes(search.toLowerCase());
}

function filteredRows() {
  return state.report.rows.filter((row) => {
    return (
      matchesSearch(row, state.search) &&
      (state.group === "全部" || row.group === state.group) &&
      (state.status === "全部" || row.status === state.status)
    );
  });
}

function renderSummary() {
  const { summary } = state.report;
  const cards = [
    ["总品项", summary.totalItems, ""],
    ["品牌/系列", summary.brandSeriesCount, ""],
    ["需关注项", summary.attentionItems, "attention"],
    ["数量空缺", summary.quantityGaps, "gap"],
  ];
  els.summaryGrid.innerHTML = cards
    .map(([label, value, className]) => `<article class="summary-card ${className}"><strong>${value}</strong><span>${label}</span></article>`)
    .join("");
}

function renderFilters() {
  const groupOptions = ["全部", ...Object.keys(state.report.summary.groupCounts)];
  const statusOptions = ["全部", "待确认", "有备注", "正常"];
  els.groupFilter.innerHTML = groupOptions.map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`).join("");
  els.statusFilter.innerHTML = statusOptions.map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`).join("");
}

function renderGroupBoard() {
  const counts = state.report.summary.groupCounts;
  const max = Math.max(...Object.values(counts));
  els.groupTotal.textContent = `${Object.keys(counts).length} 组`;
  els.groupBoard.innerHTML = Object.entries(counts)
    .map(([group, count]) => {
      const width = Math.max(8, Math.round((count / max) * 100));
      return `
        <div class="group-row">
          <span>${escapeHtml(group)}</span>
          <span class="bar-track"><span class="bar-fill" style="width:${width}%"></span></span>
          <strong>${count}</strong>
        </div>
      `;
    })
    .join("");
}

function renderAttention() {
  els.attentionTotal.textContent = `${state.report.attentionRows.length} 项`;
  els.attentionList.innerHTML = state.report.attentionRows
    .map((row) => {
      const reason = row.status === "待确认" ? "数量空缺" : row.remark;
      return `
        <article class="attention-item">
          <strong>${escapeHtml(row.name)}</strong>
          <span>${escapeHtml(row.group)} · ${escapeHtml(row.physicalCount || "未填写")} · ${escapeHtml(reason)}</span>
        </article>
      `;
    })
    .join("");
}

function renderTable() {
  const rows = filteredRows();
  els.tableCount.textContent = `显示 ${rows.length} / ${state.report.rows.length} 项`;
  els.inventoryBody.innerHTML = rows
    .map((row) => `
      <tr class="${statusClass(row.status)}">
        <td>${escapeHtml(row.sequence)}</td>
        <td>${escapeHtml(row.inventoryCode)}</td>
        <td><strong>${escapeHtml(row.name)}</strong></td>
        <td>${escapeHtml(row.group)}</td>
        <td>${escapeHtml(row.spec)}</td>
        <td>${escapeHtml(row.unit)}</td>
        <td>${escapeHtml(row.physicalCount || "未填写")}</td>
        <td><span class="status-pill ${statusClass(row.status)}">${escapeHtml(row.status)}</span></td>
        <td>${escapeHtml(row.remark)}</td>
      </tr>
    `)
    .join("");
}

function renderReport() {
  if (!state.report || !state.report.rows) {
    els.errorState.hidden = false;
    els.errorState.textContent = "未能加载库存数据，请先运行 scripts/generate_data.py。";
    return;
  }

  const { metadata } = state.report;
  els.title.textContent = metadata.title;
  els.subtitle.textContent = `${metadata.reportDate} · ${metadata.sourceFile} · ${metadata.sheetName}`;
  renderSummary();
  renderFilters();
  renderGroupBoard();
  renderAttention();
  renderTable();
}

els.searchInput.addEventListener("input", (event) => {
  state.search = event.target.value.trim();
  renderTable();
});

els.groupFilter.addEventListener("change", (event) => {
  state.group = event.target.value;
  renderTable();
});

els.statusFilter.addEventListener("change", (event) => {
  state.status = event.target.value;
  renderTable();
});

els.printButton.addEventListener("click", () => window.print());

renderReport();
```

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add index.html styles.css app.js public/data/inventory.json public/data/inventory-data.js
git commit -m "feat: add static inventory report UI"
```

## Task 3: Verification And Polish

**Files:**
- Modify if needed: `styles.css`
- Modify if needed: `app.js`
- Modify if needed: `scripts/generate_data.py`

- [ ] **Step 1: Run data tests**

Run:

```bash
python3 -m unittest tests.test_generate_data -v
```

Expected: all tests pass.

- [ ] **Step 2: Verify generated data counts**

Run:

```bash
python3 - <<'PY'
import json
from pathlib import Path
data = json.loads(Path("public/data/inventory.json").read_text(encoding="utf-8"))
print(data["summary"])
assert data["summary"]["totalItems"] == 77
assert data["summary"]["attentionItems"] == 4
assert data["summary"]["quantityGaps"] == 1
PY
```

Expected: summary is printed and assertions pass.

- [ ] **Step 3: Run a local static server**

Run:

```bash
python3 -m http.server 8010
```

Expected: server starts on `http://localhost:8010`.

- [ ] **Step 4: Inspect the page**

Open `http://localhost:8010` and check:

- Summary cards show 77 total items, 5 brand/series, 4 attention items, 1 quantity gap.
- Brand/series board shows `五粮液`, `八代/纪念系列`, `其他`, `泸州老窖`, `六和液`.
- Attention list includes the four known attention rows.
- Search and filters change only the table count and rows.
- Print button opens the browser print flow.

- [ ] **Step 5: Commit verification fixes if any**

If Step 4 required changes, run:

```bash
git add styles.css app.js scripts/generate_data.py
git commit -m "fix: polish inventory report rendering"
```

If no changes were required, skip this commit.
