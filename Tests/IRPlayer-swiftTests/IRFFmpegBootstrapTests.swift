import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFmpegBootstrapTests: XCTestCase {
    func testConcurrentInitializationIsSafeAndIdempotent() {
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            IRFFmpegBootstrap.initializeIfNeeded()
        }

        IRFFmpegBootstrap.initializeIfNeeded()
    }
}
