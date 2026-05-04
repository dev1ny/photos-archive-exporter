# Photos Archive Exporter

Photos Archive Exporter is a native macOS utility for exporting original photo and video resources from the current Apple Photos library into a regular folder archive.

It is designed for safe full-library backups first: it reads from Photos, writes to a destination folder you choose, and never modifies your Photos library.

## What It Does

- Exports original resources exposed by PhotoKit, including photos, videos, Live Photo paired videos, and RAW/JPEG resource pairs.
- Organizes files by capture date:

  ```text
  Destination/
    2024/
      2024-08/
        2024-08-16/
          2024-08-16_14-22-10_IMG_1234.HEIC
  ```

- Uses EXIF / QuickTime capture time when available, then Photos asset creation time as a fallback.
- Preserves distinct duplicate Photos resources by default.
- Skips already-exported resources on reruns when the prior export index proves the same Photos resource was already archived.
- Writes JSON and CSV reports under `_photos_archive_exporter/`.
- Produces a universal macOS app for Apple silicon and Intel Macs.

## Download

Download the latest universal macOS build from the GitHub Releases page:

- `PhotosArchiveExporter-v0.1.0-macos-universal.zip`

After downloading, unzip the archive and open `Photos Archive Exporter.app`.

The current build is ad-hoc signed for local use. If macOS blocks first launch, right-click the app, choose **Open**, and confirm that you want to open it.

## Requirements

- macOS 13 or later
- Apple Photos library with originals stored locally
- Photos permission granted to the app
- Enough free disk space for the exported archive

For an old or external `.photoslibrary`, first open or switch to that library in the Photos app, then run Photos Archive Exporter.

## Safety Model

The app is intentionally conservative:

- It does not delete Photos assets.
- It does not edit Photos assets.
- It does not parse private `.photoslibrary` internals.
- It does not overwrite existing archive files by default.
- It does not remove duplicates automatically.
- It writes temporary files before moving completed exports into place.

## Reports

Each destination gets a support folder:

```text
Destination/
  _photos_archive_exporter/
    archive-index.json
    export-runs/
      <run-id>/
        <run-id>-resources.csv
        <run-id>-errors.csv
        <run-id>-duplicates.csv
```

The index is used for safe reruns and future incremental backup support.

## Build From Source

Run tests:

```bash
swift test
```

Build a universal macOS app:

```bash
scripts/build_app.sh
```

The built app is written to:

```text
dist/Photos Archive Exporter.app
```

Verify the app binary architectures:

```bash
lipo -info "dist/Photos Archive Exporter.app/Contents/MacOS/PhotosArchiveExporterApp"
```

Expected architectures:

```text
x86_64 arm64
```

## Current Limitations

- Full export is implemented first; incremental backup is prepared through the archive index but not exposed as a separate mode.
- iCloud-only originals are not downloaded automatically.
- Edited Photos versions are not exported.
- Album, face, place, and event folder organization are not part of v0.1.0.
- Pause/cancel controls are not yet implemented.

## License

No license has been selected yet. All rights reserved until a license is added.

