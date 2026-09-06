//
//  SPMDemoTests.swift
//  SPMDemoTests
//
//  Created by irons on 2024/12/12.
//

import Testing
import UIKit
import IRPlayerSwift
@testable import SPMDemo

struct SPMDemoTests {

    @MainActor
    @Test func preparedStateCannotOverwriteSynchronousPlayingCallback() {
        let controller = PlayerViewController()
        let stateLabel = UILabel()
        let durationLabel = UILabel()
        controller.stateLabel = stateLabel
        controller.totalTimeLabel = durationLabel
        var starts = 0

        controller.applyPlaybackState(.readyToPlay) {
            starts += 1
            #expect(stateLabel.text == "Prepare")
            controller.applyPlaybackState(.playing) {
                Issue.record("Playing must not auto-start again")
            }
        }

        #expect(starts == 1)
        #expect(stateLabel.text == "Playing")
    }

}
