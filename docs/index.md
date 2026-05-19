# Photos Archive Exporter

Photos Archive Exporter 是一个原生 macOS 工具，用于从 Apple「照片」当前图库中导出原始照片和视频资源，并整理成按日期归档的普通文件夹。

## 下载

请在 GitHub Release 页面下载：

```text
PhotosArchiveExporter-v0.3.3-macos-universal.zip
```

这个包是 macOS 通用版，支持：

- Apple silicon 芯片：`arm64`
- Intel 芯片：`x86_64`

## 快速使用

1. 在 Apple「照片」中打开你要导出的图库。
2. 启动 `Photos Archive Exporter.app`。
3. 授权 Photos 访问权限。
4. 选择导出目标文件夹。
5. 点击 **Scan Library**。
6. 点击 **Start Full Export**。
7. 运行期间可以在顶部进度条查看已处理数量和百分比。
8. 导出后可点击 **Analyze Exported Photos**，对本次导出的图片运行本地 Face Analysis。

导出完成后，App 会显示本次运行结果，目标目录会包含按年、月、日整理的原始文件，以及 `_photos_archive_exporter/` 报告目录。Face Analysis 报告也会保存在同一支持目录中。

如果运行中断，请重新打开 App，选择同一目标目录，重新扫描后点击 **Incremental Backup**。程序会用 SQLite 索引和 `planned` checkpoint 恢复已经完整落盘的资源，尽量避免从头复制。

## 归档结构

```text
Destination/
  2024/
    2024-08/
      2024-08-16/
        2024-08-16_14-22-10_IMG_1234.HEIC
  _photos_archive_exporter/
    archive-index.sqlite
    export-runs/
```

## 安全原则

Photos Archive Exporter 不会修改 Photos 图库。

它不会删除、编辑或移动 Photos 中的任何资产，也不会自动删除重复文件。重复内容会被保留，并在报告中标记。

导出结果面板会显示失败、警告、重复资源和改名冲突，方便你在打开 CSV 前先快速判断是否需要处理异常。

## 适用场景

- 多年 Photos 图库全量备份。
- 将 Photos 图库迁移为普通文件夹归档。
- 按拍摄日期重新整理照片和视频。
- 保留 Live Photo、视频和 RAW/JPEG 原始资源。
- 对本次导出的图片做本地人脸检测统计。

## 当前限制

- 需要先在 Apple「照片」中切换到目标图库。
- 需要原片已经保存在本机。
- 暂不处理 iCloud 原片自动下载。
- 暂不导出编辑后版本。
- Face Analysis 不做人物身份识别。
