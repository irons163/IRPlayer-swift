//
//  IRPhotoLibrarySession.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import Photos
import UIKit

protocol IRPhotoLibraryDriving: AnyObject {
    func requestAuthorization(
        _ completion: @escaping (PHAuthorizationStatus) -> Void
    )

    func existingAlbumIdentifier(
        named name: String
    ) -> String?

    func createAlbum(
        named name: String,
        completion: @escaping (String?) -> Void
    )

    func save(
        _ image: UIImage,
        albumIdentifier: String?,
        completion: @escaping (Bool) -> Void
    )
}

final class IRSystemPhotoLibraryDriver:
    IRPhotoLibraryDriving
{
    func requestAuthorization(
        _ completion: @escaping (PHAuthorizationStatus) -> Void
    ) {
        PHPhotoLibrary.requestAuthorization(
            for: .readWrite,
            handler: completion
        )
    }

    func existingAlbumIdentifier(
        named name: String
    ) -> String? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "title = %@",
            name
        )
        return PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: options
        ).firstObject?.localIdentifier
    }

    func createAlbum(
        named name: String,
        completion: @escaping (String?) -> Void
    ) {
        let capture = IRPhotoLibraryChangeCapture()
        PHPhotoLibrary.shared().performChanges({
            let request =
                PHAssetCollectionChangeRequest
                    .creationRequestForAssetCollection(
                        withTitle: name
                    )
            capture.publish(
                identifier:
                    request.placeholderForCreatedAssetCollection
                        .localIdentifier
            )
        }) { success, _ in
            completion(
                IRPhotoSaver.createdAlbumIdentifier(
                    success: success,
                    placeholderLocalIdentifier:
                        capture.snapshot.identifier
                )
            )
        }
    }

    func save(
        _ image: UIImage,
        albumIdentifier: String?,
        completion: @escaping (Bool) -> Void
    ) {
        let album: PHAssetCollection?
        if let albumIdentifier {
            album = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumIdentifier],
                options: nil
            ).firstObject
            guard album != nil else {
                completion(false)
                return
            }
        } else {
            album = nil
        }

        let capture = IRPhotoLibraryChangeCapture()
        PHPhotoLibrary.shared().performChanges({
            let assetRequest =
                PHAssetChangeRequest.creationRequestForAsset(
                    from: image
                )
            if let album {
                guard let placeholder =
                    assetRequest.placeholderForCreatedAsset,
                    let albumRequest =
                        PHAssetCollectionChangeRequest(for: album)
                else {
                    return
                }
                albumRequest.addAssets([placeholder] as NSArray)
            }
            capture.publishChangeConfigured()
        }) { success, _ in
            completion(
                success &&
                    capture.snapshot.isChangeConfigured
            )
        }
    }
}

final class IRPhotoLibrarySession: @unchecked Sendable {
    enum Phase: Equatable {
        case active
        case closed
    }

    enum RequestStage: Equatable {
        case requestingAuthorization
        case resolvingAlbum(String)
        case waitingForAlbumCreation(String)
        case saving
    }

    struct Token: Hashable, Equatable, Sendable {
        let generation: UInt64
    }

    struct Diagnostics: Equatable {
        let phase: Phase
        let pendingRequestCount: Int
        let requestingAuthorizationCount: Int
        let resolvingAlbumCount: Int
        let waitingForAlbumCreationCount: Int
        let savingCount: Int
        let requestCount: Int
        let succeededRequestCount: Int
        let failedRequestCount: Int
        let cancelledRequestCount: Int
        let rejectedRequestCount: Int
        let albumLookupCount: Int
        let albumCreationCount: Int
        let coalescedAlbumRequestCount: Int
        let assetSaveSubmissionCount: Int
        let ignoredCallbackCount: Int
        let closeCount: Int
    }

    typealias Completion = (IRPhotoSaver.Outcome) -> Void

    private struct PendingRequest {
        let image: UIImage
        let destination: IRPhotoSaver.Destination
        let completion: Completion
        var stage: RequestStage
    }

    private struct SaveSubmission {
        let token: Token
        let image: UIImage
        let albumIdentifier: String?
    }

    private let lock = NSLock()
    private let driver: IRPhotoLibraryDriving

    private var phase: Phase = .active
    private var nextGeneration: UInt64 = 0
    private var pendingRequests: [Token: PendingRequest] = [:]
    private var albumCreationWaiters: [String: [Token]] = [:]
    private var requestCount = 0
    private var succeededRequestCount = 0
    private var failedRequestCount = 0
    private var cancelledRequestCount = 0
    private var rejectedRequestCount = 0
    private var albumLookupCount = 0
    private var albumCreationCount = 0
    private var coalescedAlbumRequestCount = 0
    private var assetSaveSubmissionCount = 0
    private var ignoredCallbackCount = 0
    private var closeCount = 0

