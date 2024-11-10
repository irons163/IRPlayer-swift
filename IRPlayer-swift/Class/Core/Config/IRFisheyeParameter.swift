//
//  IRFisheyeParameter.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/10.
//

public class IRFisheyeParameter: IRMediaParameter {
    let up: Bool
    let rx: Float
    let ry: Float
    let cx: Float
    let cy: Float
    let latmax: Float

    public init(width: Float, height: Float, up: Bool, rx: Float, ry: Float, cx: Float, cy: Float, latmax: Float) {
        self.up = up
        self.rx = rx
        self.ry = ry
        self.cx = cx
        self.cy = cy
        self.latmax = latmax
        super.init(width: width, height: height)
        print("init FisheyeParameter up:\(up) rx:\(rx) ry:\(ry) cx:\(cx) cy:\(cy) latmax:\(latmax)")
    }
}
