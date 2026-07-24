//
//  IRPhotoSaverTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import Photos
import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRPhotoSaverTests: XCTestCase {
    func testDiagnosticsAreSilentByDefault() {
        let output = captureStandardOutput {
            IRPhotoSaver.writeDiagnostic(
                for: .permissionNotGranted
            )
            IRPhotoSaver.writeDiagnostic(
                for: .albumUnavailable
            )
            IRPhotoSaver.writeDiagnostic(
                for: .assetSaveFailed
            )
            IRPhotoSaver.writeDiagnostic(for: .cancelled)
            IRPhotoSaver.writeDiagnostic(for: .closed)
        }

        XCTAssertEqual(output, "")
        XCTAssertFalse(IRPhotoSaver.isDiagnosticOutputEnabled)
        XCTAssertNil(
            IRPhotoSaver.diagnosticMessage(
                for: .permissionNotGranted
            )
        )
    }

    func testAuthorizationAndDestinationValuesNormalizeInput() {
        XCTAssertTrue(
            IRPhotoSaver.photoLibraryAccessIsGranted(.authorized)
        )
        XCTAssertTrue(
            IRPhotoSaver.photoLibraryAccessIsGranted(.limited)
        )
        XCTAssertFalse(
            IRPhotoSaver.photoLibraryAccessIsGranted(.denied)
        )
        XCTAssertFalse(
            IRPhotoSaver.photoLibraryAccessIsGranted(.restricted)
        )
        XCTAssertFalse(
            IRPhotoSaver.photoLibraryAccessIsGranted(
                .notDetermined
            )
        )

        XCTAssertEqual(
            IRPhotoSaver.saveDestination(albumName: nil),
            .library
        )
        XCTAssertEqual(
            IRPhotoSaver.saveDestination(albumName: ""),
            .library
        )
        XCTAssertEqual(
            IRPhotoSaver.saveDestination(albumName: " \n "),
            .library
        )
        XCTAssertEqual(
            IRPhotoSaver.saveDestination(
                albumName: "  Snapshots \n"
            ),
            .album("Snapshots")
        )
    }

    func testAlbumIdentifierRequiresSuccessAndNonemptyValue() {
        XCTAssertNil(
            IRPhotoSaver.createdAlbumIdentifier(
                success: false,
                placeholderLocalIdentifier: "album-id"
            )
        )
        XCTAssertNil(
            IRPhotoSaver.createdAlbumIdentifier(
                success: true,
                placeholderLocalIdentifier: nil
            )
        )
        XCTAssertNil(
            IRPhotoSaver.createdAlbumIdentifier(
                success: true,
                placeholderLocalIdentifier: ""
            )
        )
        XCTAssertEqual(
            IRPhotoSaver.createdAlbumIdentifier(
                success: true,
                placeholderLocalIdentifier: "album-id"
            ),
            "album-id"
        )
    }

    func testPermissionFailureCompletesOnceWithoutDownstreamWork() {
        let driver = ControlledPhotoLibraryDriver()
        let session = IRPhotoLibrarySession(driver: driver)
        var outcomes: [IRPhotoSaver.Outcome] = []

        let token = session.save(UIImage()) {
            outcomes.append($0)
        }

        XCTAssertEqual(
            session.requestStage(for: token!),
            .requestingAuthorization
        )
        XCTAssertEqual(
            session.diagnostics.requestingAuthorizationCount,
            1
        )

        driver.sendAuthorization(.denied)
        driver.sendAuthorization(.authorized)

        XCTAssertEqual(
            outcomes,
            [.failed(.permissionNotGranted)]
        )
        XCTAssertEqual(driver.albumLookups, [])
        XCTAssertEqual(driver.albumCreations, [])
        XCTAssertEqual(driver.saveAlbumIdentifiers, [])
        XCTAssertNil(session.requestStage(for: token!))
        XCTAssertEqual(session.diagnostics.requestCount, 1)
        XCTAssertEqual(session.diagnostics.failedRequestCount, 1)
        XCTAssertEqual(session.diagnostics.ignoredCallbackCount, 1)
        XCTAssertEqual(session.diagnostics.pendingRequestCount, 0)
    }

    func testSynchronousLibrarySavePublishesStagesBeforeCallbacks() {
        let driver = ImmediatePhotoLibraryDriver(
            authorizationStatus: .authorized,
            albumIdentifier: nil,
            createdAlbumIdentifier: nil,
            saveResult: true
        )
        let session = IRPhotoLibrarySession(driver: driver)
        var outcomes: [IRPhotoSaver.Outcome] = []

        let token = session.save(UIImage()) {
            outcomes.append($0)
        }

        XCTAssertNotNil(token)
        XCTAssertEqual(outcomes, [.saved])
        XCTAssertEqual(driver.authorizationCount, 1)
        XCTAssertEqual(driver.saveAlbumIdentifiers, [nil])
        XCTAssertEqual(session.diagnostics.requestCount, 1)
        XCTAssertEqual(
            session.diagnostics.succeededRequestCount,
            1
        )
        XCTAssertEqual(
            session.diagnostics.assetSaveSubmissionCount,
            1
        )
        XCTAssertEqual(session.diagnostics.pendingRequestCount, 0)
        XCTAssertEqual(session.diagnostics.ignoredCallbackCount, 0)
    }

    func testDriverAndClientCallbacksMayReenterSessionOutsideLock() {
        let driver = ImmediatePhotoLibraryDriver(
            authorizationStatus: .authorized,
            albumIdentifier: "album-id",
            createdAlbumIdentifier: nil,
            saveResult: true
        )
        var session: IRPhotoLibrarySession!
        var outcome: IRPhotoSaver.Outcome?
        var didClose = false
        driver.onAuthorization = {
            XCTAssertEqual(
                session.diagnostics.requestingAuthorizationCount,
                1
            )
        }
        driver.onAlbumLookup = {
            XCTAssertEqual(
                session.diagnostics.resolvingAlbumCount,
                1
            )
        }
        driver.onSave = {
            XCTAssertEqual(session.diagnostics.savingCount, 1)
        }
        session = IRPhotoLibrarySession(driver: driver)

        let token = session.save(
            UIImage(),
            toAlbum: "Snapshots"
        ) {
            outcome = $0
            didClose = session.close()
        }

        XCTAssertNotNil(token)
        XCTAssertEqual(outcome, .saved)
        XCTAssertTrue(didClose)
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertEqual(session.diagnostics.pendingRequestCount, 0)
        XCTAssertEqual(session.diagnostics.closeCount, 1)
    }

    func testDuplicateAuthorizationAndSaveCallbacksAreInert() {
        let driver = ControlledPhotoLibraryDriver()
        let session = IRPhotoLibrarySession(driver: driver)
        var outcomes: [IRPhotoSaver.Outcome] = []

        _ = session.save(UIImage()) {
            outcomes.append($0)
        }
        driver.sendAuthorization(.authorized)

        XCTAssertEqual(driver.saveAlbumIdentifiers, [nil])
        driver.sendAuthorization(.authorized)
        XCTAssertEqual(driver.saveAlbumIdentifiers, [nil])

        driver.sendSave(success: false)
        driver.sendSave(success: true)

        XCTAssertEqual(
            outcomes,
            [.failed(.assetSaveFailed)]
        )
        XCTAssertEqual(session.diagnostics.failedRequestCount, 1)
        XCTAssertEqual(session.diagnostics.ignoredCallbackCount, 2)
        XCTAssertEqual(
            session.diagnostics.assetSaveSubmissionCount,
            1
        )
    }

    func testExistingAlbumSkipsCreationAndSavesToIdentifier() {
        let driver = ControlledPhotoLibraryDriver()
        driver.existingAlbums["Snapshots"] = "existing-id"
        let session = IRPhotoLibrarySession(driver: driver)
        var outcomes: [IRPhotoSaver.Outcome] = []

        let token = session.save(
            UIImage(),
            toAlbum: " Snapshots "
        ) {
            outcomes.append($0)
        }
        driver.sendAuthorization(.limited)

        XCTAssertEqual(driver.albumLookups, ["Snapshots"])
        XCTAssertEqual(driver.albumCreations, [])
        XCTAssertEqual(
            driver.saveAlbumIdentifiers,
            ["existing-id"]
        )
        XCTAssertEqual(
            session.requestStage(for: token!),
            .saving
        )

        driver.sendSave(success: true)

        XCTAssertEqual(outcomes, [.saved])
        XCTAssertEqual(session.diagnostics.albumLookupCount, 1)
        XCTAssertEqual(session.diagnostics.albumCreationCount, 0)
        XCTAssertEqual(
            session.diagnostics.succeededRequestCount,
            1
        )
    }

    func testMissingAlbumCreationAdvancesRequestToSave() {
        let driver = ControlledPhotoLibraryDriver()
        let session = IRPhotoLibrarySession(driver: driver)
        var outcomes: [IRPhotoSaver.Outcome] = []

        let token = session.save(
            UIImage(),
            toAlbum: "Snapshots"
        ) {
            outcomes.append($0)
        }
        driver.sendAuthorization(.authorized)

        XCTAssertEqual(driver.albumLookups, ["Snapshots"])
        XCTAssertEqual(driver.albumCreations, ["Snapshots"])
        XCTAssertEqual(
            session.requestStage(for: token!),
            .waitingForAlbumCreation("Snapshots")
        )
        XCTAssertEqual(
            session.diagnostics.waitingForAlbumCreationCount,
            1
        )

        driver.sendAlbumCreation(identifier: "new-id")

        XCTAssertEqual(
            driver.saveAlbumIdentifiers,
            ["new-id"]
        )
        XCTAssertEqual(
            session.requestStage(for: token!),
            .saving
        )

        driver.sendSave(success: true)

        XCTAssertEqual(outcomes, [.saved])
        XCTAssertEqual(session.diagnostics.albumCreationCount, 1)
        XCTAssertEqual(
            session.diagnostics.assetSaveSubmissionCount,
            1
        )
    }

    func testAlbumCreationFailureAndDuplicateCallbackCompleteOnce() {
        let driver = ControlledPhotoLibraryDriver()
        let session = IRPhotoLibrarySession(driver: driver)
        var outcomes: [IRPhotoSaver.Outcome] = []

        _ = session.save(
            UIImage(),
            toAlbum: "Snapshots"
        ) {
            outcomes.append($0)
        }
        driver.sendAuthorization(.authorized)
        driver.sendAlbumCreation(identifier: nil)
        driver.sendAlbumCreation(identifier: "late-id")

        XCTAssertEqual(
            outcomes,
            [.failed(.albumUnavailable)]
        )
        XCTAssertEqual(driver.saveAlbumIdentifiers, [])
        XCTAssertEqual(session.diagnostics.failedRequestCount, 1)
        XCTAssertEqual(session.diagnostics.ignoredCallbackCount, 1)
        XCTAssertEqual(session.diagnostics.pendingRequestCount, 0)
    }

    func testOutOfOrderMissingAlbumRequestsCoalesceCreation() {
        let driver = ControlledPhotoLibraryDriver()
        let session = IRPhotoLibrarySession(driver: driver)
        var outcomes: [IRPhotoSaver.Outcome] = []

        let first = session.save(
            UIImage(),
            toAlbum: "Snapshots"
        ) {
            outcomes.append($0)
        }
        let second = session.save(
            UIImage(),
            toAlbum: "Snapshots"
        ) {
            outcomes.append($0)
        }
        driver.sendAuthorization(.authorized, at: 1)
        driver.sendAuthorization(.authorized, at: 0)

        XCTAssertEqual(
            session.requestStage(for: first!),
            .waitingForAlbumCreation("Snapshots")
        )
        XCTAssertEqual(
            session.requestStage(for: second!),
            .waitingForAlbumCreation("Snapshots")
        )
        XCTAssertEqual(driver.albumCreations, ["Snapshots"])
        XCTAssertEqual(session.diagnostics.albumLookupCount, 2)
        XCTAssertEqual(session.diagnostics.albumCreationCount, 1)
        XCTAssertEqual(
            session.diagnostics.coalescedAlbumRequestCount,
            1
        )

        driver.sendAlbumCreation(identifier: "shared-id")

        XCTAssertEqual(
            driver.saveAlbumIdentifiers,
            ["shared-id", "shared-id"]
        )
        driver.sendSave(success: true, at: 0)
        driver.sendSave(success: true, at: 1)
        driver.sendAlbumCreation(identifier: "duplicate-id")

        XCTAssertEqual(outcomes, [.saved, .saved])
        XCTAssertEqual(
            session.diagnostics.succeededRequestCount,
            2
        )
        XCTAssertEqual(session.diagnostics.ignoredCallbackCount, 1)
    }

    func testCloseCancelsPendingRequestsAndRejectsLateWork() {
        let driver = ControlledPhotoLibraryDriver()
        let session = IRPhotoLibrarySession(driver: driver)
        var outcomes: [IRPhotoSaver.Outcome] = []

        _ = session.save(UIImage()) {
            outcomes.append($0)
        }
        _ = session.save(
            UIImage(),
            toAlbum: "Snapshots"
        ) {
            outcomes.append($0)
        }

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        XCTAssertNil(
            session.save(UIImage()) {
                outcomes.append($0)
            }
        )
        driver.sendAuthorization(.authorized, at: 0)
        driver.sendAuthorization(.authorized, at: 1)

        XCTAssertEqual(
            outcomes,
            [
                .failed(.cancelled),
                .failed(.cancelled),
                .failed(.closed)
            ]
        )
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertEqual(session.diagnostics.pendingRequestCount, 0)
        XCTAssertEqual(session.diagnostics.requestCount, 2)
        XCTAssertEqual(
            session.diagnostics.cancelledRequestCount,
            2
        )
        XCTAssertEqual(session.diagnostics.rejectedRequestCount, 1)
        XCTAssertEqual(session.diagnostics.ignoredCallbackCount, 2)
        XCTAssertEqual(session.diagnostics.closeCount, 1)
        XCTAssertEqual(driver.saveAlbumIdentifiers, [])
    }

    func testDeinitializationSilentlyReleasesPendingRequests() {
        let driver = ControlledPhotoLibraryDriver()
        weak var weakSession: IRPhotoLibrarySession?
        var completionCount = 0

        autoreleasepool {
            var session: IRPhotoLibrarySession? =
                IRPhotoLibrarySession(driver: driver)
            weakSession = session
            _ = session?.save(UIImage()) { _ in
                completionCount += 1
            }
            session = nil
        }

        XCTAssertNil(weakSession)
        XCTAssertEqual(completionCount, 0)
        driver.sendAuthorization(.authorized)
        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(driver.saveAlbumIdentifiers, [])
    }

    func testConcurrentRequestCallbackAndCloseRemainCoherent() {
        let driver = ConcurrentPhotoLibraryDriver()
        let session = IRPhotoLibrarySession(driver: driver)
        let completion = expectation(
            description: "every save reaches one terminal outcome"
        )
        completion.expectedFulfillmentCount = 400
        let recorder = PhotoOutcomeRecorder()
        let image = UIImage()

        DispatchQueue.concurrentPerform(iterations: 400) {
            index in
            if index == 200 {
                _ = session.close()
            }
            _ = session.save(image) {
                recorder.append($0)
                completion.fulfill()
            }
        }

        wait(for: [completion], timeout: 10)
        XCTAssertEqual(
            driver.waitForCallbacks(timeout: .now() + 5),
            .success
        )
        _ = session.close()

        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.phase, .closed)
        XCTAssertEqual(diagnostics.pendingRequestCount, 0)
        XCTAssertEqual(
            diagnostics.requestCount +
                diagnostics.rejectedRequestCount,
            400
        )
        XCTAssertEqual(
            diagnostics.succeededRequestCount +
                diagnostics.failedRequestCount +
                diagnostics.cancelledRequestCount,
            diagnostics.requestCount
        )
        XCTAssertEqual(recorder.count, 400)
    }
}

