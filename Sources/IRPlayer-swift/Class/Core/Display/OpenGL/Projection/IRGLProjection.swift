//
//  IRGLProjection.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/19.
//

import Foundation

enum Attribute: Int {
    case vertex = 0
    case texcoord
}

protocol IRGLProjection {
    func update(with parameter: IRMediaParameter)
    func updateVertex()
    func draw()
}
