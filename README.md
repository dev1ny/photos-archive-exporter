# Photos Archive Exporter

Photos Archive Exporter 是一个原生 macOS 工具，用于从 Apple「照片」应用当前正在使用的图库中，安全导出照片和视频的原始资源，并整理成普通文件夹归档。

这个项目的第一目标是：**可靠完成全量备份，不修改 Photos 图库，不自动删除任何重复内容**。

## 核心能力

- 从当前 Apple Photos 图库读取资源。
- 导出原始资源，而不是编辑后的预览图或缩略图。
- 支持 PhotoKit 暴露的照片、视频、Live Photo 配套视频、RAW/JPEG 资源。
- Live Photo 会按 PhotoKit 原始资源保留为同一资产下的照片资源和 paired video 资源；报告会把 paired video 标记为 video，方便后续按 Apple 的原始组成重新分发或整理。
- 按拍摄日期整理为 `年 / 年月 / 年月日` 目录。
- 文件名使用 `拍摄日期时间 + 原始文件名`。
- 支持安全重复运行：已经导出的同一 Photos 资源会跳过。
- 支持增量备份：先校验归档索引和目标文件，只导出新资源、缺失文件、变化文件或无法验证的资源。
- 保留真实重复资源：不同 Photos 资产即使文件内容相同，也会被保留为独立文件。
- 生成 JSON / CSV 报告，用于审计、排错和增量备份。
- 导出完成后在 App 内显示本次运行结果，包括失败、警告、重复资源和改名冲突。
- 扫描、全量导出、增量备份和 Face Analysis 会显示进度条、已处理数量和百分比。
- 可对本次已导出的图片运行本地 Face Analysis，统计检测到的人脸数量并生成 JSON / CSV 报告。
- 带有 macOS App 图标。
- 生成 macOS 通用版 App，支持 Apple silicon 和 Intel 芯片。

## 下载

请到 GitHub Releases 下载最新版：

```text
PhotosArchiveExporter-v0.3.1-macos-universal.zip
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
6. 首次归档建议点击 `Start Full Export`，开始全量导出。
7. 后续归档可点击 `Incremental Backup`，只导出新资源、缺失文件、变化文件或无法验证的资源。
8. 导出完成后，在 App 内查看本次运行结果，并在目标目录中查看照片归档和 `_photos_archive_exporter` 报告目录。
9. 如需本地人脸检测，点击 `Analyze Exported Photos`，对本次已导出的图片生成 Face Analysis 报告。

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
    archive-index.sqlite
    export-runs/
      2026-05-04T20-30-00Z/
        2026-05-04T20-30-00Z-resources.csv
        2026-05-04T20-30-00Z-errors.csv
        2026-05-04T20-30-00Z-duplicates.csv
        2026-05-04T20-30-00Z-incremental-plan.csv
    face-analysis-index.json
    face-analysis-runs/
      2026-05-08T05-30-00Z/
        2026-05-08T05-30-00Z-summary.json
        2026-05-08T05-30-00Z-assets.csv
        2026-05-08T05-30-00Z-faces.csv
        2026-05-08T05-30-00Z-errors.csv
```

报告用途：

- `archive-index.sqlite`：归档索引，用于安全重复运行和增量备份。旧版 `archive-index.json` 会在首次读取时迁移到 SQLite。
- `resources.csv`：本次运行每个资源的导出记录。
- `errors.csv`：失败资源和错误原因。
- `duplicates.csv`：强重复报告，基于 SHA-256 哈希，不会自动删除任何文件。
- `incremental-plan.csv`：增量备份运行时的预检计划，记录每个资源是跳过、导出、补回缺失文件、重新导出变化文件还是因无法验证而导出。
- `face-analysis-index.json`：本地图片人脸检测索引。
- `face-analysis-runs/`：每次 Face Analysis 的 summary、assets、faces 和 errors CSV / JSON 报告。

App 会在导出完成后读取同一批导出记录并显示本次运行结果，帮助你快速看到：

- 哪些资源导出失败。
- 哪些资源存在元数据警告。
- 哪些资源内容重复。
- 哪些资源因为目标路径冲突而被安全改名。