private final class ControlledPhotoLibraryDriver:
    IRPhotoLibraryDriving
{
    private struct SaveCallback {
        let albumIdentifier: String?
        let completion: (Bool) -> Void
    }

    private struct AlbumCreationCallback {
        let name: String
        let completion: (String?) -> Void
    }

    private let lock = NSLock()
    private var authorizationCallbacks:
        [(PHAuthorizationStatus) -> Void] = []
    private var storedAlbumLookups: [String] = []
    private var storedAlbumCreations:
        [AlbumCreationCallback] = []
    private var saveCallbacks: [SaveCallback] = []
    var existingAlbums: [String: String] = [:]

    var albumLookups: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedAlbumLookups
    }

    var albumCreations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedAlbumCreations.map(\.name)
    }

    var saveAlbumIdentifiers: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return saveCallbacks.map(\.albumIdentifier)
    }

    func requestAuthorization(
        _ completion: @escaping (PHAuthorizationStatus) -> Void
    ) {
        lock.lock()
        authorizationCallbacks.append(completion)
        lock.unlock()
    }

    func existingAlbumIdentifier(
        named name: String
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        storedAlbumLookups.append(name)
        return existingAlbums[name]
    }

    func createAlbum(
        named name: String,
        completion: @escaping (String?) -> Void
    ) {
        lock.lock()
        storedAlbumCreations.append(
            AlbumCreationCallback(
                name: name,
                completion: completion
            )
        )
        lock.unlock()
    }

    func save(
        _ image: UIImage,
        albumIdentifier: String?,
        completion: @escaping (Bool) -> Void
    ) {
        lock.lock()
        saveCallbacks.append(
            SaveCallback(
                albumIdentifier: albumIdentifier,
                completion: completion
            )
        )
        lock.unlock()
    }

    func sendAuthorization(
        _ status: PHAuthorizationStatus,
        at index: Int = 0
    ) {
        let callback: (PHAuthorizationStatus) -> Void
        lock.lock()
        callback = authorizationCallbacks[index]
        lock.unlock()
        callback(status)
    }

    func sendAlbumCreation(
        identifier: String?,
        at index: Int = 0
    ) {
        let callback: (String?) -> Void
        lock.lock()
        callback = storedAlbumCreations[index].completion
        lock.unlock()
        callback(identifier)
    }

    func sendSave(
        success: Bool,
        at index: Int = 0
    ) {
        let callback: (Bool) -> Void
        lock.lock()
        callback = saveCallbacks[index].completion
        lock.unlock()
        callback(success)
    }
}

