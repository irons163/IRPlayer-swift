//
//  IRGLProgramFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/9.
//

import Foundation

enum IRGLProgramFactoryPolicy {
    static func expandedScaleRange(from range: IRGLScaleRange, multiplier: Float) -> IRGLScaleRange {
        IRGLScaleRange(minScaleX: range.minScaleX,
                       minScaleY: range.minScaleY,
                       maxScaleX: range.maxScaleX * multiplier,
                       maxScaleY: range.maxScaleY * multiplier,
                       defaultScaleX: range.defaultScaleX,
                       defaultScaleY: range.defaultScaleY)
    }

    static func fisheyeScopeRange(from range: IRGLScopeRange, latmax: Float) -> IRGLScopeRange {
        let maxLat = range.maxLat > 0 ? latmax : latmax - 90.0
        var defaultLat = range.defaultLat
        if defaultLat > maxLat || defaultLat < range.minLat {
            defaultLat = (maxLat + range.minLat) / 2
        }
        return IRGLScopeRange(minLat: range.minLat,
                              maxLat: maxLat,
                              minLng: range.minLng,
                              maxLng: range.maxLng,
                              defaultLat: defaultLat,
                              defaultLng: range.defaultLng)
    }

    static func defaultFisheyeScope(from range: IRGLScopeRange, panelIndex: Int?) -> IRGLScopeRange {
        let defaultLng: Float
        switch panelIndex {
        case 1:
            defaultLng = 180
        case 2:
            defaultLng = 270
        case 3:
            defaultLng = 0
        default:
            defaultLng = 90
        }

        return IRGLScopeRange(minLat: range.minLat,
                              maxLat: range.maxLat,
                              minLng: range.minLng,
                              maxLng: range.maxLng,
                              defaultLat: -40,
                              defaultLng: defaultLng)
    }
}

@objcMembers public class IRGLProgramFactory: NSObject {

    public static func createIRGLProgram2D(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2D {
        let program = IRGLProgram2D(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            program.tramsformController = makeTransformController2D(viewportRange: viewportRange)
            program.tramsformController?.delegate = program
        }
        program.mapProjection = IRGLProjectionOrthographic(textureWidth: 0, height: 0)
        return program
    }

    public static func createIRGLProgram2DFisheye2Pano(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2DFisheye2Pano {
        let program = IRGLProgram2DFisheye2Pano(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            program.tramsformController = makeTransformController2D(viewportRange: viewportRange)
            program.tramsformController?.delegate = program

            let oldScaleRange = program.tramsformController?.scaleRange ?? IRGLScaleRange(minScaleX: 0, minScaleY: 0, maxScaleX: 0, maxScaleY: 0, defaultScaleX: 0, defaultScaleY: 0)
            program.tramsformController?.scaleRange = IRGLProgramFactoryPolicy.expandedScaleRange(from: oldScaleRange, multiplier: 1.5)
        }
        program.mapProjection = IRGLProjectionOrthographic(textureWidth: 0, height: 0)
        return program
    }

    public static func createIRGLProgram2DFisheye2Persp(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2DFisheye2Persp {
        let program = IRGLProgram2DFisheye2Persp(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            program.tramsformController = makeTransformController2D(viewportRange: viewportRange)
            program.tramsformController?.delegate = program
        }
        program.mapProjection = IRGLProjectionOrthographic(textureWidth: 0, height: 0)
        return program
    }

    public static func createIRGLProgram3DFisheye(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram3DFisheye? {
        guard let fisheyeParameter = makeFisheyeParameter(from: parameter) else {
            return nil
        }

        let program = IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: fisheyeParameter)
        if program.tramsformController == nil {
            program.tramsformController = makeFisheyeTransformController(viewportRange: viewportRange, tileType: .backward)
            program.tramsformController?.delegate = program

            let oldScopeRange = program.tramsformController?.scopeRange ?? IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
            let fisheyeScopeRange = IRGLProgramFactoryPolicy.fisheyeScopeRange(from: oldScopeRange, latmax: fisheyeParameter.latmax)
            program.tramsformController?.scopeRange = IRGLProgramFactoryPolicy.defaultFisheyeScope(from: fisheyeScopeRange, panelIndex: nil)
        }
        program.mapProjection = IRGLProjectionEquirectangular(textureWidth: fisheyeParameter.width, height: fisheyeParameter.height, centerX: fisheyeParameter.cx, centerY: fisheyeParameter.cy, radius: fisheyeParameter.ry)
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
            program.tramsformController = makeTransformController2D(viewportRange: viewportRange)
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
        guard let fisheyeParameter = makeFisheyeParameter(from: parameter) else {
            return nil
        }

        let programs_4p = [
            IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: fisheyeParameter),
            IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: fisheyeParameter),
            IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: fisheyeParameter),
            IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: fisheyeParameter)
        ]

