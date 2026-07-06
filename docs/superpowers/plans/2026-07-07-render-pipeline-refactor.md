# Render Pipeline Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `IRGLView` render orchestration and mode-specific Metal cache state into internal RenderKit collaborators while preserving all post-2.0 render behavior.

**Architecture:** Add `IRGLViewRenderState` to own fisheye, VR, fish2pano, and distortion cached resources. Add `IRGLViewRenderCoordinator` to own the current `renderCurrentContent` dispatch order while `IRGLView` remains the UIKit-facing facade and render queue owner.

**Tech Stack:** Swift 5.9, UIKit, Metal, CoreImage, XCTest, Xcode project test target, iOS Simulator via XcodeBuildMCP or `xcodebuild test`.

---

## Scope Check

This plan covers one subsystem: Display/RenderKit render pipeline internals. It intentionally avoids FFmpeg, AVPlayer, audio, Metal shader source, pixel conversion rewrites, and public API changes.

## File Structure

- Create: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderState.swift`
  - Owns mode-specific cached Metal resources and setup/reset helpers.
- Create: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderCoordinator.swift`
  - Owns render dispatch ordering and CI fallback rendering.
- Modify: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift`
  - Keeps view lifecycle, render queue, mode list, selected mode, gestures, snapshot methods, Metal setup, and public/internal entry points.
  - Delegates mode cache state and render dispatch.
- Create: `Tests/IRPlayer-swiftTests/IRGLViewRenderStateTests.swift`
  - Covers state reset and mode setup without real playback.
- Modify: `Tests/IRPlayer-swiftTests/IRGLViewSnapshotTests.swift`
  - Keep existing dispatch tests passing; no new snapshot tests are expected for this slice because current coverage already proves selected-mode dispatch.
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`
  - Add new source/test files to the Xcode project because the project uses explicit file references.

Use these new project identifiers when editing `project.pbxproj`:

- `B5E960002F7107000149265` = `IRGLViewRenderState.swift` file reference
- `B5E960012F7107000149265` = `IRGLViewRenderState.swift in Sources`
- `B5E960022F7107010149265` = `IRGLViewRenderStateTests.swift` file reference
- `B5E960032F7107010149265` = `IRGLViewRenderStateTests.swift in Sources`
- `B5E960042F7107020149265` = `IRGLViewRenderCoordinator.swift` file reference
- `B5E960052F7107020149265` = `IRGLViewRenderCoordinator.swift in Sources`

Add production files to the RenderKit group near `IRGLView.swift`, `IRGLViewPolicy.swift`, and `IRGLRenderStrategyPolicy.swift`. Add the test file near `IRGLViewSnapshotTests.swift`.

## Verification Commands

Before the first simulator build/test in an implementation session, call XcodeBuildMCP `session_show_defaults`. If defaults show project/workspace, scheme, and simulator are configured, use those defaults for focused and full test calls.

Shell fallback for focused tests:

```sh
FOCUSED_DESTINATION_ID="$(xcrun simctl list devices available | awk -F'[()]' '/iPhone/ && /Booted|Shutdown/ { print $2; exit }')"
test -n "$FOCUSED_DESTINATION_ID"
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRGLViewRenderStateTests
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRGLViewSnapshotTests
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRGLRenderStrategyFactoryTests
```

Full verification command:

```sh
git diff --check
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID"
```

Expected green output for passing test runs includes `** TEST SUCCEEDED **`.

Run this assignment at the start of each new shell session before using the focused commands below:

```sh
FOCUSED_DESTINATION_ID="$(xcrun simctl list devices available | awk -F'[()]' '/iPhone/ && /Booted|Shutdown/ { print $2; exit }')"
```

---

### Task 1: Add Failing Render State Tests

**Files:**
- Create: `Tests/IRPlayer-swiftTests/IRGLViewRenderStateTests.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the failing test file**

Add `Tests/IRPlayer-swiftTests/IRGLViewRenderStateTests.swift`:

```swift
import CoreGraphics
import Metal
import XCTest
@testable import IRPlayer_swift

final class IRGLViewRenderStateTests: XCTestCase {

