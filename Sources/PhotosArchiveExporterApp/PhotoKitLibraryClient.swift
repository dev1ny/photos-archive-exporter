import Combine
import Foundation
import Photos
import PhotosArchiveExporterCore

enum PhotosAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted

    var canRead: Bool {
        self == .authorized || self == .limited
    }
}

@MainActor
final class PhotoKitLibraryClient: ObservableObject {
    @Published private(set) var authorizationState: PhotosAuthorizationState = .notDetermined

    func refreshAuthorizationState() {
        authorizationState = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> PhotosAuthorizationState {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let mapped = Self.map(status)
        authorizationState = mapped
        return mapped
    }

    func scanResources() async throws -> [AssetResourceDescriptor] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard Self.map(status).canRead else {
            throw PhotoKitError.notAuthorized
        }

        return await Task.detached(priority: .userInitiated) {
            var resources: [AssetResourceDescriptor] = []
            let fetch = PHAsset.fetchAssets(with: nil)
            fetch.enumerateObjects { asset, _, _ in
                let assetMediaType = Self.mapMediaType(asset.mediaType)
                let assetResources = PHAssetResource.assetResources(for: asset)
                // Track ordinal *within the (assetID, resourceType, originalFilename) triple*
                // so that two resources sharing all three still get distinct identifiers
                // (e.g. multiple alternatePhotos exported with the same source filename).
                var ordinalForKey: [String: Int] = [:]
                for resource in assetResources where Self.shouldExport(resource) {
                    let resourceType = Self.mapResourceType(resource.type)
                    let triple = "\(asset.localIdentifier)|\(resource.type.rawValue)|\(resource.originalFilename)"
                    let ordinal = ordinalForKey[triple, default: 0]
                    ordinalForKey[triple] = ordinal + 1
                    let identifier = ordinal == 0 ? triple : "\(triple)|\(ordinal)"
                    resources.append(
                        AssetResourceDescriptor(
                            assetLocalIdentifier: asset.localIdentifier,
                            resourceIdentifier: identifier,
                            resourceType: resourceType,
                            mediaType: ResourceMediaTypeResolver.mediaType(for: resourceType, assetMediaType: assetMediaType),
                            originalFilename: resource.originalFilename,
                            uniformTypeIdentifier: resource.uniformTypeIdentifier,
                            assetCreationDate: asset.creationDate
                        )
                    )
                }
            }
            return resources
        }.value
    }

    nonisolated private static func map(_ status: PHAuthorizationStatus) -> PhotosAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    nonisolated private static func mapMediaType(_ mediaType: PHAssetMediaType) -> PhotosArchiveExporterCore.MediaType {
        switch mediaType {
        case .image:
            return .image
        case .video:
            return .video
        default:
            return .other
        }
    }

    nonisolated private static func mapResourceType(_ type: PHAssetResourceType) -> ResourceType {
        switch type {
        case .photo:
            return .photo
        case .video:
            return .video
        case .pairedVideo:
            return .pairedVideo
        case .fullSizePhoto:
            return .fullSizePhoto
        case .fullSizeVideo:
            return .fullSizeVideo
        case .fullSizePairedVideo:
            return .fullSizePairedVideo
        case .alternatePhoto:
            return .alternatePhoto
        default:
            return .other
        }
    }

    nonisolated private static func shouldExport(_ resource: PHAssetResource) -> Bool {
        switch resource.type {
        case .photo, .video, .pairedVideo, .fullSizePhoto, .fullSizeVideo, .fullSizePairedVideo, .alternatePhoto:
            return true
        default:
            return false
        }
    }
}

enum PhotoKitError: LocalizedError {
    case notAuthorized
    case resourceNotFound(String)
    case resourceNotLocallyAvailable(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photos access is not authorized."
        case .resourceNotFound(let identifier):
            return "Could not find Photos resource \(identifier)."
        case .resourceNotLocallyAvailable(let identifier):
            return "Photos resource \(identifier) is only stored in iCloud. Download the original in Photos.app (Photos → Settings → iCloud → Download Originals to this Mac) and retry."
        }
    }
}

/// Resolves descriptors back to live `PHAssetResource` objects, caching a fetch
/// per asset so callers (e.g. `PhotoKitResourceWriter.write`) don't pay an
/// `PHAsset.fetchAssets` + `PHAssetResource.assetResources` round-trip per file.
///
/// Lifetime is intentionally tied to the caller — instantiate one per batch and
/// drop it when the batch is done so a long export never holds the entire
/// library's resource list in memory.
final class PHAssetResourceLookup {
    private var resourcesByAsset: [String: [PHAssetResource]] = [:]

    func resource(for descriptor: AssetResourceDescriptor) -> PHAssetResource? {
        let assetID = descriptor.assetLocalIdentifier
        let resources: [PHAssetResource]
        if let cached = resourcesByAsset[assetID] {
            resources = cached
        } else {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = assets.firstObject else { return nil }
            resources = PHAssetResource.assetResources(for: asset)
            resourcesByAsset[assetID] = resources
        }

        // Replay the same disambiguation used in `scanResources` so descriptors
        // produced there map back to the right `PHAssetResource` even when
        // multiple resources share (type, originalFilename).
        var ordinalForKey: [String: Int] = [:]
        for resource in resources {
            let triple = "\(assetID)|\(resource.type.rawValue)|\(resource.originalFilename)"
            let ordinal = ordinalForKey[triple, default: 0]
            ordinalForKey[triple] = ordinal + 1
            let identifier = ordinal == 0 ? triple : "\(triple)|\(ordinal)"
            if identifier == descriptor.resourceIdentifier {
                return resource
            }
        }
        return nil
    }
}

final class PhotoKitResourceWriter: ResourceWriting {
    /// Per-batch lookup cache. AppModel resets it between batches so the cache
    /// never grows without bound on huge libraries.
    private var lookup: PHAssetResourceLookup

    init(lookup: PHAssetResourceLookup = PHAssetResourceLookup()) {
        self.lookup = lookup
    }

    /// Drop the cached `PHAssetResource` arrays. Call between export batches so
    /// memory pressure stays roughly proportional to the batch size, not the
    /// whole library.
    func resetBatchCache() {
        lookup = PHAssetResourceLookup()
    }

    func write(resource: AssetResourceDescriptor, to temporaryURL: URL) async throws {
        guard let phResource = lookup.resource(for: resource) else {
            throw PhotoKitError.resourceNotFound(resource.resourceIdentifier)
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let options = PHAssetResourceRequestOptions()
                // We intentionally do NOT pull from iCloud — keep exports
                // deterministic, offline-only, and free from surprise data
                // charges. Callers should pre-download originals via Photos.app.
                options.isNetworkAccessAllowed = false
                PHAssetResourceManager.default().writeData(for: phResource, toFile: temporaryURL, options: options) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            // Photos returns a generic PHPhotosError when the original lives
            // only in iCloud. Surface it as a dedicated, user-actionable error
            // so the UI / log can guide the user instead of showing a raw code.
            if Self.indicatesCloudOnlyResource(error) {
                throw PhotoKitError.resourceNotLocallyAvailable(resource.resourceIdentifier)
            }
            throw error
        }
    }

    private static func indicatesCloudOnlyResource(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain {
            // 3164 = networkAccessRequired on supported OS versions; we also
            // match by localized hint so behaviour is robust if Apple changes
            // the numeric code.
            if nsError.code == 3164 { return true }
        }
        let description = nsError.localizedDescription.lowercased()
        return description.contains("network") && description.contains("icloud")
    }
}
