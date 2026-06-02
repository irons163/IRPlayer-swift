//
//  IRGLProgramFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/9.
//

import Foundation
import OSLog

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

            let oldScaleRange = program.tramsformController?.scaleRange
            let newScaleRange = IRGLScaleRange(minScaleX: oldScaleRange?.minScaleX ?? 0, minScaleY: oldScaleRange?.minScaleY ?? 0,
                                               maxScaleX: (oldScaleRange?.maxScaleX ?? 0) * 1.5, maxScaleY: (oldScaleRange?.maxScaleY ?? 0) * 1.5,
                                               defaultScaleX: oldScaleRange?.defaultScaleX ?? 0, defaultScaleY: oldScaleRange?.defaultScaleY ?? 0)
            program.tramsformController?.scaleRange = newScaleRange
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
            IRPlayerImp.Logger.libraryLogger.warning("createIRGLProgram failed.")
            return nil
        }

        let program = IRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: fisheyeParameter)
        if program.tramsformController == nil {
            program.tramsformController = makeFisheyeTransformController(viewportRange: viewportRange, tileType: .backward)
            program.tramsformController?.delegate = program

            let oldScopeRange = program.tramsformController?.scopeRange ?? IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
            let newMaxLat = oldScopeRange.maxLat > 0 ? fisheyeParameter.latmax : fisheyeParameter.latmax - 90.0
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
            IRPlayerImp.Logger.libraryLogger.warning("createIRGLProgram failed.")
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

                let oldScopeRange = program.tramsformController?.scopeRange
                let newMaxLat = (oldScopeRange?.maxLat ?? 0 > 0) ? fisheyeParameter.latmax : fisheyeParameter.latmax - 90.0
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

    private static func makeFisheyeParameter(from parameter: IRMediaParameter?) -> IRFisheyeParameter? {
        guard let parameter = parameter else {
            return IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 0)
        }
        guard let fisheyeParameter = parameter as? IRFisheyeParameter else {
            IRPlayerImp.Logger.libraryLogger.warning("createIRGLProgram failed.")
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

            let oldScaleRange = program.tramsformController?.scaleRange
            let newScaleRange = IRGLScaleRange(minScaleX: oldScaleRange?.minScaleX ?? 0, minScaleY: oldScaleRange?.minScaleY ?? 0,
                                               maxScaleX: (oldScaleRange?.maxScaleX ?? 0) * 1.5, maxScaleY: (oldScaleRange?.maxScaleY ?? 0) * 1.5,
                                               defaultScaleX: oldScaleRange?.defaultScaleX ?? 0, defaultScaleY: oldScaleRange?.defaultScaleY ?? 0)
            program.tramsformController?.scaleRange = newScaleRange
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

            let oldScaleRange = program.tramsformController?.scaleRange
            let newScaleRange = IRGLScaleRange(minScaleX: oldScaleRange?.minScaleX ?? 0, minScaleY: oldScaleRange?.minScaleY ?? 0,
                                               maxScaleX: (oldScaleRange?.maxScaleX ?? 0) * 1.5, maxScaleY: (oldScaleRange?.maxScaleY ?? 0) * 1.5,
                                               defaultScaleX: oldScaleRange?.defaultScaleX ?? 0, defaultScaleY: oldScaleRange?.defaultScaleY ?? 0)
            program.tramsformController?.scaleRange = newScaleRange
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
