import Foundation

struct IRPlayerRenderConfiguration {
    enum Interaction: Equatable {
        case gestures
        case motion
    }

    let modes: [IRGLRenderMode]?
    let gravityMode: IRGravityMode?
    let interaction: Interaction

    static func make(videoType: IRVideoType, displayMode: IRDisplayMode) -> IRPlayerRenderConfiguration {
        switch videoType {
        case .normal:
            return IRPlayerRenderConfiguration(
                modes: IRGLRenderModeFactory.createNormalModes(with: nil),
                gravityMode: nil,
                interaction: .gestures
            )

        case .vr:
            let mode: IRGLRenderMode
            let interaction: Interaction
            switch displayMode {
            case .normal:
                mode = IRGLRenderModeFactory.createVRMode(with: nil)
                interaction = .gestures
            case .box:
                mode = IRGLRenderModeFactory.createDistortionMode(with: nil)
                interaction = .motion
            }
            mode.defaultScale = 1.5
            mode.aspect = 16.0 / 9.0
            return IRPlayerRenderConfiguration(
                modes: [mode],
                gravityMode: .resizeAspect,
                interaction: interaction
            )

        case .fisheye:
            let parameter = IRFisheyeParameter(
                width: 0,
                height: 0,
                up: false,
                rx: 0,
                ry: 0,
                cx: 0,
                cy: 0,
                latmax: 80
            )
            let mode = IRGLRenderModeFactory.createFisheyeMode(with: parameter)
            mode.defaultScale = 1.5
            mode.aspect = 16.0 / 9.0
            return IRPlayerRenderConfiguration(
                modes: [mode],
                gravityMode: .resizeAspect,
                interaction: .gestures
            )

        case .pano:
            return IRPlayerRenderConfiguration(
                modes: [IRGLRenderModeFactory.createPanoramaMode(with: nil)],
                gravityMode: nil,
                interaction: .gestures
            )

        case .custom:
            return IRPlayerRenderConfiguration(
                modes: nil,
                gravityMode: nil,
                interaction: .gestures
            )
        }
    }
}
