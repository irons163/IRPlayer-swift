//
//  IRPhotoSaverPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRPhotoSaverPolicy {
    static func writeDiagnostic(for failure: IRPhotoSaver.Failure) {
        guard let message = diagnosticMessage(for: failure) else { return }
        print(message)
    }

    static func diagnosticMessage(for _: IRPhotoSaver.Failure) -> String? {
        nil
    }
}
