# Photo Only Face Analyzer Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small photo-only face-analysis prototype that can analyze already exported local image files and produce face-analysis records.

**Architecture:** Keep the prototype in `PhotosArchiveExporterCore` so it can be unit-tested without PhotoKit UI. Add a protocol-backed detector boundary: tests use a fake detector, while production gets a Vision-backed still-image detector. The runner consumes successful image `ExportRecord`s and returns `FaceAnalysisAssetRecord` plus `FaceObservationRecord` values for the existing report store.

**Tech Stack:** Swift, Foundation, Vision, ImageIO, XCTest, Swift Package Manager.

---

## File Structure

- Create: `Sources/PhotosArchiveExporterCore/FaceAnalysisPhotoAnalyzer.swift`
  - Owns detector DTOs, detector protocol, file-based analyzer runner, and Vision still-image detector.
- Modify: `Sources/PhotosArchiveExporterCore/FaceAnalysisTypes.swift`
  - Add a status for unsupported/skipped non-photo inputs if needed by tests.
- Create: `Tests/PhotosArchiveExporterCoreTests/FaceAnalysisPhotoAnalyzerTests.swift`
  - Covers no-face, multi-face, failed image analysis, and skipping non-image or failed export records.

## Task 1: Protocol Runner With Test Doubles

**Files:**
- Create: `Sources/PhotosArchiveExporterCore/FaceAnalysisPhotoAnalyzer.swift`
- Create: `Tests/PhotosArchiveExporterCoreTests/FaceAnalysisPhotoAnalyzerTests.swift`

- [ ] **Step 1: Write failing runner tests**

Add tests:

```swift
func testAnalyzesExportedImageRecordsWithInjectedDetector() async throws
func testRecordsFailedAnalysisWithoutStoppingRun() async throws
func testSkipsNonImageAndFailedExportRecords() async throws
```

The fake detector should return two faces for one image, throw for another image, and never be called for video or failed export records.

- [ ] **Step 2: Run focused tests to verify failure**

Run:

```bash
swift test --filter FaceAnalysisPhotoAnalyzerTests
```

Expected: fail because `FaceAnalysisPhotoAnalyzer` and detector DTOs do not exist.

- [ ] **Step 3: Implement protocol runner**

Create:

```swift
public struct StillImageFaceDetectionResult: Equatable
public struct DetectedFace: Equatable
public protocol StillImageFaceDetecting
public struct FaceAnalysisPhotoAnalyzer
public struct FaceAnalysisPhotoAnalyzerResult
```

The runner should:

- Analyze only `ExportRecord` values with `mediaType == .image` and `status != .failed`.
- Use `ExportRecord.destinationPath` as the local image file URL.
- Produce `.analyzed` asset records on detector success.
- Produce `.failed` asset records on detector errors.
- Preserve original filename, asset identifier, resource identifier, SHA-256, and file size from the export record.
- Convert detected faces into `FaceObservationRecord`s with stable IDs based on run ID, asset identifier, resource identifier, and face index.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter FaceAnalysisPhotoAnalyzerTests
```

Expected: all photo analyzer tests pass.

## Task 2: Vision Still Image Detector

**Files:**
- Modify: `Sources/PhotosArchiveExporterCore/FaceAnalysisPhotoAnalyzer.swift`

- [ ] **Step 1: Add a focused invalid-image test**

Add:

```swift
func testVisionDetectorThrowsForUnsupportedImageFile() async throws
```

Write a temporary text file and assert `VisionStillImageFaceDetector.detectFaces(in:)` throws.

- [ ] **Step 2: Run focused tests to verify failure**

Run:

```bash
swift test --filter FaceAnalysisPhotoAnalyzerTests/testVisionDetectorThrowsForUnsupportedImageFile
```

Expected: fail because `VisionStillImageFaceDetector` does not exist.

- [ ] **Step 3: Implement Vision detector**

Use `CGImageSourceCreateWithURL`, `CGImageSourceCreateImageAtIndex`, and `VNDetectFaceLandmarksRequest`. Convert Vision bounding boxes and landmarks into existing normalized face-analysis records. Leave quality nil if Vision does not provide it from the landmarks request.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter FaceAnalysisPhotoAnalyzerTests
```

Expected: all photo analyzer tests pass.

## Task 3: Full Verification

**Files:**
- No new files.

- [ ] **Step 1: Run full tests**

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

Expected: only face-analysis core, tests, and plan files changed.
