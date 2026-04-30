# Inventory Report Frontend Design

## Purpose

Build a modern, PDF-first frontend report for `库存盘点表-20260430 copy.xls`. The report should help colleagues understand the April 30, 2026 inventory snapshot at a glance, using only the data in this single spreadsheet rather than comparing against another period or system ledger.

The primary use case is printing or exporting to PDF. Browser viewing is still supported, but print readability is the main design constraint.

## Source Data

The source workbook has one populated sheet, `2025年4月`, containing the April 30, 2026 physical inventory table.

Observed structure:

- Title row: `高丽源2026年4月盘点表`
- Header row fields: `序号`, `存货编号`, `品名`, `规格`, `单位`, `2026年4月30日 实盘数量`, `备注`
- Data rows: 77
- Unit distribution: 45 `件`, 22 `盒`, 8 `瓶`, 1 `箱`, and 1 blank unit
- Attention items: 4 total
- Quantity gaps: 1 total

## Report Structure

The page will be a single modern report surface optimized for A4 landscape PDF output.

Top section:

- Report title and source file/date.
- Compact metadata chips, such as PDF-first and filterable.
- Four summary cards:
  - Total item count
  - Brand/series count
  - Attention item count
  - Quantity gap count

Main section:

- Left column:
  - Brand/series board with item counts and proportional bars.
  - Attention list for rows with missing quantity or remarks.
- Right column:
  - Modern inventory detail table.
  - Original spreadsheet fields preserved.
  - Generated `品牌/系列` and `状态` fields added for readability.

The visual direction should be clean, operational, and report-like: restrained colors, strong table hierarchy, compact cards, and no marketing-style hero section.

## Grouping Rules

Rows are grouped by item name. Rules are evaluated in this order so `八代/纪念系列` takes precedence over the broader `五粮液` group:

- Contains `八代`, `元旦纪念`, `国庆纪念`, `中秋纪念`, `春节纪念`, or `牛年纪念`: `八代/纪念系列`
- Contains `五粮液`: `五粮液`
- Contains `泸州老窖`: `泸州老窖`
- Contains `六和液`: `六和液`
- Otherwise: `其他`

For the current workbook, the expected group counts are:

- `五粮液`: 34
- `八代/纪念系列`: 9
- `其他`: 31
- `泸州老窖`: 1
- `六和液`: 2

## Highlighting Rules

Each row receives a generated status. Rules are evaluated in this order:

- `待确认`: physical count is empty.
- `有备注`: remark is present.
- `正常`: no quantity gap and no remark.

The report will highlight `待确认` and `有备注` rows with light background colors and explicit status text. The design must not rely on color alone.

Known attention items in the current workbook:

- `经典五粮液大品鉴`: quantity is empty.
- `五粮液原洒封坛红釉`: remark `大封坛酒`.
- `泸州老窖特曲96版`: remark `（外箱标识为60版）`.
- `六和液小酒`: remark `10瓶不翼而飞`.

## Browser Interactions

The screen view may include lightweight controls:

- Search by item name, inventory code, specification, or remark.
- Filter by brand/series.
- Filter by status.
- Print/export PDF button that calls the browser print flow.

These controls are convenience features only. They must be hidden in print output.

## Print And PDF Behavior

The print stylesheet will target A4 landscape.

Print output must:

- Hide interactive controls.
- Preserve the report title, summary cards, brand/series board, attention list, and full detail table.
- Repeat the table header across page breaks when supported by the browser.
- Keep attention rows visually marked with both background and status text.
- Avoid overlapping text, clipped columns, or cramped buttons.
- Keep the first page focused on summary and attention items as much as the data length allows.

## Data Flow

The frontend will use a generated JSON data file rather than reading Excel directly in the browser.

1. A local script reads the `.xls` workbook with `xlrd`.
2. The script extracts the populated sheet and normalizes rows.
3. The script writes a JSON file containing:
   - Source metadata
   - Original rows
   - Generated brand/series
   - Generated status
   - Summary counts
4. The frontend loads the JSON and renders summary cards, group board, attention list, filters, and detail table.

This keeps the frontend static and easy to open, while making monthly refreshes possible by rerunning the data generation script.

## Technical Shape

The repository is currently empty except for Git metadata, so the implementation can use a small static frontend.

Recommended structure:

- `scripts/generate-data.py`: reads the Excel file and writes normalized JSON.
- `public/data/inventory.json`: generated data consumed by the frontend.
- `src/` or root-level static assets depending on the chosen frontend setup.
- `index.html`, stylesheet, and JavaScript for the report UI.

No backend server is required for the core report.

## Error Handling

The data generation script should fail clearly when:

- The source file is missing.
- The workbook has no populated sheet.
- Required columns cannot be found.
- A row is malformed enough that required fields cannot be extracted.

The frontend should show a calm empty/error state when JSON cannot be loaded, but the main expected workflow is generating the JSON before opening or printing the report.

## Testing And Verification

Data verification:

- Confirm the parser produces 77 data rows for the current workbook.
- Confirm the group counts match the design.
- Confirm the attention count is 4.
- Confirm the quantity gap count is 1.

UI verification:

- Open the report in a browser.
- Check desktop layout for readable cards, group board, attention list, and table.
- Check print preview or a print-sized viewport for A4 landscape readability.
- Confirm interactive controls are hidden in print mode.
- Confirm highlighted rows remain understandable without relying on color alone.

## Out Of Scope

- Comparing inventory against prior months.
- Comparing inventory against system stock.
- Uploading spreadsheets through the UI.
- Multi-user hosting or authentication.
- Editing inventory records in the browser.
