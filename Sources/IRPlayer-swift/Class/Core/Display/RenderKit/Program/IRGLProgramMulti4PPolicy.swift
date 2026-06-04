//
//  IRGLProgramMulti4PPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import CoreGraphics
import Foundation

enum IRGLProgramMulti4PPolicy {

    static func viewportRanges(
        in viewprotRange: CGRect,
        displayMode: IRGLProgramMultiMode,
        programCount: Int,
        selectedIndex: Int?
    ) -> [CGRect] {
        guard programCount > 0 else { return [] }

        switch displayMode {
        case .multiDisplay:
            let viewportWidth = viewprotRange.size.width / 2.0
            let viewportHeight = viewprotRange.size.height / 2.0
            return (0..<programCount).map { index in
                CGRect(
                    x: CGFloat(index % 2) * viewportWidth,
                    y: CGFloat(index / 2) * viewportHeight,
                    width: viewportWidth,
                    height: viewportHeight
                )
            }
        case .singleDisplay:
            let selectedRange = CGRect(x: 0, y: 0, width: viewprotRange.size.width, height: viewprotRange.size.height)
            return (0..<programCount).map { index in
                index == selectedIndex ? selectedRange : .zero
            }
        }
    }
}
