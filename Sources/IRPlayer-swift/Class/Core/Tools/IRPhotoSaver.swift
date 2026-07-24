//
//  IRPhotoSaver.swift
//  IRPlayer
//
//  Created by Phil on 2025/11/24.
//

import Photos
import UIKit

enum IRPhotoSaver {
    enum Failure: Error, Equatable, Sendable {
        case permissionNotGranted
        case albumUnavailable
        case assetSaveFailed
        case cancelled
        case closed
    }

    enum Outcome: Equatable, Sendable {
        case saved
        case failed(Failure)
    }

    enum Destination: Equatable, Sendable {
        case library
        case album(String)
    }

    private static let systemSession = IRPhotoLibrarySession()

    static func save(
        _ image: UIImage,
        toAlbum albumName: String? = nil
    ) {
        _ = systemSession.save(
            image,
            toAlbum: albumName
        ) { outcome in
            guard case .failed(let failure) = outcome else {
                return
            }
            writeDiagnostic(for: failure)
        }
    }

    @discardableResult
    static func save(
        _ image: UIImage,
        toAlbum albumName: String? = nil,
        completion: @escaping IRPhotoLibrarySession.Completion
    ) -> IRPhotoLibrarySession.Token? {
        systemSession.save(
            image,
            toAlbum: albumName,
            completion: completion
        )
    }

    #if IRPhotoSaverDiagnosticOutputEnable
    static let isDiagnosticOutputEnabled = true
    #else
    static let isDiagnosticOutputEnabled = false
    #endif

    static func writeDiagnostic(for failure: Failure) {
        guard let message = diagnosticMessage(for: failure) else {
            return
        }
        print(message)
    }

    static func diagnosticMessage(
        for failure: Failure
    ) -> String? {
        #if IRPhotoSaverDiagnosticOutputEnable
        switch failure {
        case .permissionNotGranted:
            return "IRPhotoSaver: photo-library permission was not granted"
        case .albumUnavailable:
            return "IRPhotoSaver: the destination album is unavailable"
        case .assetSaveFailed:
            return "IRPhotoSaver: the image could not be saved"
        case .cancelled:
            return "IRPhotoSaver: the save request was cancelled"
        case .closed:
            return "IRPhotoSaver: the photo-library session is closed"
        }
        #else
        return nil
        #endif
    }

    static func photoLibraryAccessIsGranted(
        _ status: PHAuthorizationStatus
    ) -> Bool {
        status == .authorized || status == .limited
    }

    static func saveDestination(
        albumName: String?
    ) -> Destination {
        guard let albumName else { return .library }
        let normalizedName = albumName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedName.isEmpty else { return .library }
        return .album(normalizedName)
    }

    static func createdAlbumIdentifier(
        success: Bool,
        placeholderLocalIdentifier: String?
    ) -> String? {
        guard success,
              let placeholderLocalIdentifier,
              !placeholderLocalIdentifier.isEmpty else {
            return nil
        }
        return placeholderLocalIdentifier
    }
}