    func testResetClearsModeSpecificState() throws {
        let state = IRGLViewRenderState()
        let panoMode = makePanoMode()
        let fisheyeMode = makeFisheyeMode()
        let program = try XCTUnwrap(panoMode.program as? IRGLProgram2DFisheye2Pano)
        let params = try XCTUnwrap(program.metalFish2PanoParams)
        params.outputWidth = 4
        params.outputHeight = 2
        params.antialias = 2

        state.configureFish2Pano(renderMode: panoMode)
        let readiness: IRGLViewRenderState.Fish2PanoTextureReadiness? =
            state.prepareFish2PanoTextures(device: nil as MTLDevice?)
        XCTAssertEqual(readiness, IRGLViewRenderState.Fish2PanoTextureReadiness.waitingForTextures)
        state.configureFisheye(renderMode: fisheyeMode,
                               viewportSize: CGSize(width: 320, height: 180))

        XCTAssertNotNil(state.fish2PanoParams)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize(width: 4, height: 2))
        XCTAssertEqual(state.fish2PanoLastAntialias, 2)
        XCTAssertNotNil(state.fisheyeController)
        XCTAssertNotNil(state.fisheyeParameter)

        state.reset()

        XCTAssertNil(state.fish2PanoParams)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize.zero)
        XCTAssertEqual(state.fish2PanoLastAntialias, 0)
        XCTAssertNil(state.fisheyeController)
        XCTAssertNil(state.fisheyeParameter)
    }

    func testConfigureFish2PanoStoresProgramParams() throws {
        let state = IRGLViewRenderState()
        let mode = makePanoMode()
        let program = try XCTUnwrap(mode.program as? IRGLProgram2DFisheye2Pano)
        let params = try XCTUnwrap(program.metalFish2PanoParams)

        state.configureFish2Pano(renderMode: mode)

        XCTAssertTrue(state.fish2PanoParams === params)
    }

    func testConfigureFish2PanoClearsStateForNonPanoMode() throws {
        let state = IRGLViewRenderState()
        let mode = makePanoMode()
        let program = try XCTUnwrap(mode.program as? IRGLProgram2DFisheye2Pano)
        let params = try XCTUnwrap(program.metalFish2PanoParams)
        params.outputWidth = 4
        params.outputHeight = 2
        params.antialias = 2

        state.configureFish2Pano(renderMode: mode)
        let readiness: IRGLViewRenderState.Fish2PanoTextureReadiness? =
            state.prepareFish2PanoTextures(device: nil as MTLDevice?)
        XCTAssertEqual(readiness, IRGLViewRenderState.Fish2PanoTextureReadiness.waitingForTextures)
        XCTAssertNotNil(state.fish2PanoParams)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize(width: 4, height: 2))
        XCTAssertEqual(state.fish2PanoLastAntialias, 2)

        state.configureFish2Pano(renderMode: IRGLRenderMode2D())

        XCTAssertNil(state.fish2PanoParams)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize.zero)
        XCTAssertEqual(state.fish2PanoLastAntialias, 0)
    }

    func testConfigureFisheyeUsesProgramControllerAndParameter() throws {
        let state = IRGLViewRenderState()
        let mode = makeFisheyeMode()
        let program = try XCTUnwrap(mode.program as? IRGLProgram3DFisheye)
        let controller = try XCTUnwrap(program.tramsformController as? IRGLTransformController3DFisheye)
        let parameter = try XCTUnwrap(mode.parameter as? IRFisheyeParameter)

        state.configureFisheye(renderMode: mode,
                               viewportSize: CGSize(width: 320, height: 180))

        XCTAssertTrue(state.fisheyeController === controller)
        XCTAssertTrue(state.fisheyeParameter === parameter)
    }

    func testConfigureFisheyeCreatesFallbackControllerAndDefaultParameter() {
        let state = IRGLViewRenderState()
        let mode = NilProgramFisheyeRenderMode()

        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                              parameter: nil)

        state.configureFisheye(renderMode: mode,
                               viewportSize: CGSize(width: 320, height: 180))

        let controller: IRGLTransformController3DFisheye = try XCTUnwrap(state.fisheyeController)
        let scope = controller.getScope()
        XCTAssertEqual(scope.w, 320)
        XCTAssertEqual(scope.h, 180)
        XCTAssertEqual(state.fisheyeParameter?.width, 0)
        XCTAssertEqual(state.fisheyeParameter?.height, 0)
        XCTAssertEqual(state.fisheyeParameter?.latmax, 0)
    }

    func testConfigureFisheyeClearsStateForNonFisheyeMode() {
        let state = IRGLViewRenderState()
        state.configureFisheye(renderMode: makeFisheyeMode(),
                               viewportSize: CGSize(width: 320, height: 180))
        XCTAssertNotNil(state.fisheyeController)

        state.configureFisheye(renderMode: IRGLRenderMode2D(),
                               viewportSize: CGSize(width: 320, height: 180))

        XCTAssertNil(state.fisheyeController)
        XCTAssertNil(state.fisheyeParameter)
    }

    private func makePanoMode() -> IRGLRenderMode2DFisheye2Pano {
        let mode = IRGLRenderMode2DFisheye2Pano()
        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                              parameter: nil)
        return mode
    }

    private func makeFisheyeMode() -> IRGLRenderMode3DFisheye {
        let mode = IRGLRenderMode3DFisheye()
        let parameter = IRFisheyeParameter(width: 2,
                                           height: 2,
                                           up: false,
                                           rx: 1,
                                           ry: 1,
                                           cx: 1,
                                           cy: 1,
                                           latmax: 90)
        mode.parameter = parameter
        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                              parameter: parameter)
        return mode
    }
}

