//
//  IRGLProgramFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/9.
//

import Foundation

@objcMembers public class IRGLProgramFactory: NSObject {

    public static func createIRGLProgram2D(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2D {
        let program = IRGLProgram2D(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            program.tramsformController = IRGLTransformController2D(viewportWidth: Int(viewportRange.size.width), viewportHeight: Int(viewportRange.size.height))
            program.tramsformController?.delegate = program
        }
        program.mapProjection = IRGLProjectionOrthographic(textureWidth: 0, hidth: 0)
        return program
    }

    public static func createIRGLProgram2DFisheye2Pano(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2DFisheye2Pano {
        let program = IRGLProgram2DFisheye2Pano(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            program.tramsformController = IRGLTransformController2D(viewportWidth: Int(viewportRange.size.width), viewportHeight: Int(viewportRange.size.height))
            program.tramsformController?.delegate = program

            let oldScaleRange = program.tramsformController?.scaleRange
            let newScaleRange = IRGLScaleRange(minScaleX: oldScaleRange?.minScaleX ?? 0, minScaleY: oldScaleRange?.minScaleY ?? 0,
                                               maxScaleX: (oldScaleRange?.maxScaleX ?? 0) * 1.5, maxScaleY: (oldScaleRange?.maxScaleY ?? 0) * 1.5,
                                               defaultScaleX: oldScaleRange?.defaultScaleX ?? 0, defaultScaleY: oldScaleRange?.defaultScaleY ?? 0)
            program.tramsformController?.scaleRange = newScaleRange
        }
        program.mapProjection = IRGLProjectionOrthographic(textureWidth: 0, hidth: 0)
        return program
    }

    public static func createIRGLProgram2DFisheye2Persp(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2DFisheye2Persp {
        let program = IRGLProgram2DFisheye2Persp(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            program.tramsformController = IRGLTransformController2D(viewportWidth: Int(viewportRange.size.width), viewportHeight: Int(viewportRange.size.height))
            program.tramsformController?.delegate = program
        }
        program.mapProjection = IRGLProjectionOrthographic(textureWidth: 0, hidth: 0)
        return program
    }

    public static func createIRGLProgram3DFisheye(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram3DFisheye? {
        var parameter = parameter
        if parameter == nil {
            parameter = IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 0)
        } else if !(parameter is IRFisheyeParameter) {
            print("createIRGLProgram failed.")
            return nil
        }

        let fp = parameter as! IRFisheyeParameter

        let program = IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter!)
        if program.tramsformController == nil {
            program.tramsformController = IRGLTransformController3DFisheye(viewportWidth: Int(viewportRange.size.width), viewportHeight: Int(viewportRange.size.height), tileType: .TILT_BACKWARD)
            program.tramsformController?.delegate = program

            let oldScopeRange = program.tramsformController?.scopeRange ?? IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
            let newMaxLat = oldScopeRange.maxLat > 0 ? fp.latmax : fp.latmax - 90.0
            var newDefaultLat = oldScopeRange.defaultLat
            if newDefaultLat > newMaxLat || newDefaultLat < oldScopeRange.minLat {
                newDefaultLat = (newMaxLat + oldScopeRange.minLat) / 2
            }
            let newScopeRange = IRGLScopeRange(minLat: oldScopeRange.minLat, maxLat: newMaxLat, minLng: oldScopeRange.minLng, maxLng: oldScopeRange.maxLng, defaultLat: newDefaultLat, defaultLng: oldScopeRange.defaultLng)
            program.tramsformController?.scopeRange = newScopeRange

            let scopeRange = program.tramsformController?.scopeRange ?? IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
            let adjustedScopeRange = IRGLScopeRange(minLat: scopeRange.minLat, maxLat: scopeRange.maxLat, minLng: scopeRange.minLng, maxLng: scopeRange.maxLng, defaultLat: -40, defaultLng: 90)
            program.tramsformController?.scopeRange = adjustedScopeRange
        }
        program.mapProjection = IRGLProjectionEquirectangular(textureWidth: fp.width, height: fp.height, centerX: fp.cx, centerY: fp.cy, radius: fp.ry)
        return program
    }

    public static func createIRGLProgram2DFisheye2Persp4P(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgramMulti4P {
        let programs_4p = [
            createIRGLProgram2DFisheye2Persp(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter),
            createIRGLProgram2DFisheye2Persp(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter),
            createIRGLProgram2DFisheye2Persp(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter),
            createIRGLProgram2DFisheye2Persp(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        ]
        let program = IRGLProgramMulti4P(programs: programs_4p, viewprotRange: viewportRange)
        if program.tramsformController == nil {
            program.tramsformController = IRGLTransformController2D(viewportWidth: Int(viewportRange.size.width), viewportHeight: Int(viewportRange.size.height))
            program.tramsformController?.delegate = program
        }

        for (index, program) in programs_4p.enumerated() {
            switch index {
            case 0:
                program.setTransform(x: 0, y: 0)
            case 1:
                program.setTransform(x: 45, y: -45)
            case 2:
                program.setTransform(x: 45, y: 180)
            case 3:
                program.setTransform(x: 45, y: -90)
            default:
                break
            }
        }

        return program
    }

    public static func createIRGLProgram3DFisheye4P(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgramMulti4P? {
        var parameter = parameter
        if parameter == nil {
            parameter = IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 0)
        } else if !(parameter is IRFisheyeParameter) {
            print("createIRGLProgram failed.")
            return nil
        }

        let fp = parameter as! IRFisheyeParameter

        let programs_4p = [
            IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter!),
            IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter!),
            IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter!),
            IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter!)
        ]

        let program = IRGLProgramMulti4P(programs: programs_4p, viewprotRange: viewportRange)
        if program.tramsformController == nil {
            program.tramsformController = IRGLTransformController2D(viewportWidth: Int(viewportRange.size.width), viewportHeight: Int(viewportRange.size.height))
            program.tramsformController?.delegate = program
        }

        let mapProjection = IRGLProjectionEquirectangular(textureWidth: 1440, height: 1080, centerX: fp.cx, centerY: fp.cy, radius: fp.ry)

        for (index, program) in programs_4p.enumerated() {
            if program.tramsformController == nil {
                program.tramsformController = IRGLTransformController3DFisheye(viewportWidth: Int(viewportRange.size.width), viewportHeight: Int(viewportRange.size.height), tileType: .TILT_BACKWARD)
                program.tramsformController?.delegate = program

                let oldScopeRange = program.tramsformController?.scopeRange
                let newMaxLat = (oldScopeRange?.maxLat ?? 0 > 0) ? fp.latmax : fp.latmax - 90.0
                var newDefaultLat = oldScopeRange?.defaultLat ?? 0
                if newDefaultLat > newMaxLat || newDefaultLat < oldScopeRange?.minLat ?? 0 {
                    newDefaultLat = (newMaxLat + (oldScopeRange?.minLat ?? 0)) / 2
                }
                let newScopeRange = IRGLScopeRange(minLat: oldScopeRange?.minLat ?? 0, maxLat: newMaxLat, minLng: oldScopeRange?.minLng ?? 0, maxLng: oldScopeRange?.maxLng ?? 0, defaultLat: newDefaultLat, defaultLng: oldScopeRange?.defaultLng ?? 0)
                program.tramsformController?.scopeRange = newScopeRange
            }
            program.mapProjection = mapProjection

            let scopeRange = program.tramsformController?.scopeRange ?? IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
            var newScopeRange: IRGLScopeRange?
            switch index {
            case 0:
                newScopeRange = IRGLScopeRange(minLat: scopeRange.minLat, maxLat: scopeRange.maxLat, minLng: scopeRange.minLng, maxLng: scopeRange.maxLng, defaultLat: -40, defaultLng: 90)
            case 1:
                newScopeRange = IRGLScopeRange(minLat: scopeRange.minLat, maxLat: scopeRange.maxLat, minLng: scopeRange.minLng, maxLng: scopeRange.maxLng, defaultLat: -40, defaultLng: 180)
            case 2:
                newScopeRange = IRGLScopeRange(minLat: scopeRange.minLat, maxLat: scopeRange.maxLat, minLng: scopeRange.minLng, maxLng: scopeRange.maxLng, defaultLat: -40, defaultLng: 270)
            case 3:
                newScopeRange = IRGLScopeRange(minLat: scopeRange.minLat, maxLat: scopeRange.maxLat, minLng: scopeRange.minLng, maxLng: scopeRange.maxLng, defaultLat: -40, defaultLng: 0)
            default:
                break
            }

            program.tramsformController?.scopeRange = newScopeRange
        }

        return program
    }

