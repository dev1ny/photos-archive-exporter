# Face Analysis Experiment Design

## Purpose

Explore whether Photos Archive Exporter can add an optional, local-only face analysis feature using public Apple APIs, without changing the current export behavior or mutating the Photos library.

This is an experimental branch feature. It must stay isolated from the released `v0.1.1` behavior until it proves useful, stable, and resource-safe.

## Scope Decision

The feature is **face analysis**, not person recognition.

In scope:

- Detect faces in photos.
- Detect face rectangles and facial landmarks.
- Record face count, location, confidence, landmarks, quality, and analysis errors when available.
- Optionally sample video frames and run the same face analysis on sampled frames.
- Save JSON / CSV reports under the archive support directory.
- Show a separate UI summary for analysis results.
- Support cancellation, low-resource mode, and resume/skip behavior.

Out of scope:

- Identifying who a person is.
- Reading Apple Photos People names or internal person clusters.
- Accessing private `.photoslibrary` databases.
- Mutating Photos assets or creating People albums.
- Automatically deleting, merging, or moving files based on faces.
- Full-frame analysis of every video frame by default.

## Apple API Feasibility

PhotoKit can provide access to Photos assets and resources that the current app already scans and exports.

Vision can analyze still images for faces, landmarks, and face quality. It can also process image sequences and video frames through public video/frame APIs.

AVFoundation can extract still frames from video assets at chosen timestamps through `AVAssetImageGenerator`.

Recommended public API path:

- Photos / PhotoKit: locate assets and request image or video resources.
- Vision: run face detection, landmarks, and quality analysis on images or frames.
- AVFoundation: sample frames from video resources at controlled intervals.

The design avoids private Photos internals and avoids depending on Apple Photos' own People recognition database.

## Product Shape

Add a new optional workflow named **Face Analysis**. It should be separate from **Scan Library** and **Start Full Export**.

The main export flow remains unchanged:

1. Authorize Photos.
2. Choose archive destination.
3. Scan library.
4. Export originals.
5. Review export results.

The experimental analysis flow is explicit:

1. Choose whether to analyze photos only or photos plus sampled video.
2. Choose resource profile: low resource, balanced, or faster.
3. Start analysis.
4. App writes analysis reports and shows a summary.
5. User may cancel and resume later.

## Data Model

Add a separate face-analysis index. Do not extend `archive-index.json` directly in the first experiment.

Recommended files:

```text
Destination/
  _photos_archive_exporter/
    face-analysis-index.json
    face-analysis-runs/
      2026-05-07T12-30-00Z/
        2026-05-07T12-30-00Z-summary.json
        2026-05-07T12-30-00Z-assets.csv
        2026-05-07T12-30-00Z-faces.csv
        2026-05-07T12-30-00Z-errors.csv
```

Core records:

- `FaceAnalysisRun`: run ID, started/finished time, settings, totals, cancellation state.
- `AnalyzedAssetRecord`: Photos asset identifier, media type, original filename/resource identity, file hash when available, status, warning/error.
- `FaceObservationRecord`: asset identifier, optional video timestamp, face index, bounding box, confidence, quality, roll/yaw/pitch when available, landmark availability.
- `FaceLandmarkRecord`: face observation ID, landmark region name, normalized points, confidence when available.

Use normalized coordinates in reports so results stay independent of display size. Store image dimensions and orientation metadata so a future UI can project boxes back onto thumbnails.

## Photo Analysis

Photo analysis should use downscaled images by default, not full-resolution originals.

Recommended first version:

- Request an image representation suitable for analysis, capped to a maximum long edge such as 1600 or 2048 pixels.
- Run face rectangles first.
- Run landmarks and quality only for detected faces.
- Store results in the face-analysis index.
- Mark unsupported or failed assets without stopping the run.

The full original export path remains untouched. Face analysis may read from Photos or from already exported files, but should not rewrite exported files.

## Video Analysis

Video analysis must be optional and disabled by default.

Recommended first experiment:

- Analyze videos only when the user opts in.
- Extract frames at fixed intervals such as every 3 seconds.
- Apply a per-video cap such as 100 frames.
- Decode frames with a maximum size limit.
- Run face rectangles on sampled frames.
- Run landmarks only on frames where faces are detected.
- Store timestamped observations.

