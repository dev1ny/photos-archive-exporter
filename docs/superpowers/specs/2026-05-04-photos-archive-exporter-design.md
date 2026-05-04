# Photos Archive Exporter Design

## Purpose

Build a native macOS app that safely exports original photo and video resources from the current macOS Photos library into a normal folder hierarchy. The app is for long-term personal backup and archive organization, with full export as the first priority and incremental backup support prepared by the data model.

The app must never modify, delete, or reorganize the Photos library itself. It is a read-only exporter.

## Primary User Goals

- Export the entire current Photos library as original resources.
- Preserve original photo, video, Live Photo, RAW, and JPEG resources.
- Organize exported files by capture date into year, month, and day folders.
- Name files with capture date/time plus the original filename.
- Keep all duplicates by default, while reporting strong duplicates.
- Produce human-readable and machine-readable export reports.
- Allow safe reruns without overwriting or losing prior exports.

## Source Library Model

The first version uses Apple PhotoKit against the current Photos library. For an old or external `.photoslibrary` package, the user first opens or switches to that library in the Photos app, then returns to this exporter.

The app will not directly inspect the internal `.photoslibrary` database or package structure in version 1. That path is intentionally out of scope because it depends on private implementation details that can change across macOS and Photos versions.

The expected first-version assumption is that all originals are already stored locally on the Mac. iCloud download orchestration is out of scope for version 1, although the error model will leave room to report unavailable resources.

## Technical Direction

Use a native SwiftUI macOS app backed by PhotoKit.

Key Apple frameworks:

- SwiftUI for the desktop interface.
- Photos / PhotoKit for authorization, asset enumeration, and original resource export.
- UniformTypeIdentifiers for file type handling.
- CryptoKit for SHA-256 hashing.
- Foundation file APIs for folder creation, temporary files, atomic moves, CSV/JSON reports, and security-scoped destination access where needed.

The app should be structured so the export engine is testable without the UI. SwiftUI views should observe export state, but not contain PhotoKit traversal or file-writing logic.

## Core Components

### PhotoLibraryScanner

Requests read access to Photos and enumerates `PHAsset` records from the current library. It produces stable asset descriptors containing local identifier, media type, creation date, modification date, dimensions when available, and basic Photos metadata.

### AssetResourceResolver

Expands each `PHAsset` into the original `PHAssetResource` records that need export. It keeps all original resources, including:

- Standard image originals.
- Video originals.
- Live Photo still and paired video resources.
- RAW and JPEG pairs.
- Other original resources that PhotoKit exposes as part of an asset.

Edited renderings, adjustment data, thumbnails, and previews are not export targets in version 1.

### MetadataReader

Determines the archive date for each export resource.

Capture date priority:

1. EXIF or QuickTime capture timestamp from the original resource, when available.
2. Photos asset creation date.
3. Export run timestamp, marked with a `missing_capture_date` warning.

The app should preserve the original resource file bytes and avoid rewriting metadata.

### ExportPlanner

Builds deterministic destination paths from the archive date and original filename.

Folder layout:

```text
Destination/
  2024/
    2024-08/
      2024-08-16/
        2024-08-16_14-22-10_IMG_1234.HEIC
```

Filename format:

```text
yyyy-MM-dd_HH-mm-ss_originalFilename.ext
```

If the planned path already exists:

- If an existing index entry or fresh hash check proves the content is identical, skip the resource and record `skipped_existing`.
- If the path exists but content differs, generate a suffix such as `__2`, `__3`, and record `renamed_conflict`.
- Never overwrite by default.

### ExportRunner

Executes the export plan with pause, cancel, and retry-friendly state. It writes each resource to a temporary file first, computes its SHA-256 hash, then moves it to the final path. Temporary files prevent interrupted exports from looking complete.

Single-resource failures do not stop the whole run. Failures are recorded and the runner continues.

### ArchiveIndexStore

Persists a detailed JSON index and CSV report in the destination folder. The index is the foundation for safe reruns and future incremental backup.

Each exported resource row should include:

- Run ID.
- Photos asset local identifier.
- Resource identifier or stable resource signature where available.
- Resource type.
- Media type.
- Original filename.
- Destination path.
- Capture timestamp used for sorting.
- Capture timestamp source.
- File size.
- SHA-256 hash when exported or verified.
- Export status.
- Warning codes.
- Error message when relevant.

### DuplicateReporter

