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
                for resource in assetResources where Self.shouldExport(resource) {
                    resources.append(
                        AssetResourceDescriptor(
                            assetLocalIdentifier: asset.localIdentifier,
                            resourceIdentifier: "\(asset.localIdentifier)|\(resource.type.rawValue)|\(resource.originalFilename)",
                            resourceType: Self.mapResourceType(resource.type),
                            mediaType: assetMediaType,
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

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photos access is not authorized."
        case .resourceNotFound(let identifier):
            return "Could not find Photos resource \(identifier)."
        }
    }
}

struct PhotoKitResourceWriter: ResourceWriting {
    func write(resource: AssetResourceDescriptor, to temporaryURL: URL) async throws {
        guard let phResource = findResource(for: resource) else {
            throw PhotoKitError.resourceNotFound(resource.resourceIdentifier)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            PHAssetResourceManager.default().writeData(for: phResource, toFile: temporaryURL, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func findResource(for descriptor: AssetResourceDescriptor) -> PHAssetResource? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [descriptor.assetLocalIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            return nil
        }

        return PHAssetResource.assetResources(for: asset).first { resource in
            "\(asset.localIdentifier)|\(resource.type.rawValue)|\(resource.originalFilename)" == descriptor.resourceIdentifier
        }
    }
}
