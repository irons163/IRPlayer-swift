import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderOperationPolicyTests: XCTestCase {

    func testOperationSchedulingTreatsMissingOrFinishedOperationsAsSchedulable() {
        XCTAssertTrue(IRFFDecoder.needsScheduling(nil))

        let operation = BlockOperation {}
        XCTAssertFalse(IRFFDecoder.needsScheduling(operation))

        operation.start()
        XCTAssertTrue(operation.isFinished)
        XCTAssertTrue(IRFFDecoder.needsScheduling(operation))
    }

    func testOperationHelpersIgnoreMissingInputsAndWireDependencies() {
        let queue = OperationQueue()
        queue.isSuspended = true

        let operation = BlockOperation {}
        let dependency = BlockOperation {}

        XCTAssertFalse(IRFFDecoder.addDependency(dependency, to: nil))
        XCTAssertFalse(IRFFDecoder.addDependency(nil, to: operation))
        XCTAssertTrue(IRFFDecoder.addDependency(dependency, to: operation))
        XCTAssertTrue(operation.dependencies.contains { $0 === dependency })

        XCTAssertFalse(IRFFDecoder.enqueue(nil, on: queue))
        XCTAssertFalse(IRFFDecoder.enqueue(operation, on: nil))
        XCTAssertTrue(IRFFDecoder.enqueue(operation, on: queue))
        XCTAssertTrue(queue.operations.contains { $0 === operation })

        queue.cancelAllOperations()
        queue.isSuspended = false
    }
}
