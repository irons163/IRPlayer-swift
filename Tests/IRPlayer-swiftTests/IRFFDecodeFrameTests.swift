import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFDecodeFrameTests: XCTestCase {
    func testAllocationFailureDoesNotPublishOwner() {
        let freeCount = LockedDecoderResourceValue(0)
        let runtime = IRFFDecodeFrameRuntime(
            allocateFrame: { nil },
            freeFrame: { frame in
                freeCount.withValue { $0 += 1 }
                frame = nil
            }
        )

        XCTAssertNil(
            IRFFDecodeFrame(runtime: runtime)
        )
        XCTAssertEqual(freeCount.value, 0)
    }

    func testOwnerBorrowsFrameAndClosesExactlyOnce() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let frameAddress = 0x1000
        let owner = try XCTUnwrap(
            IRFFDecodeFrame(
                runtime: makeRuntime(
                    frameAddress: frameAddress,
                    events: events
                )
            )
        )
        var borrowedAddress: Int?

        XCTAssertTrue(
            owner.withFrame { frame in
                borrowedAddress = Int(
                    bitPattern:
                        UnsafeMutableRawPointer(frame)
                )
                return true
            }
        )
        XCTAssertEqual(borrowedAddress, frameAddress)
        XCTAssertEqual(
            owner.diagnostics,
            .init(
                closed: false,
                hasFrame: true
            )
        )
        XCTAssertTrue(owner.close())
        XCTAssertFalse(owner.close())
        XCTAssertEqual(events.value, ["allocate", "free"])
        XCTAssertEqual(
            owner.diagnostics,
            .init(
                closed: true,
                hasFrame: false
            )
        )
        XCTAssertFalse(owner.withFrame { _ in true })
    }

    func testConcurrentCloseFreesFrameExactlyOnce() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let owner = try XCTUnwrap(
            IRFFDecodeFrame(
                runtime: makeRuntime(
                    frameAddress: 0x2000,
                    events: events
                )
            )
        )
        let closeOwners =
            LockedDecoderResourceValue(0)

        DispatchQueue.concurrentPerform(
            iterations: 100
        ) { _ in
            if owner.close() {
                closeOwners.withValue { $0 += 1 }
            }
        }

        XCTAssertEqual(closeOwners.value, 1)
        XCTAssertEqual(events.value, ["allocate", "free"])
    }

    func testCloseWaitsForScopedFrameBorrow() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let owner = try XCTUnwrap(
            IRFFDecodeFrame(
                runtime: makeRuntime(
                    frameAddress: 0x3000,
                    events: events
                )
            )
        )
        let borrowStarted = DispatchSemaphore(value: 0)
        let releaseBorrow = DispatchSemaphore(value: 0)
        let borrowFinished = DispatchSemaphore(value: 0)
        let closeFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            owner.withFrame { _ in
                borrowStarted.signal()
                releaseBorrow.wait()
                return true
            }
            borrowFinished.signal()
        }
        XCTAssertEqual(
            borrowStarted.wait(timeout: .now() + 1),
            .success
        )

        DispatchQueue.global().async {
            owner.close()
            closeFinished.signal()
        }
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )

        releaseBorrow.signal()
        XCTAssertEqual(
            borrowFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(events.value, ["allocate", "free"])
    }

    func testDeinitClosesFrame() {
        let events =
            LockedDecoderResourceValue<[String]>([])

        autoreleasepool {
            _ = IRFFDecodeFrame(
                runtime: makeRuntime(
                    frameAddress: 0x4000,
                    events: events
                )
            )
        }

        XCTAssertEqual(events.value, ["allocate", "free"])
    }

    private func makeRuntime(
        frameAddress: Int,
        events: LockedDecoderResourceValue<[String]>
    ) -> IRFFDecodeFrameRuntime {
        IRFFDecodeFrameRuntime(
            allocateFrame: {
                events.withValue {
                    $0.append("allocate")
                }
                return UnsafeMutablePointer<AVFrame>(
                    bitPattern: frameAddress
                )
            },
            freeFrame: { frame in
                events.withValue {
                    $0.append("free")
                }
                frame = nil
            }
        )
    }
}

final class LockedDecoderResourceValue<Value>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(
        _ body: (inout Value) -> Void
    ) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}