private final class NilProgramFisheyeRenderMode: IRGLRenderMode3DFisheye {
    override var programFactory: IRGLProgram2DFactory {
        NilProgramFactory()
    }
}

private final class NilProgramFactory: IRGLProgram2DFactory {
    override func createIRGLProgram(pixelFormat: IRPixelFormat,
                                    viewportRange: CGRect,
                                    parameter: IRMediaParameter?) -> IRGLProgram2D? {
        nil
    }
}
```

- [ ] **Step 2: Add the test file to the Xcode test target**

Modify `IRPlayer-swift.xcodeproj/project.pbxproj`:

```text
B5E960032F7107010149265 /* IRGLViewRenderStateTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B5E960022F7107010149265 /* IRGLViewRenderStateTests.swift */; };
B5E960022F7107010149265 /* IRGLViewRenderStateTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IRGLViewRenderStateTests.swift; sourceTree = "<group>"; };
B5E960022F7107010149265 /* IRGLViewRenderStateTests.swift */,
B5E960032F7107010149265 /* IRGLViewRenderStateTests.swift in Sources */,
```

- [ ] **Step 3: Run focused tests and confirm RED**

Run:

```sh
FOCUSED_DESTINATION_ID="$(xcrun simctl list devices available | awk -F'[()]' '/iPhone/ && /Booted|Shutdown/ { print $2; exit }')"
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRGLViewRenderStateTests
```

Expected: FAIL to compile with `cannot find 'IRGLViewRenderState' in scope`.

- [ ] **Step 4: Commit**

```sh
git add Tests/IRPlayer-swiftTests/IRGLViewRenderStateTests.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "test: cover gl view render state setup"
```

---

### Task 2: Implement Render State Helper

**Files:**
- Create: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderState.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create `IRGLViewRenderState.swift`**

Add `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderState.swift`:

```swift
//
//  IRGLViewRenderState.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import CoreGraphics
import Metal

final class IRGLViewRenderState {
    private(set) var fisheyeMesh: IRMetalFisheyeMesh?
    private(set) var vrMesh: IRMetalFisheyeMesh?
    private(set) var fisheyeController: IRGLTransformController3DFisheye?
    private(set) var fisheyeParameter: IRFisheyeParameter?
    private(set) var fisheyeLastSize: CGSize = .zero
    private(set) var fish2PanoParams: IRGLFish2PanoShaderParams?
    private(set) var fish2PanoTextures: [MTLTexture] = []
    private(set) var fish2PanoLastOutputSize: CGSize = .zero
    private(set) var fish2PanoLastAntialias: Int = 0
    private(set) var distortionLeftMesh: IRMetalDistortionMesh?
    private(set) var distortionRightMesh: IRMetalDistortionMesh?

    enum Fish2PanoTextureReadiness: Equatable {
        case invalid
        case waitingForTextures
        case ready(outputSize: CGSize, antialias: Int)
    }

    func reset() {
        fisheyeMesh = nil
        vrMesh = nil
        fisheyeController = nil
        fisheyeParameter = nil
        fisheyeLastSize = .zero
        resetFish2Pano()
        distortionLeftMesh = nil
        distortionRightMesh = nil
    }

    func configureFish2Pano(renderMode: IRGLRenderMode) {
        guard let program = renderMode.program as? IRGLProgram2DFisheye2Pano else {
            resetFish2Pano()
            return
        }

        fish2PanoParams = program.metalFish2PanoParams
    }