private final class ImmediatePhotoLibraryDriver:
    IRPhotoLibraryDriving
{
    let authorizationStatus: PHAuthorizationStatus
    let albumIdentifier: String?
    let createdAlbumIdentifier: String?
    let saveResult: Bool
    var onAuthorization: (() -> Void)?
    var onAlbumLookup: (() -> Void)?
    var onSave: (() -> Void)?
    private(set) var authorizationCount = 0
    private(set) var saveAlbumIdentifiers: [String?] = []

    init(
        authorizationStatus: PHAuthorizationStatus,
        albumIdentifier: String?,
        createdAlbumIdentifier: String?,
        saveResult: Bool
    ) {
        self.authorizationStatus = authorizationStatus
        self.albumIdentifier = albumIdentifier
        self.createdAlbumIdentifier = createdAlbumIdentifier
        self.saveResult = saveResult
    }

    func requestAuthorization(
        _ completion: @escaping (PHAuthorizationStatus) -> Void
    ) {
        authorizationCount += 1
        onAuthorization?()
        completion(authorizationStatus)
    }

    func existingAlbumIdentifier(
        named name: String
    ) -> String? {
        onAlbumLookup?()
        return albumIdentifier
    }

    func createAlbum(
        named name: String,
        completion: @escaping (String?) -> Void
    ) {
        completion(createdAlbumIdentifier)
    }

    func save(
        _ image: UIImage,
        albumIdentifier: String?,
        completion: @escaping (Bool) -> Void
    ) {
        saveAlbumIdentifiers.append(albumIdentifier)
        onSave?()
        completion(saveResult)
    }
}