Generates a strong duplicate report based on SHA-256 hash equality. Duplicates are never deleted or merged automatically. Version 1 reports strong duplicates only; fuzzy similarity detection is out of scope.

## User Flow

1. User opens the app.
2. App shows Photos authorization status and a clear read-only explanation.
3. User grants Photos access if needed.
4. User selects the destination archive folder.
5. User clicks `Scan Library`.
6. App shows asset/resource counts, media breakdown, and any preflight warnings.
7. User clicks `Start Full Export`.
8. App shows progress, current file, current day group, elapsed time, and counts for exported, skipped, failed, and duplicate resources.
9. User may pause or cancel. A later run can continue safely from the index and existing files.
10. On completion, app shows a summary and links to the saved index, duplicate report, and error report.

## Interface Shape

The first screen should be the working exporter, not a marketing landing page.

Main areas:

- Source panel: current Photos library status, authorization status, and note about switching old libraries through Photos.
- Destination picker: selected folder, free-space preflight status, and report location.
- Scan summary: total assets, total export resources, photos, videos, Live Photo paired resources, RAW/JPEG pairs when detectable.
- Export controls: scan, start, pause, cancel, retry failed.
- Progress area: progress bar, current file, current date group, throughput, elapsed time.
- Results area: exported, skipped, failed, conflicts renamed, strong duplicates, missing date warnings.
- Report actions: reveal destination, open detailed CSV, open JSON index, open error report.

The UI should feel like a careful utility: dense enough for a long-running archive job, restrained, readable, and calm. It should not use a hero page, decorative cards inside cards, or marketing copy.

## Reports

The app saves reports inside a `_photos_archive_exporter/` folder under the destination root.

Recommended files:

```text
Destination/
  _photos_archive_exporter/
    archive-index.json
    export-runs/
      2026-05-04T20-30-00Z-summary.json
      2026-05-04T20-30-00Z-resources.csv
      2026-05-04T20-30-00Z-errors.csv
      2026-05-04T20-30-00Z-duplicates.csv
```

The UI displays a concise run summary, while CSV/JSON files preserve details for audit, troubleshooting, and future incremental backup.

## Incremental Backup Preparation

Version 1 is full export first. It still stores enough identity data to support later incremental backup.

Future incremental runs can compare current Photos resources against `archive-index.json` by Photos local identifier, original filename, resource type, size, and hash. If PhotoKit persistent change tokens are adopted later, the app can scan only changed assets, but version 1 should not depend on that for correctness.

## Error Handling

The app should handle and report:

- Photos access denied or limited.
- No Photos library available.
- Destination folder missing or not writable.
- Insufficient disk space during preflight or export.
- Resource unavailable from PhotoKit.
- Metadata missing or unparseable.
- Existing path conflicts.
- Temporary write failure.
- Final move failure.
- Hashing failure.
- User cancellation.

Errors are attached to resource rows when possible. Run-level errors are recorded in the summary. A failed resource can be retried in a later run.

## Safety Principles

- Never mutate the Photos library.
- Never overwrite destination files by default.
- Never delete duplicate files automatically.
- Write to temporary files before final moves.
- Keep an append-friendly export history.
- Make every skipped, failed, or renamed resource visible in reports.

## Testing And Verification

Unit tests:

- Destination path generation for normal names, duplicate names, and invalid filesystem characters.
- Capture-date priority selection.
- Conflict suffix generation.
- Index read/write round trip.
- Duplicate hash grouping.

Integration tests with test doubles:

- Scanner output with multiple resource types.
- Full export plan generation.
- Resume behavior when index entries already exist.
- Failure recording when a resource cannot be written.

Manual verification:

- Run against a small test Photos library.
- Verify original filenames and extensions are preserved.
- Verify Live Photo still and video resources both export.
- Verify RAW+JPEG assets export both resources.
- Verify folder layout is year/month/day.
- Verify rerun skips identical exported resources.
- Verify duplicate report lists identical SHA-256 groups without deleting anything.
- Verify cancel and restart do not leave completed-looking partial files.

## Out Of Scope For Version 1

- Direct parsing of arbitrary `.photoslibrary` package internals.
- Automatic iCloud original download management.
- Exporting edited versions.
- Deleting, merging, or modifying Photos assets.
- Automatic duplicate removal.
- Fuzzy duplicate detection.
- Face, album, or place-based folder organization.
- Cloud backup upload.
- Multi-user sharing or remote dashboard.