    public static func createIRGLProgramVR(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgramVR {
        let program = IRGLProgramVR(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            let transformController = IRGLTransformControllerVR(viewportWidth: Int(viewportRange.size.width), viewportHeight: Int(viewportRange.size.height), tileType: .TILT_UP)
            transformController.rc = 1
            transformController.fov = 30
            transformController.updateVertices()
            program.tramsformController = transformController
            program.tramsformController?.delegate = program

            let oldScaleRange = program.tramsformController?.scaleRange
            let newScaleRange = IRGLScaleRange(minScaleX: oldScaleRange?.minScaleX ?? 0, minScaleY: oldScaleRange?.minScaleY ?? 0,
                                               maxScaleX: (oldScaleRange?.maxScaleX ?? 0) * 1.5, maxScaleY: (oldScaleRange?.maxScaleY ?? 0) * 1.5,
                                               defaultScaleX: oldScaleRange?.defaultScaleX ?? 0, defaultScaleY: oldScaleRange?.defaultScaleY ?? 0)
            program.tramsformController?.scaleRange = newScaleRange
        }
        program.mapProjection = IRGLProjectionVR(textureWidth: 0, hidth: 0)
        return program
    }

    public static func createIRGLProgramDistortion(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgramDistortion {
        let program = IRGLProgramDistortion(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            let transformController = IRGLTransformControllerDistortion(viewportWidth: Int(viewportRange.size.width), viewportHeight: Int(viewportRange.size.height), tileType: .TILT_UP)
            transformController.rc = 1
            transformController.fov = 30
            transformController.updateVertices()
            program.tramsformController = transformController
            program.tramsformController?.delegate = program

            let oldScaleRange = program.tramsformController?.scaleRange
            let newScaleRange = IRGLScaleRange(minScaleX: oldScaleRange?.minScaleX ?? 0, minScaleY: oldScaleRange?.minScaleY ?? 0,
                                               maxScaleX: (oldScaleRange?.maxScaleX ?? 0) * 1.5, maxScaleY: (oldScaleRange?.maxScaleY ?? 0) * 1.5,
                                               defaultScaleX: oldScaleRange?.defaultScaleX ?? 0, defaultScaleY: oldScaleRange?.defaultScaleY ?? 0)
            program.tramsformController?.scaleRange = newScaleRange
        }
        program.mapProjection = IRGLProjectionVR(textureWidth: 0, hidth: 0)
        return program
    }
}
