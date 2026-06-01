//
//  IRPhotoSaverTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import XCTest
@testable import IRPlayer_swift

final class IRPhotoSaverTests: XCTestCase {

    func testDiagnosticsAreSilentByDefault() {
        let output = captureStandardOutput {
            IRPhotoSaver.writeDiagnostic(for: .permissionNotGranted)
            IRPhotoSaver.writeDiagnostic(for: .albumUnavailable)
        }

        XCTAssertEqual(output, "")
    }
}