CSV 输出会处理逗号、引号、换行，并防止表格软件公式注入。

## Incremental Backup

`Incremental Backup` 会按批读取目标目录中的 `_photos_archive_exporter/archive-index.sqlite`，并逐项校验旧记录对应的目标文件：

- 如果同一 Photos 资源的目标文件仍存在，文件大小和 SHA-256 都匹配，则本次直接记录为 `skippedExisting`，不再从 PhotoKit 写出临时文件。
- 如果索引里没有这个资源，则作为新资源导出。
- 如果目标文件缺失，则重新导出补回。
- 如果目标文件大小或 SHA-256 与索引不一致，则重新导出并保留冲突安全命名规则。
- 如果旧记录缺少可验证的 hash 或文件大小，则重新导出。

每次增量运行仍会写入 `resources.csv`、`errors.csv`、`duplicates.csv` 和 `incremental-plan.csv`，并把本次 skipped / exported / failed / renamed 统计显示在 App 内。

## 大图库注意事项

针对超大 Photos 图库，当前版本已经做了几项保护：

- `archive-index.sqlite` 会存储为每个 Photos 资源一条最新有效记录，重复增量运行不会把大量 `skippedExisting` 记录无限追加进索引。
- 旧版 `archive-index.json` 会自动迁移到 SQLite；迁移完成后，后续运行只按当前批次查询相关旧记录。
- 扫描后的导出和增量规划按批处理，每批完成后立刻写回 SQLite，减少中途失败时丢失进度的风险。
- 导出、增量备份和 Face Analysis 会按批推进进度条，长时间运行时可以看到当前处理数量和百分比。
- 导出时用索引化的 `(assetLocalIdentifier, resourceIdentifier, destinationPath, sha256)` 查找旧记录，避免随着历史记录变多出现二次方级别的查找成本。
- CSV 报告使用流式写出，不再把整份 CSV 先拼成一个超大字符串。
- Face Analysis 会按 `imageLongEdgeLimit` 下采样后再交给 Vision，避免直接解码超大原图。
- App 顶部统计在导出完成时计算一次，避免 SwiftUI 反复扫描本次记录数组。

仍需注意：扫描阶段目前仍会把当前 Photos 图库的可导出资源描述符保存在内存中；最终 UI 统计和 CSV 报告也会保留本次运行记录。对百万级资源或上 TB 归档，首次全量导出主要受磁盘空间、PhotoKit 读取速度和目标盘写入速度影响；增量备份若选择严格 hash 校验，仍可能读取大量已有归档文件。后续进一步优化的方向，是把 PhotoKit 扫描枚举和报告生成也继续下沉为分页/流式 pipeline。

## Face Analysis

Face Analysis 是导出后的可选本地分析流程：

- 只分析本次运行记录中可用的图片文件，包括增量备份中已验证跳过的图片。
- 使用 Apple Vision 在本机检测人脸、脸框和可用的人脸 landmarks。
- 默认按低资源配置下采样图片后分析，减少超大图片的瞬时内存压力。
- 在 App 内显示 analyzed、failed 和 faces detected 统计。
- 报告写入目标目录的 `_photos_archive_exporter/face-analysis-runs/`。
- 不上传图片，不调用云端服务，不识别“是谁”，也不读取 Apple Photos 的人物数据库。

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
dist/PhotosArchiveExporter-v0.3.1-macos-universal.zip
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

- 增量备份仍会扫描当前 Photos 图库；尚未接入 PhotoKit persistent change token 来只扫描变化资产。
- 不会自动从 iCloud 下载未保存在本机的原片。
- 不导出 Photos 中的编辑后版本。
- 不按相簿、人物、地点或事件归档。
- Face Analysis 只做本地人脸检测，不做人物身份识别。
- 暂未提供暂停 / 取消导出按钮。
- 当前 release 未做 Developer ID 公证，不适合作为正式公众发行包。

## 技术栈

- Swift
- SwiftUI
- PhotoKit
- ImageIO
- AVFoundation
- Vision
- CryptoKit
- XCTest
- Swift Package Manager

## 版本

当前版本：`v0.3.1`

## 许可证

尚未选择开源许可证。在添加 LICENSE 文件前，默认保留所有权利。
