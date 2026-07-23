import XCTest
@testable import IRPlayer_swift

final class IRFFmpegBootstrapTests: XCTestCase {
    func testConcurrentInitializationIsSafeAndIdempotent() {
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            IRFFmpegBootstrap.initializeIfNeeded()
        }

        IRFFmpegBootstrap.initializeIfNeeded()
    }
}
