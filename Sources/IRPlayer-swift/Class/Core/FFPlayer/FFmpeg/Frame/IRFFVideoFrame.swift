//
//  IRFFVideoFrame.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation

struct IRFFVideoDimensions: Equatable, Hashable, Sendable {
    static let zero = IRFFVideoDimensions(width: 0, height: 0)

    let width: Int
    let height: Int

    private init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    var isEmpty: Bool {
        width == 0 && height == 0
    }

    static func make(
        width: Int,
        height: Int
    ) -> IRFFVideoDimensions? {
        guard width >= 0, height >= 0 else {
            return nil
        }
        guard (width == 0) == (height == 0) else {
            return nil
        }
        return IRFFVideoDimensions(
            width: width,
            height: height
        )
    }
}

enum IRYUVChannel: Int, Hashable, Equatable, Sendable, RawRepresentable {
    case luma = 0
    case chromaB = 1
    case chromaR = 2
    case count = 3
}

@objcMembers public class IRFFVideoFrame: IRFFFrame {
    private let dimensionLock = NSLock()
    private var storedDimensions = IRFFVideoDimensions.zero

    public var width: Int {
        dimensionSnapshot().width
    }

    public var height: Int {
        dimensionSnapshot().height
    }

    override var type: IRFFFrameType {
        return .video
    }

    @discardableResult
    public func setDimensions(
        width: Int,
        height: Int
    ) -> Bool {
        guard let dimensions = IRFFVideoDimensions.make(
            width: width,
            height: height
        ) else {
            return false
        }
        replaceStoredDimensions(dimensions)
        return true
    }

    @nonobjc
    func dimensionSnapshot() -> IRFFVideoDimensions {
        dimensionLock.lock()
        defer { dimensionLock.unlock() }
        return storedDimensions
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        replaceStoredDimensions(.zero)
    }

    private func replaceStoredDimensions(
        _ dimensions: IRFFVideoDimensions
    ) {
        dimensionLock.lock()
        storedDimensions = dimensions
        dimensionLock.unlock()
    }
}