private final class ConcurrentPhotoLibraryDriver:
    IRPhotoLibraryDriving
{
    private let callbackGroup = DispatchGroup()

    func requestAuthorization(
        _ completion: @escaping (PHAuthorizationStatus) -> Void
    ) {
        callbackGroup.enter()
        DispatchQueue.global().async {
            completion(.authorized)
            self.callbackGroup.leave()
        }
    }

    func existingAlbumIdentifier(
        named name: String
    ) -> String? {
        nil
    }

    func createAlbum(
        named name: String,
        completion: @escaping (String?) -> Void
    ) {
        callbackGroup.enter()
        DispatchQueue.global().async {
            completion("album-id")
            self.callbackGroup.leave()
        }
    }

    func save(
        _ image: UIImage,
        albumIdentifier: String?,
        completion: @escaping (Bool) -> Void
    ) {
        callbackGroup.enter()
        DispatchQueue.global().async {
            completion(true)
            self.callbackGroup.leave()
        }
    }

    func waitForCallbacks(
        timeout: DispatchTime
    ) -> DispatchTimeoutResult {
        callbackGroup.wait(timeout: timeout)
    }
}

private final class PhotoOutcomeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [IRPhotoSaver.Outcome] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return outcomes.count
    }

    func append(_ outcome: IRPhotoSaver.Outcome) {
        lock.lock()
        outcomes.append(outcome)
        lock.unlock()
    }
}
