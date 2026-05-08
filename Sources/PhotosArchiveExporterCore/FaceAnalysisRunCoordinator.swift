import Foundation

public struct FaceAnalysisReportURLs: Equatable {
    public let index: URL
    public let summary: URL
    public let assets: URL
    public let faces: URL
    public let errors: URL

    public init(index: URL, summary: URL, assets: URL, faces: URL, errors: URL) {
        self.index = index
        self.summary = summary
        self.assets = assets
        self.faces = faces
        self.errors = errors
    }
}

public struct FaceAnalysisRunCoordinatorResult: Equatable {
    public let summary: FaceAnalysisRunSummary
    public let assetRecords: [FaceAnalysisAssetRecord]
    public let faceObservations: [FaceObservationRecord]
    public let reportURLs: FaceAnalysisReportURLs

    public init(
        summary: FaceAnalysisRunSummary,
        assetRecords: [FaceAnalysisAssetRecord],
        faceObservations: [FaceObservationRecord],
        reportURLs: FaceAnalysisReportURLs
    ) {
        self.summary = summary
        self.assetRecords = assetRecords
        self.faceObservations = faceObservations
        self.reportURLs = reportURLs
    }
}

public struct FaceAnalysisRunCoordinator {
    private let analyzer: FaceAnalysisPhotoAnalyzer

    public init(analyzer: FaceAnalysisPhotoAnalyzer = FaceAnalysisPhotoAnalyzer()) {
        self.analyzer = analyzer
    }

    public func analyzeAndWriteReports(
        records: [ExportRecord],
        destinationRoot: URL,
        runID: String,
        settings: FaceAnalysisSettings,
        analyzedAt: Date = Date(),
        progressHandler: ((Int, Int) async -> Void)? = nil
    ) async throws -> FaceAnalysisRunCoordinatorResult {
        let analyzerResult = await analyzer.analyze(
            records: records,
            runID: runID,
            settings: settings,
            analyzedAt: analyzedAt,
            progressHandler: progressHandler
        )
        let reportStore = FaceAnalysisReportStore(destinationRoot: destinationRoot)
        let previousIndex = try reportStore.loadIndex()
        try reportStore.saveIndex(previousIndex + analyzerResult.assetRecords)

        let summaryURL = try reportStore.writeRunSummary(analyzerResult.summary)
        let assetsURL = try reportStore.writeAssetsCSV(runID: runID, records: analyzerResult.assetRecords)
        let facesURL = try reportStore.writeFacesCSV(runID: runID, faces: analyzerResult.faceObservations)
        let errorsURL = try reportStore.writeErrorsCSV(runID: runID, records: analyzerResult.assetRecords)

        return FaceAnalysisRunCoordinatorResult(
            summary: analyzerResult.summary,
            assetRecords: analyzerResult.assetRecords,
            faceObservations: analyzerResult.faceObservations,
            reportURLs: FaceAnalysisReportURLs(
                index: reportStore.indexURL,
                summary: summaryURL,
                assets: assetsURL,
                faces: facesURL,
                errors: errorsURL
            )
        )
    }
}
