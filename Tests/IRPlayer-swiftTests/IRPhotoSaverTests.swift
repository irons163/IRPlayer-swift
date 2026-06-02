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

    func testDiagnosticMessageWrapperMatchesPolicy() {
        XCTAssertEqual(IRPhotoSaver.diagnosticMessage(for: .permissionNotGranted),
                       IRPhotoSaverPolicy.diagnosticMessage(for: .permissionNotGranted))
        XCTAssertEqual(IRPhotoSaver.diagnosticMessage(for: .albumUnavailable),
                       IRPhotoSaverPolicy.diagnosticMessage(for: .albumUnavailable))
        XCTAssertNil(IRPhotoSaverPolicy.diagnosticMessage(for: .permissionNotGranted))
    }

    func testDiagnosticWriterWrapperMatchesPolicy() {
        let wrapperOutput = captureStandardOutput {
            IRPhotoSaver.writeDiagnostic(for: .permissionNotGranted)
        }
        let policyOutput = captureStandardOutput {
            IRPhotoSaverPolicy.writeDiagnostic(for: .permissionNotGranted)
        }

        XCTAssertEqual(wrapperOutput, policyOutput)
    }
}
