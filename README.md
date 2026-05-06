# Photos Archive Exporter

Photos Archive Exporter 是一个原生 macOS 工具，用于从 Apple「照片」应用当前正在使用的图库中，安全导出照片和视频的原始资源，并整理成普通文件夹归档。

这个项目的第一目标是：**可靠完成全量备份，不修改 Photos 图库，不自动删除任何重复内容**。

## 核心能力

- 从当前 Apple Photos 图库读取资源。
- 导出原始资源，而不是编辑后的预览图或缩略图。
- 支持 PhotoKit 暴露的照片、视频、Live Photo 配套视频、RAW/JPEG 资源。
- 按拍摄日期整理为 `年 / 年月 / 年月日` 目录。
- 文件名使用 `拍摄日期时间 + 原始文件名`。
- 支持安全重复运行：已经导出的同一 Photos 资源会跳过。
- 保留真实重复资源：不同 Photos 资产即使文件内容相同，也会被保留为独立文件。
- 生成 JSON / CSV 报告，用于审计、排错和未来增量备份。
- 导出完成后在 App 内显示本次运行结果，包括失败、警告、重复资源和改名冲突。
- 生成 macOS 通用版 App，支持 Apple silicon 和 Intel 芯片。

## 下载

请到 GitHub Releases 下载最新版：

```text
PhotosArchiveExporter-v0.1.1-macos-universal.zip
```

解压后打开：

```text
Photos Archive Exporter.app
```

当前版本使用本地 ad-hoc 签名，适合个人本机使用，还没有做 Developer ID 公证。如果 macOS 首次启动时拦截，请右键 App，选择「打开」，再确认启动。

## 系统要求

- macOS 13 或更高版本
- Apple Photos 图库原片已经保存在本机
- 授予 App 访问 Photos 的权限
- 目标磁盘有足够空间保存导出的原始文件

如果你要导出外置硬盘或旧备份里的 `.photoslibrary`，请先用 Apple「照片」应用打开或切换到该图库，再回到 Photos Archive Exporter 执行扫描和导出。

## 使用流程

1. 打开 Apple「照片」，确认当前图库就是你要导出的图库。
2. 打开 `Photos Archive Exporter.app`。
3. 点击 `Authorize`，授予 Photos 访问权限。
4. 点击 `Choose Folder`，选择导出目标文件夹。
5. 点击 `Scan Library`，扫描当前图库中的可导出资源。
6. 点击 `Start Full Export`，开始全量导出。
7. 导出完成后，在 App 内查看本次运行结果，并在目标目录中查看照片归档和 `_photos_archive_exporter` 报告目录。

## 归档目录结构

导出文件会按照拍摄日期整理：

```text
Destination/
  2024/
    2024-08/
      2024-08-16/
        2024-08-16_14-22-10_IMG_1234.HEIC
        2024-08-16_14-22-10_IMG_1234.MOV
```

时间来源优先级：

1. 原始资源中的 EXIF 拍摄时间。
2. 原始视频中的 QuickTime 创建时间。
3. Photos 资产创建时间。
4. 如果以上都不存在，则使用导出运行时间，并在报告中标记 `missing_capture_date`。

## 报告文件

每个导出目标目录下会生成：

```text
Destination/
  _photos_archive_exporter/
    archive-index.json
    export-runs/
      2026-05-04T20-30-00Z/
        2026-05-04T20-30-00Z-resources.csv
        2026-05-04T20-30-00Z-errors.csv
        2026-05-04T20-30-00Z-duplicates.csv
```

报告用途：

- `archive-index.json`：归档索引，用于安全重复运行和未来增量备份。
- `resources.csv`：本次运行每个资源的导出记录。
- `errors.csv`：失败资源和错误原因。
- `duplicates.csv`：强重复报告，基于 SHA-256 哈希，不会自动删除任何文件。

App 会在导出完成后读取同一批导出记录并显示本次运行结果，帮助你快速看到：

- 哪些资源导出失败。
- 哪些资源存在元数据警告。
- 哪些资源内容重复。
- 哪些资源因为目标路径冲突而被安全改名。

CSV 输出会处理逗号、引号、换行，并防止表格软件公式注入。

## 安全设计

Photos Archive Exporter 对 Photos 图库是只读的：

- 不删除 Photos 资产。
- 不编辑 Photos 资产。
- 不移动 Photos 图库内部文件。
- 不解析 `.photoslibrary` 内部私有数据库。
- 不自动删除重复文件。
- 不默认覆盖目标目录中的已有文件。
- 导出时先写入临时文件，完成后再移动到最终路径。

重复处理规则：

- 如果索引证明同一 Photos 资源已经导出，重复运行时会跳过。
- 如果是不同 Photos 资源，即使文件字节完全一致，也会保留并生成冲突后缀，例如 `__2`。
- 重复报告只用于提示，不做删除或合并。

## 通用版 App 构建

运行测试：

```bash
swift test
```

构建 macOS 通用版 App：

```bash
scripts/build_app.sh
```

输出文件：

```text
dist/Photos Archive Exporter.app
dist/PhotosArchiveExporter-v0.1.1-macos-universal.zip
```

验证架构：

```bash
lipo -info "dist/Photos Archive Exporter.app/Contents/MacOS/PhotosArchiveExporterApp"
```

期望输出包含：

```text
x86_64 arm64
```

验证签名：

```bash
codesign --verify --deep --strict --verbose=2 "dist/Photos Archive Exporter.app"
```

## 当前限制

- v0.1.1 聚焦全量导出和导出结果审计，尚未提供单独的增量备份模式。
- 不会自动从 iCloud 下载未保存在本机的原片。
- 不导出 Photos 中的编辑后版本。
- 不按相簿、人物、地点或事件归档。
- 暂未提供暂停 / 取消导出按钮。
- 当前 release 未做 Developer ID 公证，不适合作为正式公众发行包。

## 技术栈

- Swift
- SwiftUI
- PhotoKit
- ImageIO
- AVFoundation
- CryptoKit
- XCTest
- Swift Package Manager

## 版本

当前版本：`v0.1.1`

## 许可证

尚未选择开源许可证。在添加 LICENSE 文件前，默认保留所有权利。