    func prepareFish2PanoTextures(device: MTLDevice?) -> Fish2PanoTextureReadiness? {
        guard let params = fish2PanoParams else { return nil }
        let outputWidth = Int(params.outputWidth)
        let outputHeight = Int(params.outputHeight)
        let antialias = Int(params.antialias)
        guard outputWidth > 0, outputHeight > 0, antialias > 0 else { return .invalid }

        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        if outputSize != fish2PanoLastOutputSize || antialias != fish2PanoLastAntialias {
            fish2PanoTextures = []
            fish2PanoLastOutputSize = outputSize
            fish2PanoLastAntialias = antialias
        }

        if let device, let pixUV = params.consumePixUVIfReady() {
            defer { params.releaseConsumedPixUV(pixUV) }

            let texCount = min(pixUV.count, antialias * antialias)
            var newTextures: [MTLTexture] = []
            newTextures.reserveCapacity(texCount)
            for i in 0..<texCount {
                guard let texture = makeTexUVTexture(device: device,
                                                     width: outputWidth,
                                                     height: outputHeight,
                                                     data: pixUV[i]) else {
                    continue
                }
                newTextures.append(texture)
            }
            if !newTextures.isEmpty {
                fish2PanoTextures = newTextures
            }
        }

        guard fish2PanoTextures.count == antialias * antialias else {
            return .waitingForTextures
        }

        return .ready(outputSize: outputSize, antialias: antialias)
    }

    func configureFisheye(renderMode: IRGLRenderMode, viewportSize: CGSize) {
        guard renderMode is IRGLRenderMode3DFisheye else {
            resetFisheye()
            return
        }

        if let programController = renderMode.program?.tramsformController as? IRGLTransformController3DFisheye {
            fisheyeController = programController
        } else if fisheyeController == nil {
            let width = max(Int(viewportSize.width), 1)
            let height = max(Int(viewportSize.height), 1)
            fisheyeController = IRGLTransformController3DFisheye(viewportWidth: width,
                                                                 viewportHeight: height,
                                                                 tileType: .backward)
        }

        if let parameter = renderMode.parameter as? IRFisheyeParameter {
            fisheyeParameter = parameter
        } else {
            fisheyeParameter = Self.defaultFisheyeParameter()
        }
    }

    func resetFisheyeViewport(width: Int, height: Int, resetTransform: Bool) {
        fisheyeController?.resetViewport(width: width,
                                         height: height,
                                         resetTransform: resetTransform)
    }

    func updateFallbackFisheye(fx: Float, fy: Float, sx: Float, sy: Float) {
        fisheyeController?.update(fx: fx, fy: fy, sx: sx, sy: sy)
    }

    func scrollFallbackFisheye(dx: Float, dy: Float) {
        fisheyeController?.scroll(dx: dx, dy: dy)
    }

    func scrollFallbackFisheye(degreeX: Float, degreeY: Float) {
        fisheyeController?.scroll(degreeX: degreeX, degreeY: degreeY)
    }

    private func resetFish2Pano() {
        fish2PanoParams = nil
        fish2PanoTextures = []
        fish2PanoLastOutputSize = .zero
        fish2PanoLastAntialias = 0
    }

    private func resetFisheye() {
        fisheyeController = nil
        fisheyeMesh = nil
        fisheyeParameter = nil
        fisheyeLastSize = .zero
    }

    private func makeTexUVTexture(device: MTLDevice,
                                  width: Int,
                                  height: Int,
                                  data: UnsafeMutablePointer<GLfloat>) -> MTLTexture? {
        guard let layout = IRGLViewPolicy.texUVTextureLayout(width: width, height: height) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: data,
                        bytesPerRow: layout.bytesPerRow)
        return texture
    }

    static func defaultFisheyeParameter() -> IRFisheyeParameter {
        IRFisheyeParameter(width: 0,
                           height: 0,
                           up: false,
                           rx: 0,
                           ry: 0,
                           cx: 0,
                           cy: 0,
                           latmax: 0)
    }
}
```

- [ ] **Step 2: Add the source file to the Xcode framework target**

Modify `IRPlayer-swift.xcodeproj/project.pbxproj`:

```text
B5E960012F7107000149265 /* IRGLViewRenderState.swift in Sources */ = {isa = PBXBuildFile; fileRef = B5E960002F7107000149265 /* IRGLViewRenderState.swift */; };
B5E960002F7107000149265 /* IRGLViewRenderState.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IRGLViewRenderState.swift; sourceTree = "<group>"; };
B5E960002F7107000149265 /* IRGLViewRenderState.swift */,
B5E960012F7107000149265 /* IRGLViewRenderState.swift in Sources */,
```

- [ ] **Step 3: Run focused state tests and confirm GREEN**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRGLViewRenderStateTests
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```sh
git add Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderState.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "feat: add gl view render state helper"
```

---

### Task 3: Route IRGLView Setup And Gesture Fallback Through Render State

**Files:**
- Modify: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift`

- [ ] **Step 1: Add render state and remove only setup-owned cached fields**

In `IRGLView`, add:

```swift
private let renderState = IRGLViewRenderState()
```

Then remove only the cached fields that Task 3 routes completely through `renderState`:

```swift
private var metalFisheyeController: IRGLTransformController3DFisheye?
private var metalFisheyeParameter: IRFisheyeParameter?
private var metalFish2PanoParams: IRGLFish2PanoShaderParams?
private var metalFish2PanoTexUV: [MTLTexture] = []
private var metalFish2PanoLastOutputSize: CGSize = .zero
private var metalFish2PanoLastAntialias: Int = 0
```

Keep these cache fields in `IRGLView` until Task 4 moves their render-helper mutation into `IRGLViewRenderState`:

```swift
private var metalFisheyeMesh: IRMetalFisheyeMesh?
private var metalVRMesh: IRMetalFisheyeMesh?
private var metalFisheyeLastSize: CGSize = .zero
private var metalDistortionLeftMesh: IRMetalDistortionMesh?
private var metalDistortionRightMesh: IRMetalDistortionMesh?
```

- [ ] **Step 2: Route reset through render state**

In `reset()`, replace the mode-specific nil assignments with:

```swift
renderState.reset()
```

Keep the existing resets for `currentImage`, `currentFrame`, `metalRenderer`, `commandQueue`, `ciContext`, `device`, and the render-helper cache fields that remain in `IRGLView` until Task 4.

- [ ] **Step 3: Route viewport and gesture fallback calls through render state**

Replace fallback controller calls:

```swift
metalFisheyeController?.resetViewport(width: viewportSize.width, height: viewportSize.height, resetTransform: resetTransform)
metalFisheyeController?.update(fx: fx, fy: fy, sx: dsx, sy: dsy)
metalFisheyeController?.scroll(dx: dx, dy: dy)
metalFisheyeController?.scroll(degreeX: degreeX, degreeY: degreeY)
```

with:

```swift
renderState.resetFisheyeViewport(width: viewportSize.width,
                                 height: viewportSize.height,
                                 resetTransform: resetTransform)
renderState.updateFallbackFisheye(fx: fx, fy: fy, sx: dsx, sy: dsy)
renderState.scrollFallbackFisheye(dx: dx, dy: dy)
renderState.scrollFallbackFisheye(degreeX: degreeX, degreeY: degreeY)
```

- [ ] **Step 4: Route mode setup through render state**

Replace the body of `setupMetalFish2PanoIfNeeded(renderMode:)` with:

```swift
renderState.configureFish2Pano(renderMode: renderMode)
```

Replace the body of `setupMetalFisheyeIfNeeded(renderMode:)` with:

```swift
renderState.configureFisheye(renderMode: renderMode,
                             viewportSize: CGSize(width: backingWidth, height: backingHeight))
```

To keep Task 3 independently compiling before Task 4, update the existing render helpers to read fish2pano params/textures and fisheye controller/parameter from `renderState` where the old setup-owned fields were removed. Do not move mesh, VR, distortion, or full render helper ownership yet; that belongs to Task 4.

- [ ] **Step 5: Compile and run setup-related focused tests**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRGLViewRenderStateTests -only-testing:IRPlayer-swiftTests/IRGLViewSnapshotTests/testFisheyeModeWithoutProgramUsesFallbackControllerForGestures -only-testing:IRPlayer-swiftTests/IRGLViewSnapshotTests/testRenderModeSelectionRequiresRegisteredMode
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```sh
git add Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift
git commit -m "refactor: route gl view state setup through helper"
```

---

### Task 4: Move Mode-Specific Render Cache Usage Into Render State

**Files:**
- Modify: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderState.swift`
- Modify: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift`

- [ ] **Step 1: Move cache-backed render helper logic to state**

Move the bodies of these `IRGLView` helpers into `IRGLViewRenderState`, preserving signatures except for explicit dependencies:

```swift
func renderMulti4PIfNeeded(frame: IRFFVideoFrame,
                           mode: IRGLRenderMode?,
                           renderer: IRGLRenderInternal,
                           drawable: CAMetalDrawable,
                           drawableSize: CGSize,
                           device: MTLDevice?) -> Bool?

func renderFish2PanoIfNeeded(frame: IRFFVideoFrame,
                             mode: IRGLRenderMode?,
                             renderer: IRGLRenderInternal,
                             drawable: CAMetalDrawable,
                             drawableSize: CGSize,
                             renderContentMode: IRGLRenderContentMode,
                             device: MTLDevice?) -> Bool?

func renderDistortionIfNeeded(frame: IRFFVideoFrame,
                              mode: IRGLRenderMode?,
                              renderer: IRGLRenderInternal,
                              drawable: CAMetalDrawable,
                              drawableSize: CGSize,
                              renderContentMode: IRGLRenderContentMode,
                              device: MTLDevice?) -> Bool?

func renderFisheyeIfNeeded(frame: IRFFVideoFrame,
                           mode: IRGLRenderMode?,
                           renderer: IRGLRenderInternal,
                           drawable: CAMetalDrawable,
                           drawableSize: CGSize,
                           device: MTLDevice?) -> Bool?

func renderVRIfNeeded(frame: IRFFVideoFrame,
                      mode: IRGLRenderMode?,
                      renderer: IRGLRenderInternal,
                      drawable: CAMetalDrawable,
                      drawableSize: CGSize,
                      device: MTLDevice?) -> Bool?
```