    init(
        driver: IRPhotoLibraryDriving =
            IRSystemPhotoLibraryDriver()
    ) {
        self.driver = driver
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }

        var requestingAuthorizationCount = 0
        var resolvingAlbumCount = 0
        var waitingForAlbumCreationCount = 0
        var savingCount = 0
        for request in pendingRequests.values {
            switch request.stage {
            case .requestingAuthorization:
                requestingAuthorizationCount += 1
            case .resolvingAlbum:
                resolvingAlbumCount += 1
            case .waitingForAlbumCreation:
                waitingForAlbumCreationCount += 1
            case .saving:
                savingCount += 1
            }
        }

        return Diagnostics(
            phase: phase,
            pendingRequestCount: pendingRequests.count,
            requestingAuthorizationCount:
                requestingAuthorizationCount,
            resolvingAlbumCount: resolvingAlbumCount,
            waitingForAlbumCreationCount:
                waitingForAlbumCreationCount,
            savingCount: savingCount,
            requestCount: requestCount,
            succeededRequestCount: succeededRequestCount,
            failedRequestCount: failedRequestCount,
            cancelledRequestCount: cancelledRequestCount,
            rejectedRequestCount: rejectedRequestCount,
            albumLookupCount: albumLookupCount,
            albumCreationCount: albumCreationCount,
            coalescedAlbumRequestCount:
                coalescedAlbumRequestCount,
            assetSaveSubmissionCount:
                assetSaveSubmissionCount,
            ignoredCallbackCount: ignoredCallbackCount,
            closeCount: closeCount
        )
    }

    func requestStage(
        for token: Token
    ) -> RequestStage? {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequests[token]?.stage
    }

    @discardableResult
    func save(
        _ image: UIImage,
        toAlbum albumName: String? = nil,
        completion: @escaping Completion
    ) -> Token? {
        let token: Token
        lock.lock()
        guard phase == .active else {
            rejectedRequestCount += 1
            lock.unlock()
            completion(.failed(.closed))
            return nil
        }
        nextGeneration &+= 1
        token = Token(generation: nextGeneration)
        pendingRequests[token] = PendingRequest(
            image: image,
            destination:
                IRPhotoSaver.saveDestination(
                    albumName: albumName
                ),
            completion: completion,
            stage: .requestingAuthorization
        )
        requestCount += 1
        lock.unlock()

        driver.requestAuthorization { [weak self] status in
            self?.handleAuthorization(
                status,
                token: token
            )
        }
        return token
    }

    @discardableResult
    func close() -> Bool {
        invalidate(
            deliverCancellation: true,
            recordClose: true
        )
    }

    deinit {
        _ = invalidate(
            deliverCancellation: false,
            recordClose: false
        )
    }

    private func handleAuthorization(
        _ status: PHAuthorizationStatus,
        token: Token
    ) {
        var completion: Completion?
        var saveSubmission: SaveSubmission?
        var albumName: String?

        lock.lock()
        guard var request = pendingRequests[token],
              request.stage == .requestingAuthorization else {
            ignoredCallbackCount += 1
            lock.unlock()
            return
        }

        guard IRPhotoSaver.photoLibraryAccessIsGranted(status) else {
            completion = removeRequestLocked(
                token,
                outcome: .failed(.permissionNotGranted)
            )
            lock.unlock()
            completion?(.failed(.permissionNotGranted))
            return
        }

        switch request.destination {
        case .library:
            request.stage = .saving
            pendingRequests[token] = request
            assetSaveSubmissionCount += 1
            saveSubmission = SaveSubmission(
                token: token,
                image: request.image,
                albumIdentifier: nil
            )
        case .album(let name):
            request.stage = .resolvingAlbum(name)
            pendingRequests[token] = request
            albumLookupCount += 1
            albumName = name
        }
        lock.unlock()

        if let saveSubmission {
            submit(saveSubmission)
        } else if let albumName {
            let identifier =
                driver.existingAlbumIdentifier(
                    named: albumName
                )
            handleAlbumResolution(
                identifier,
                named: albumName,
                token: token
            )
        }
    }

    private func handleAlbumResolution(
        _ identifier: String?,
        named name: String,
        token: Token
    ) {
        var saveSubmission: SaveSubmission?
        var shouldCreateAlbum = false

        lock.lock()
        guard var request = pendingRequests[token],
              request.stage == .resolvingAlbum(name) else {
            ignoredCallbackCount += 1
            lock.unlock()
            return
        }

        if let identifier = validIdentifier(identifier) {
            request.stage = .saving
            pendingRequests[token] = request
            assetSaveSubmissionCount += 1
            saveSubmission = SaveSubmission(
                token: token,
                image: request.image,
                albumIdentifier: identifier
            )
        } else {
            request.stage = .waitingForAlbumCreation(name)
            pendingRequests[token] = request
            if albumCreationWaiters[name] == nil {
                albumCreationWaiters[name] = [token]
                albumCreationCount += 1
                shouldCreateAlbum = true
            } else {
                albumCreationWaiters[name]?.append(token)
                coalescedAlbumRequestCount += 1
            }
        }
        lock.unlock()

        if let saveSubmission {
            submit(saveSubmission)
        } else if shouldCreateAlbum {
            driver.createAlbum(named: name) { [weak self] in
                self?.handleAlbumCreation(
                    $0,
                    named: name
                )
            }
        }
    }

    private func handleAlbumCreation(
        _ identifier: String?,
        named name: String
    ) {
        var saveSubmissions: [SaveSubmission] = []
        var failureCompletions: [Completion] = []
        let identifier = validIdentifier(identifier)

        lock.lock()
        guard let tokens =
            albumCreationWaiters.removeValue(forKey: name)
        else {
            ignoredCallbackCount += 1
            lock.unlock()
            return
        }

        for token in tokens {
            guard var request = pendingRequests[token],
                  request.stage ==
                    .waitingForAlbumCreation(name) else {
                ignoredCallbackCount += 1
                continue
            }

            if let identifier {
                request.stage = .saving
                pendingRequests[token] = request
                assetSaveSubmissionCount += 1
                saveSubmissions.append(
                    SaveSubmission(
                        token: token,
                        image: request.image,
                        albumIdentifier: identifier
                    )
                )
            } else if let completion = removeRequestLocked(
                token,
                outcome: .failed(.albumUnavailable)
            ) {
                failureCompletions.append(completion)
            }
        }
        lock.unlock()

        failureCompletions.forEach {
            $0(.failed(.albumUnavailable))
        }
        saveSubmissions.forEach(submit)
    }

    private func submit(
        _ submission: SaveSubmission
    ) {
        driver.save(
            submission.image,
            albumIdentifier: submission.albumIdentifier
        ) { [weak self] success in
            self?.handleSaveCompletion(
                success,
                token: submission.token
            )
        }
    }

    private func handleSaveCompletion(
        _ success: Bool,
        token: Token
    ) {
        let outcome: IRPhotoSaver.Outcome =
            success
                ? .saved
                : .failed(.assetSaveFailed)
        let completion: Completion?

        lock.lock()
        guard pendingRequests[token]?.stage == .saving else {
            ignoredCallbackCount += 1
            lock.unlock()
            return
        }
        completion = removeRequestLocked(
            token,
            outcome: outcome
        )
        lock.unlock()

        completion?(outcome)
    }

    private func removeRequestLocked(
        _ token: Token,
        outcome: IRPhotoSaver.Outcome
    ) -> Completion? {
        guard let request =
            pendingRequests.removeValue(forKey: token) else {
            return nil
        }
        switch outcome {
        case .saved:
            succeededRequestCount += 1
        case .failed(.cancelled):
            cancelledRequestCount += 1
        case .failed:
            failedRequestCount += 1
        }
        return request.completion
    }

    private func validIdentifier(
        _ identifier: String?
    ) -> String? {
        IRPhotoSaver.createdAlbumIdentifier(
            success: identifier != nil,
            placeholderLocalIdentifier: identifier
        )
    }

    private func invalidate(
        deliverCancellation: Bool,
        recordClose: Bool
    ) -> Bool {
        let completions: [Completion]

        lock.lock()
        guard phase == .active else {
            lock.unlock()
            return false
        }
        phase = .closed
        if recordClose {
            closeCount += 1
        }
        completions = pendingRequests.values.map(\.completion)
        cancelledRequestCount += pendingRequests.count
        pendingRequests.removeAll(keepingCapacity: false)
        albumCreationWaiters.removeAll(keepingCapacity: false)
        lock.unlock()

        if deliverCancellation {
            completions.forEach {
                $0(.failed(.cancelled))
            }
        }
        return true
    }
}

private final class IRPhotoLibraryChangeCapture:
    @unchecked Sendable
{
    struct Snapshot {
        let identifier: String?
        let isChangeConfigured: Bool
    }

    private let lock = NSLock()
    private var identifier: String?
    private var isChangeConfigured = false

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            identifier: identifier,
            isChangeConfigured: isChangeConfigured
        )
    }

    func publish(identifier: String?) {
        lock.lock()
        self.identifier = identifier
        lock.unlock()
    }

    func publishChangeConfigured() {
        lock.lock()
        isChangeConfigured = true
        lock.unlock()
    }
}
