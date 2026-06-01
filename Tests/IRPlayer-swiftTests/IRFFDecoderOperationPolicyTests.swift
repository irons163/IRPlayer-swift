import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderOperationPolicyTests: XCTestCase {

    func testOperationSchedulingTreatsMissingOrFinishedOperationsAsSchedulable() {
        XCTAssertTrue(IRFFDecoderOperationPolicy.needsScheduling(nil))

        let operation = BlockOperation {}
        XCTAssertFalse(IRFFDecoderOperationPolicy.needsScheduling(operation))

        operation.start()
        XCTAssertTrue(operation.isFinished)
        XCTAssertTrue(IRFFDecoderOperationPolicy.needsScheduling(operation))
    }

    func testOperationHelpersIgnoreMissingInputsAndWireDependencies() {
        let queue = OperationQueue()
        queue.isSuspended = true

        let operation = BlockOperation {}
        let dependency = BlockOperation {}

        XCTAssertFalse(IRFFDecoderOperationPolicy.addDependency(dependency, to: nil))
        XCTAssertFalse(IRFFDecoderOperationPolicy.addDependency(nil, to: operation))
        XCTAssertTrue(IRFFDecoderOperationPolicy.addDependency(dependency, to: operation))
        XCTAssertTrue(operation.dependencies.contains { $0 === dependency })

        XCTAssertFalse(IRFFDecoderOperationPolicy.enqueue(nil, on: queue))
        XCTAssertFalse(IRFFDecoderOperationPolicy.enqueue(operation, on: nil))
        XCTAssertTrue(IRFFDecoderOperationPolicy.enqueue(operation, on: queue))
        XCTAssertTrue(queue.operations.contains { $0 === operation })

        queue.cancelAllOperations()
        queue.isSuspended = false
    }
}