Use `IRGLViewPolicy.translationVector(for:)` inside state methods instead of `IRGLView.translationVector(for:)`.

- [ ] **Step 2: Replace `IRGLView` render helper calls with state calls**

In `renderCurrentContent()`, replace:

```swift
renderMetalMulti4PIfNeeded(frame: frame, renderer: renderer, drawable: drawable, drawableSize: drawableSize)
renderMetalFish2PanoIfNeeded(frame: frame, renderer: renderer, drawable: drawable, drawableSize: drawableSize)
renderMetalDistortionIfNeeded(frame: frame, renderer: renderer, drawable: drawable, drawableSize: drawableSize)
renderMetalFisheyeIfNeeded(frame: frame, renderer: renderer, drawable: drawable, drawableSize: drawableSize)
renderMetalVRIfNeeded(frame: frame, renderer: renderer, drawable: drawable, drawableSize: drawableSize)
```

with:

```swift
renderState.renderMulti4PIfNeeded(frame: frame,
                                  mode: mode,
                                  renderer: renderer,
                                  drawable: drawable,
                                  drawableSize: drawableSize,
                                  device: device)
renderState.renderFish2PanoIfNeeded(frame: frame,
                                    mode: mode,
                                    renderer: renderer,
                                    drawable: drawable,
                                    drawableSize: drawableSize,
                                    renderContentMode: renderContentMode,
                                    device: device)
renderState.renderDistortionIfNeeded(frame: frame,
                                     mode: mode,
                                     renderer: renderer,
                                     drawable: drawable,
                                     drawableSize: drawableSize,
                                     renderContentMode: renderContentMode,
                                     device: device)
renderState.renderFisheyeIfNeeded(frame: frame,
                                  mode: mode,
                                  renderer: renderer,
                                  drawable: drawable,
                                  drawableSize: drawableSize,
                                  device: device)
renderState.renderVRIfNeeded(frame: frame,
                             mode: mode,
                             renderer: renderer,
                             drawable: drawable,
                             drawableSize: drawableSize,
                             device: device)
```

- [ ] **Step 3: Remove moved helpers from `IRGLView`**

Delete these private methods from `IRGLView` after their logic exists in `IRGLViewRenderState`:

```swift
private func renderMetalMulti4PIfNeeded(frame: IRFFVideoFrame,
                                        renderer: IRGLRenderInternal,
                                        drawable: CAMetalDrawable,
                                        drawableSize: CGSize) -> Bool?
private func renderMetalFish2PanoIfNeeded(frame: IRFFVideoFrame,
                                          renderer: IRGLRenderInternal,
                                          drawable: CAMetalDrawable,
                                          drawableSize: CGSize) -> Bool?
private func renderMetalDistortionIfNeeded(frame: IRFFVideoFrame,
                                           renderer: IRGLRenderInternal,
                                           drawable: CAMetalDrawable,
                                           drawableSize: CGSize) -> Bool?
private func makeTexUVTexture(width: Int,
                              height: Int,
                              data: UnsafeMutablePointer<GLfloat>) -> MTLTexture?
private func renderMetalFisheyeIfNeeded(frame: IRFFVideoFrame,
                                        renderer: IRGLRenderInternal,
                                        drawable: CAMetalDrawable,
                                        drawableSize: CGSize) -> Bool?
private func renderMetalVRIfNeeded(frame: IRFFVideoFrame,
                                   renderer: IRGLRenderInternal,
                                   drawable: CAMetalDrawable,
                                   drawableSize: CGSize) -> Bool?
```

Keep `static func texUVTextureLayout(width:height:)` in `IRGLView` as a compatibility wrapper for existing tests.

- [ ] **Step 4: Run focused render tests**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRGLViewRenderStateTests -only-testing:IRPlayer-swiftTests/IRGLViewSnapshotTests
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```sh
git add Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderState.swift Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift
git commit -m "refactor: move gl view render caches into state"
```

---

### Task 5: Extract Render Coordinator

