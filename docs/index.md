# Photos Archive Exporter

A small native macOS utility for exporting original resources from Apple Photos into a dated folder archive.

## Download

Use the latest GitHub Release and download:

```text
PhotosArchiveExporter-v0.1.0-macos-universal.zip
```

The build contains a universal macOS app for both:

- Apple silicon Macs (`arm64`)
- Intel Macs (`x86_64`)

## Quick Start

1. Open the Photos library you want to export in Apple Photos.
2. Launch `Photos Archive Exporter.app`.
3. Authorize Photos access.
4. Choose an archive destination folder.
5. Click **Scan Library**.
6. Click **Start Full Export**.

The app writes original resources into year, month, and day folders, then saves JSON/CSV reports under `_photos_archive_exporter/`.

## Archive Layout

```text
Destination/
  2024/
    2024-08/
      2024-08-16/
        2024-08-16_14-22-10_IMG_1234.HEIC
  _photos_archive_exporter/
    archive-index.json
    export-runs/
```

## Safety

Photos Archive Exporter is read-only against your Photos library. It does not edit, delete, or move assets inside Photos.

Duplicate files are preserved by default. The app reports strong duplicates instead of deleting them.

