//
//  IRPhotoSaver.swift
//  IRPlayer
//
//  Created by Phil on 2025/11/24.
//

import Photos
import UIKit

enum IRPhotoSaver {

    static func save(_ image: UIImage, toAlbum albumName: String? = nil) {
        requestPermission { granted in
            guard granted else {
                print("Photo permission not granted")
                return
            }

            guard let albumName = albumName else {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                })
                return
            }

            fetchOrCreateAlbum(named: albumName) { album in
                guard let album = album else {
                    print("Failed to fetch/create album")
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    let createAsset = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    guard let placeholder = createAsset.placeholderForCreatedAsset else { return }

                    if let albumChange = PHAssetCollectionChangeRequest(for: album) {
                        albumChange.addAssets([placeholder] as NSArray)
                    }
                })
            }
        }
    }

    private static func requestPermission(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            completion(status == .authorized || status == .limited)
        }
    }

    private static func fetchOrCreateAlbum(named name: String,
                                           completion: @escaping (PHAssetCollection?) -> Void) {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", name)
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)

        if let existing = result.firstObject {
            completion(existing)
            return
        }

        var placeholder: PHObjectPlaceholder?

        PHPhotoLibrary.shared().performChanges({
            let create = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = create.placeholderForCreatedAssetCollection
        }) { success, _ in
            guard success, let id = placeholder?.localIdentifier else {
                completion(nil)
                return
            }
            let fetch = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            completion(fetch.firstObject)
        }
    }
}