The UI must state that video results are sampled:

> Video analysis uses sampled frames and may miss faces between sampled timestamps.

Do not attempt in the first version:

- Every-frame analysis.
- Person tracking across timestamps.
- Measuring exact on-screen duration of a person.
- Person identity clustering.

## Resource Controls

Default to a conservative resource profile.

Low resource mode:

- Photos only by default.
- 1 analysis task at a time.
- Smaller image size cap.
- Video disabled unless manually enabled.
- Longer frame interval for videos.

Balanced mode:

- 1-2 concurrent photo analysis tasks.
- Optional video sampling.
- Moderate image size cap.

Faster mode:

- More concurrency.
- Shorter video frame interval.
- Only available after an explicit warning.

All modes require:

- Cancel support.
- Progress updates.
- Periodic index writes.
- Resume behavior that skips unchanged already analyzed assets.

## Resume And Idempotency

The experiment should avoid reanalyzing unchanged assets.

Recommended skip key:

- Photos asset local identifier.
- Resource identifier or original filename.
- Media type.
- Modification date when available.
- File size / hash when available.
- Analysis settings version.

If the asset or settings changed, analyze again and record a new result.

## UI Design

Add a separate **Face Analysis** panel below or beside the export results area.

The panel should show:

- Status: idle, analyzing, canceled, finished, failed.
- Settings summary: photos only / videos included, sampling interval, max frames per video, resource mode.
- Progress: analyzed assets, skipped assets, failed assets, faces detected.
- Photo results: photos with faces, photos without faces, failures.
- Video results: videos with sampled-face hits, sampled timestamps, videos skipped or failed.
- Report actions: reveal face-analysis reports, open JSON, open CSV.

Avoid showing face thumbnails or overlays in the first experiment unless we explicitly decide to handle privacy-sensitive previews.

## Privacy And Safety

This feature handles biometric-adjacent data. Keep it local and transparent.

Rules:

- No network calls.
- No cloud inference.
- No persistence outside the selected archive support directory.
- No person names.
- No automatic identity grouping.
- No Photos mutation.
- Reports are plain files controlled by the user.

The UI should explain that results are local analysis metadata and may include face locations.

## Error Handling

Record per-asset failures:

- Photos authorization missing.
- Image request failed.
- Video resource unavailable.
- Frame decode failed.
- Vision request failed.
- Unsupported format.
- User canceled.

Run-level failures should not destroy partial results. A later run can continue from the index.

## Testing Strategy

Core unit tests:

- Face-analysis settings encode/decode.
- Skip-key logic for unchanged assets.
- Summary count aggregation.
- CSV escaping and formula neutralization for new reports.
- Video timestamp sampling plan.

Integration tests with test doubles:

- Analyzer records no-face, one-face, multi-face, and failed assets.
- Canceled runs persist partial results.
- Resume skips previously analyzed records.

Manual verification:

- Run on a tiny Photos test library.
- Run on a folder of exported test files if a file-based test mode is added.
- Confirm CPU stays bounded in low-resource mode.
- Confirm cancel stops promptly.

## Recommended Implementation Slices

1. **Face analysis data model and reports**
   Add types and report writing only. No Vision integration yet.

2. **Photo-only analyzer prototype**
   Add a small Vision-backed analyzer for still images, behind an explicit UI action.

3. **Resume and low-resource controls**
   Add persisted index, cancellation, and settings.

4. **Video sampling prototype**
   Add optional sampled video frame analysis using AVFoundation.

5. **UI result review**
   Add summary and report actions. Avoid thumbnail overlays in the first version.

## Success Criteria For The Experiment

The experiment is worth continuing if:

- Photo face detection works locally on a small library.
- The app stays responsive during low-resource mode.
- Cancel and resume work.
- Reports are understandable.
- Video sampling can process short videos without excessive CPU or memory.
- The feature does not affect the original export flow.

The experiment should be stopped or redesigned if:

- Vision results are too slow for practical use even with sampling.
- Video decoding creates unacceptable resource spikes.
- Reports are too noisy to be useful.
- Users expect person identity recognition, which this design intentionally does not provide.
