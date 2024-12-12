//
//  IRMediaParameter.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/10.
//

public class IRMediaParameter {
    var width: Float
    var height: Float
    var autoUpdate: Bool = true

    public init(width: Float, height: Float) {
        self.width = width
        self.height = height
    }
}
