# Face Analysis Data Model And Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first face-analysis experiment slice: local-only data models, summary aggregation, and JSON / CSV report writing.

**Architecture:** Keep face analysis separate from the current archive export index. Add a focused `FaceAnalysisTypes.swift` file for Codable records and aggregation, plus `FaceAnalysisReportStore.swift` for support-directory output. Do not add Vision, PhotoKit analysis execution, or UI in this slice.

**Tech Stack:** Swift, Foundation, XCTest, Swift Package Manager.

---

## File Structure

- Create: `Sources/PhotosArchiveExporterCore/FaceAnalysisTypes.swift`
  - Owns settings, status enums, asset records, face observation records, run summaries, and aggregation.
- Create: `Sources/PhotosArchiveExporterCore/FaceAnalysisReportStore.swift`
  - Owns `face-analysis-index.json` plus per-run summary JSON and CSV report writing.
- Create: `Tests/PhotosArchiveExporterCoreTests/FaceAnalysisReportStoreTests.swift`
  - Covers settings encode/decode, summary counts, CSV escaping and formula neutralization, invalid run IDs, and report file paths.

## Task 1: Face Analysis Models And Summary

**Files:**
- Create: `Sources/PhotosArchiveExporterCore/FaceAnalysisTypes.swift`
- Test: `Tests/PhotosArchiveExporterCoreTests/FaceAnalysisReportStoreTests.swift`

- [ ] **Step 1: Write failing tests for settings and summary aggregation**

Add tests named:

```swift
func testSettingsRoundTripThroughJSON() throws
func testRunSummaryAggregatesAssetsAndFaces()
```

The tests should expect:

```swift
FaceAnalysisSettings(
    includeVideos: true,
    resourceProfile: .balanced,
    imageLongEdgeLimit: 1600,
    videoFrameIntervalSeconds: 3,
    maxFramesPerVideo: 100,
    settingsVersion: 1
)
```

and a summary with 4 asset records:

```swift
analyzedAssetCount == 2
skippedAssetCount == 1
failedAssetCount == 1
photoAssetCount == 2
videoAssetCount == 2
facesDetectedCount == 3
assetsWithFacesCount == 1
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter FaceAnalysisReportStoreTests
```

Expected: fail because `FaceAnalysisSettings` and related types do not exist.

- [ ] **Step 3: Implement models and aggregation**

Create `FaceAnalysisTypes.swift` with public Codable and Equatable types:

```swift
public enum FaceAnalysisResourceProfile: String, Codable, Equatable, CaseIterable {
    case lowResource
    case balanced
    case faster
}

public enum FaceAnalysisAssetStatus: String, Codable, Equatable, CaseIterable {
    case analyzed
    case skippedUnchanged
    case failed
    case canceled
}
```

Add `FaceAnalysisSettings`, `FaceAnalysisAssetRecord`, `FaceObservationRecord`, `FaceLandmarkRecord`, and `FaceAnalysisRunSummary`. Use normalized bounding-box values and optional video timestamps.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter FaceAnalysisReportStoreTests
```

Expected: tests compile and pass for the model and summary cases.

## Task 2: Report Store

**Files:**
- Create: `Sources/PhotosArchiveExporterCore/FaceAnalysisReportStore.swift`
- Modify: `Tests/PhotosArchiveExporterCoreTests/FaceAnalysisReportStoreTests.swift`

- [ ] **Step 1: Write failing report-store tests**

Add tests named:

```swift
func testWritesIndexSummaryAndCSVReports() throws
func testFaceAnalysisCSVNeutralizesSpreadsheetFormulas() throws
func testRejectsInvalidFaceAnalysisRunIDs() throws
```

The tests should expect these files:

```text
_photos_archive_exporter/face-analysis-index.json
_photos_archive_exporter/face-analysis-runs/run-1/run-1-summary.json
_photos_archive_exporter/face-analysis-runs/run-1/run-1-assets.csv
_photos_archive_exporter/face-analysis-runs/run-1/run-1-faces.csv
_photos_archive_exporter/face-analysis-runs/run-1/run-1-errors.csv
```

CSV fields beginning with `=`, `+`, `-`, `@`, tab, or carriage return must be prefixed with `'`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter FaceAnalysisReportStoreTests
```

Expected: fail because `FaceAnalysisReportStore` does not exist.

- [ ] **Step 3: Implement report store**

Create `FaceAnalysisReportStore` with:

```swift
public init(destinationRoot: URL)
public var supportDirectory: URL
public var indexURL: URL
public func loadIndex() throws -> [FaceAnalysisAssetRecord]
public func saveIndex(_ records: [FaceAnalysisAssetRecord]) throws
public func writeRunSummary(_ summary: FaceAnalysisRunSummary) throws -> URL
public func writeAssetsCSV(runID: String, records: [FaceAnalysisAssetRecord]) throws -> URL
public func writeFacesCSV(runID: String, faces: [FaceObservationRecord]) throws -> URL
public func writeErrorsCSV(runID: String, records: [FaceAnalysisAssetRecord]) throws -> URL
```

Use pretty-printed sorted-key JSON with ISO-8601 dates. Reuse the same run-ID validation behavior as `ArchiveIndexStore`.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter FaceAnalysisReportStoreTests
```

Expected: all face-analysis report-store tests pass.

## Task 3: Full Verification

**Files:**
- No new files.

- [ ] **Step 1: Run the full SwiftPM test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Inspect diff**

Run:

```bash
git diff --stat
git diff --check
```

Expected: only the new face-analysis plan, core files, and tests changed; no whitespace errors.