        let program = IRGLProgramMulti4P(programs: programs_4p, viewprotRange: viewportRange)
        if program.tramsformController == nil {
            program.tramsformController = makeTransformController2D(viewportRange: viewportRange)
            program.tramsformController?.delegate = program
        }

        let mapProjection = IRGLProjectionEquirectangular(textureWidth: 1440, height: 1080, centerX: fisheyeParameter.cx, centerY: fisheyeParameter.cy, radius: fisheyeParameter.ry)

        for (index, program) in programs_4p.enumerated() {
            if program.tramsformController == nil {
                program.tramsformController = makeFisheyeTransformController(viewportRange: viewportRange, tileType: .backward)
                program.tramsformController?.delegate = program

                let oldScopeRange = program.tramsformController?.scopeRange ?? IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
                program.tramsformController?.scopeRange = IRGLProgramFactoryPolicy.fisheyeScopeRange(from: oldScopeRange, latmax: fisheyeParameter.latmax)
            }
            program.mapProjection = mapProjection

            let scopeRange = program.tramsformController?.scopeRange ?? IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
            program.tramsformController?.scopeRange = IRGLProgramFactoryPolicy.defaultFisheyeScope(from: scopeRange, panelIndex: index)
        }

        return program
    }

    private static func makeFisheyeParameter(from parameter: IRMediaParameter?) -> IRFisheyeParameter? {
        guard let parameter = parameter else {
            return IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 0)
        }
        guard let fisheyeParameter = parameter as? IRFisheyeParameter else {
            print("createIRGLProgram failed.")
            return nil
        }
        return fisheyeParameter
    }

    public static func createIRGLProgramVR(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgramVR {
        let program = IRGLProgramVR(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            guard let viewportSize = IRGLProgram2D.viewportSize(from: viewportRange) else {
                program.mapProjection = IRGLProjectionVR(textureWidth: 0, height: 0)
                return program
            }
            let transformController = IRGLTransformControllerVR(viewportWidth: viewportSize.width, viewportHeight: viewportSize.height, tileType: .up)
            transformController.rc = 1
            transformController.fov = 30
            transformController.updateVertices()
            program.tramsformController = transformController
            program.tramsformController?.delegate = program

            let oldScaleRange = program.tramsformController?.scaleRange ?? IRGLScaleRange(minScaleX: 0, minScaleY: 0, maxScaleX: 0, maxScaleY: 0, defaultScaleX: 0, defaultScaleY: 0)
            program.tramsformController?.scaleRange = IRGLProgramFactoryPolicy.expandedScaleRange(from: oldScaleRange, multiplier: 1.5)
        }
        program.mapProjection = IRGLProjectionVR(textureWidth: 0, height: 0)
        return program
    }

    public static func createIRGLProgramDistortion(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgramDistortion {
        let program = IRGLProgramDistortion(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        if program.tramsformController == nil {
            guard let viewportSize = IRGLProgram2D.viewportSize(from: viewportRange) else {
                program.mapProjection = IRGLProjectionVR(textureWidth: 0, height: 0)
                return program
            }
            let transformController = IRGLTransformControllerDistortion(viewportWidth: viewportSize.width, viewportHeight: viewportSize.height, tileType: .up)
            transformController.rc = 1
            transformController.fov = 30
            transformController.updateVertices()
            program.tramsformController = transformController
            program.tramsformController?.delegate = program

            let oldScaleRange = program.tramsformController?.scaleRange ?? IRGLScaleRange(minScaleX: 0, minScaleY: 0, maxScaleX: 0, maxScaleY: 0, defaultScaleX: 0, defaultScaleY: 0)
            program.tramsformController?.scaleRange = IRGLProgramFactoryPolicy.expandedScaleRange(from: oldScaleRange, multiplier: 1.5)
        }
        program.mapProjection = IRGLProjectionVR(textureWidth: 0, height: 0)
        return program
    }

    private static func makeTransformController2D(viewportRange: CGRect) -> IRGLTransformController2D? {
        guard let viewportSize = IRGLProgram2D.viewportSize(from: viewportRange) else { return nil }
        return IRGLTransformController2D(viewportWidth: viewportSize.width, viewportHeight: viewportSize.height)
    }

    private static func makeFisheyeTransformController(viewportRange: CGRect, tileType: IRGLScope3D.TiltType) -> IRGLTransformController3DFisheye? {
        guard let viewportSize = IRGLProgram2D.viewportSize(from: viewportRange) else { return nil }
        return IRGLTransformController3DFisheye(viewportWidth: viewportSize.width, viewportHeight: viewportSize.height, tileType: tileType)
    }
}