**Files:**
- Create: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderCoordinator.swift`
- Modify: `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift`
- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create coordinator file**

Add `Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderCoordinator.swift`:

```swift
//
//  IRGLViewRenderCoordinator.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import CoreGraphics
import CoreImage
import Metal
import QuartzCore
import UIKit

final class IRGLViewRenderCoordinator {
    struct Context {
        let metalLayer: CAMetalLayer
        let currentFrame: IRFFVideoFrame?
        let currentImage: CIImage?
        let mode: IRGLRenderMode?
        let fallbackRenderer: IRGLRenderInternal?
        let renderContentMode: IRGLRenderContentMode
        let device: MTLDevice?
        let commandQueue: MTLCommandQueue?
        let ciContext: CIContext?
        let colorSpace: CGColorSpace
        let renderState: IRGLViewRenderState
        let makeImage: (IRFFVideoFrame) -> CIImage?
        let fitImage: (CIImage, CGRect) -> CIImage
    }

    struct Result {
        let currentImage: CIImage?
        let didCompleteRender: Bool
    }

    func render(context: Context) -> Result {
        let metalLayer = context.metalLayer
        let drawableSize = metalLayer.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else {
            return Result(currentImage: context.currentImage, didCompleteRender: false)
        }

        if let frame = context.currentFrame,
           let renderer = (context.mode?.renderer as? IRGLRenderInternal) ?? context.fallbackRenderer,
           let drawable = metalLayer.nextDrawable() {
            context.mode?.program?.setRenderFrame(frame)
            if let result = context.renderState.renderMulti4PIfNeeded(frame: frame,
                                                                      mode: context.mode,
                                                                      renderer: renderer,
                                                                      drawable: drawable,
                                                                      drawableSize: drawableSize,
                                                                      device: context.device),
               result {
                return Result(currentImage: context.currentImage, didCompleteRender: true)
            }
            if let result = context.renderState.renderFish2PanoIfNeeded(frame: frame,
                                                                       mode: context.mode,
                                                                       renderer: renderer,
                                                                       drawable: drawable,
                                                                       drawableSize: drawableSize,
                                                                       renderContentMode: context.renderContentMode,
                                                                       device: context.device),
               result {
                return Result(currentImage: context.currentImage, didCompleteRender: true)
            }
            if let result = context.renderState.renderDistortionIfNeeded(frame: frame,
                                                                        mode: context.mode,
                                                                        renderer: renderer,
                                                                        drawable: drawable,
                                                                        drawableSize: drawableSize,
                                                                        renderContentMode: context.renderContentMode,
                                                                        device: context.device),
               result {
                return Result(currentImage: context.currentImage, didCompleteRender: true)
            }
            if let result = context.renderState.renderFisheyeIfNeeded(frame: frame,
                                                                     mode: context.mode,
                                                                     renderer: renderer,
                                                                     drawable: drawable,
                                                                     drawableSize: drawableSize,
                                                                     device: context.device),
               result {
                return Result(currentImage: context.currentImage, didCompleteRender: true)
            }
            if let result = context.renderState.renderVRIfNeeded(frame: frame,
                                                                mode: context.mode,
                                                                renderer: renderer,
                                                                drawable: drawable,
                                                                drawableSize: drawableSize,
                                                                device: context.device),
               result {
                return Result(currentImage: context.currentImage, didCompleteRender: true)
            }

            let zoomScale = Float((context.mode?.program?.getCurrentScale().x) ?? 1)
            let translation = IRGLViewPolicy.translationVector(for: (context.mode?.program as? IRGLProgram2D)?.tramsformController?.getScope())
            if renderer.render(frame: frame,
                               to: drawable,
                               contentMode: context.renderContentMode,
                               drawableSize: drawableSize,
                               zoomScale: zoomScale,
                               translation: translation) {
                return Result(currentImage: context.currentImage, didCompleteRender: true)
            }
            if frame is IRFFCVYUVVideoFrame || frame is IRFFAVYUVVideoFrame {
                return Result(currentImage: context.currentImage, didCompleteRender: false)
            }
        }

        var image = context.currentImage
        if image == nil, let frame = context.currentFrame {
            image = context.makeImage(frame)
        }
        guard let currentImage = image else {
            return Result(currentImage: image, didCompleteRender: false)
        }
        guard let drawable = metalLayer.nextDrawable() else {
            return Result(currentImage: image, didCompleteRender: false)
        }
        guard let commandQueue = context.commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let ciContext = context.ciContext else {
            return Result(currentImage: image, didCompleteRender: false)
        }

        let targetRect = CGRect(origin: .zero, size: metalLayer.drawableSize)
        guard targetRect.width > 0, targetRect.height > 0 else {
            return Result(currentImage: image, didCompleteRender: false)
        }
        let fittedImage = context.fitImage(currentImage, targetRect)

        ciContext.render(fittedImage,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: targetRect,
                         colorSpace: context.colorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return Result(currentImage: image, didCompleteRender: true)
    }
}
```

- [ ] **Step 2: Add coordinator to Xcode framework target**

Modify `IRPlayer-swift.xcodeproj/project.pbxproj`:

```text
B5E960052F7107020149265 /* IRGLViewRenderCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = B5E960042F7107020149265 /* IRGLViewRenderCoordinator.swift */; };
B5E960042F7107020149265 /* IRGLViewRenderCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IRGLViewRenderCoordinator.swift; sourceTree = "<group>"; };
B5E960042F7107020149265 /* IRGLViewRenderCoordinator.swift */,
B5E960052F7107020149265 /* IRGLViewRenderCoordinator.swift in Sources */,
```

- [ ] **Step 3: Add coordinator property to `IRGLView`**

Add near `renderState`:

```swift
private let renderCoordinator = IRGLViewRenderCoordinator()
```

- [ ] **Step 4: Replace `renderCurrentContent()` body with coordinator call**

Use this body:

```swift
private func renderCurrentContent() {
    guard let metalLayer = metalLayer else { return }
    let result = renderCoordinator.render(
        context: IRGLViewRenderCoordinator.Context(
            metalLayer: metalLayer,
            currentFrame: currentFrame,
            currentImage: currentImage,
            mode: mode,
            fallbackRenderer: metalRenderer,
            renderContentMode: renderContentMode,
            device: device,
            commandQueue: commandQueue,
            ciContext: ciContext,
            colorSpace: colorSpace,
            renderState: renderState,
            makeImage: { [weak self] frame in
                self?.makeImage(from: frame)
            },
            fitImage: { [weak self] image, rect in
                self?.fitImage(image, in: rect) ?? image
            }
        )
    )
    currentImage = result.currentImage
    if result.didCompleteRender {
        saveSnapShot()
    }
}
```

- [ ] **Step 5: Run focused dispatch tests**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRGLViewSnapshotTests -only-testing:IRPlayer-swiftTests/IRGLRenderStrategyFactoryTests
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```sh
git add Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderCoordinator.swift Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "refactor: extract gl view render coordinator"
```

---

### Task 6: Final Verification And Cleanup

**Files:**
- Modify only files already touched by Tasks 1-5 if verification exposes issues inside this slice.

- [ ] **Step 1: Confirm no forbidden subsystem changes**

Run:

```sh
git diff --name-only main...HEAD
```

Expected changed paths are limited to:

```text
docs/superpowers/specs/2026-07-07-render-pipeline-refactor-design.md
docs/superpowers/plans/2026-07-07-render-pipeline-refactor.md
Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift
Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderState.swift
Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderCoordinator.swift
Tests/IRPlayer-swiftTests/IRGLViewRenderStateTests.swift
Tests/IRPlayer-swiftTests/IRGLViewSnapshotTests.swift
IRPlayer-swift.xcodeproj/project.pbxproj
```

- [ ] **Step 2: Run whitespace check**

Run:

```sh
git diff --check
```

Expected: no output and exit code `0`.

- [ ] **Step 3: Run focused render suite**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID" -only-testing:IRPlayer-swiftTests/IRGLViewRenderStateTests -only-testing:IRPlayer-swiftTests/IRGLViewSnapshotTests -only-testing:IRPlayer-swiftTests/IRGLRenderStrategyFactoryTests -only-testing:IRPlayer-swiftTests/IRMetalRendererPixelFormatTests -only-testing:IRPlayer-swiftTests/IRMetalRendererDistortionTests
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [ ] **Step 4: Run full iOS simulator suite**

Run:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination "id=$FOCUSED_DESTINATION_ID"
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit verification fixes when verification created changes**

If Step 2, Step 3, or Step 4 required changes inside the allowed paths, commit them:

```sh
git add Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLView.swift Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderState.swift Sources/IRPlayer-swift/Class/Core/Display/RenderKit/IRGLViewRenderCoordinator.swift Tests/IRPlayer-swiftTests/IRGLViewRenderStateTests.swift Tests/IRPlayer-swiftTests/IRGLViewSnapshotTests.swift IRPlayer-swift.xcodeproj/project.pbxproj
git commit -m "fix: stabilize render pipeline refactor"
```

- [ ] **Step 6: Report final status**

Include:

- Final branch name.
- Commit list after `main`.
- Focused test results.
- Full simulator test result.
- Any warnings that remain, especially existing deprecation warnings unrelated to this slice.
