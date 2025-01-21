//
//  PlayerViewController.swift
//  demo
//
//  Created by Phil Chang on 2022/4/22.
//  Copyright © 2022 Phil. All rights reserved.
//

import Foundation
import UIKit
import IRPlayerSwift

enum DemoType: UInt {
    case avPlayerNormal
    case avPlayerVR
    case avPlayerVRBox
    case ffmpegNormal
    case ffmpegNormalHardware
    case ffmpegFisheyeHardware
    case ffmpegPanoramaHardware
    case ffmpegMultiModesHardwareModesSelection
}

class PlayerViewController: UIViewController {

    static let displayNames = ["i see fire, AVPlayer",
                               "google help, AVPlayer, VR",
                               "google help, AVPlayer, VR, Box",
                               "i see fire, FFmpeg",
                               "i see fire, FFmpeg, Hardware Decode",
                               "fisheye-demo, FFmpeg, Fisheye Mode",
                               "fisheye-demo, FFmpeg, Pano Mode",
                               "fisheye-demo, FFmpeg, Multi Modes"]

    static let normalVideo = URL.init(fileURLWithPath: Bundle.main.path(forResource: "i-see-fire", ofType: "mp4") ?? "")
    static let vrVideo = URL.init(fileURLWithPath: Bundle.main.path(forResource: "google-help-vr", ofType: "mp4") ?? "")
    static let fisheyeVideo = URL.init(fileURLWithPath: Bundle.main.path(forResource: "fisheye-demo", ofType: "mp4") ?? "")

    var demoType: DemoType = .avPlayerNormal
    var progressSilderTouching: Bool = false
    lazy var player: IRPlayerImp = {
        return IRPlayerImp.player()
    }()
    var modes: [IRGLRenderMode]?
    var playerNotification: IRPlayerNotification?

    @IBOutlet weak var mainView: UIView!
    @IBOutlet weak var stateLabel: UILabel!
    @IBOutlet weak var currentTimeLabel: UILabel!
    @IBOutlet weak var progressSilder: UISlider!
    @IBOutlet weak var totalTimeLabel: UILabel!
    @IBOutlet weak var modesButton: UIButton!

    deinit {
        player.removePlayerNotification(target: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.player.registerPlayerNotification(target: self,
                                               stateAction: #selector(stateAction(_:)),
                                               progressAction: #selector(progressAction(_:)),
                                               playableAction: #selector(playableAction(_:)),
                                               errorAction: #selector(errorAction(_:)))
        self.player.viewTapAction = { (player, view) in
            print("player display view did click!")
        }
        if let playerView = self.player.view {
            self.mainView.insertSubview(playerView, at: 0)
        }

        switch self.demoType {
        case .avPlayerNormal:
            self.player.replaceVideoWithURL(contentURL: PlayerViewController.normalVideo as NSURL, videoType: .normal)
        case .avPlayerVR:
            self.player.replaceVideoWithURL(contentURL: PlayerViewController.vrVideo as NSURL, videoType: .vr)
        case .avPlayerVRBox:
            self.player.displayMode = .box
            self.player.replaceVideoWithURL(contentURL: PlayerViewController.vrVideo as NSURL, videoType: .vr)
        case .ffmpegNormal:
            self.player.decoder.mpeg4Format = .ffmpeg
            self.player.decoder.ffmpegHardwareDecoderEnable = false
            self.player.replaceVideoWithURL(contentURL: PlayerViewController.normalVideo as NSURL, videoType: .normal)
        case .ffmpegNormalHardware:
            self.player.decoder = IRPlayerDecoder.FFmpegDecoder()
            self.player.replaceVideoWithURL(contentURL: PlayerViewController.normalVideo as NSURL, videoType: .normal)
        case .ffmpegFisheyeHardware:
            self.player.decoder = IRPlayerDecoder.FFmpegDecoder()
            #if TARGET_IPHONE_SIMULATOR
            self.player.decoder.ffmpegHardwareDecoderEnable = false
            #endif
            self.player.replaceVideoWithURL(contentURL: PlayerViewController.fisheyeVideo as NSURL, videoType: .fisheye)
        case .ffmpegPanoramaHardware:
            self.player.decoder = IRPlayerDecoder.FFmpegDecoder()
            #if TARGET_IPHONE_SIMULATOR
            self.player.decoder.ffmpegHardwareDecoderEnable = false
            #endif
            self.player.replaceVideoWithURL(contentURL: PlayerViewController.fisheyeVideo as NSURL, videoType: .pano)
        case .ffmpegMultiModesHardwareModesSelection:
            self.player.decoder = IRPlayerDecoder.FFmpegDecoder()
            let sharedRender: IRGLRender
            modes = self.createFisheyeModes(with: nil)
            #if TARGET_IPHONE_SIMULATOR
            sharedRender = IRGLRenderYUV()
            self.player.decoder.ffmpegHardwareDecoderEnable = false
            #else
            sharedRender = IRGLRenderNV12()
            for mode in modes ?? [] {
                mode.renderer = sharedRender;
            }
            #endif
            self.player.renderModes = modes
            self.player.replaceVideoWithURL(contentURL: PlayerViewController.fisheyeVideo as NSURL, videoType: .custom)
            self.modesButton.isHidden = false
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.player.updateGraphicsViewFrame(frame: self.view.bounds)
    }

    func createFisheyeModes(with parameter: IRMediaParameter?) -> [IRGLRenderMode] {
        let normal = IRGLRenderMode2D()
        let fisheye2Pano = IRGLRenderMode2DFisheye2Pano()
        let fisheye = IRGLRenderMode3DFisheye()
        let fisheye4P = IRGLRenderModeMulti4P()
        let modes = [
            fisheye2Pano,
            fisheye,
            fisheye4P,
            normal
        ]

        normal.shiftController.enabled = false
        fisheye2Pano.contentMode = .scaleAspectFill
        fisheye2Pano.wideDegreeX = 360
        fisheye2Pano.wideDegreeY = 20
        fisheye4P.parameter = IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 80)
        fisheye.parameter = IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 80)
//        fisheye4P.parameter = fisheye.parameter
        fisheye4P.aspect = 16.0 / 9.0
        fisheye.aspect = fisheye4P.aspect

        normal.name = "Rawdata"
        fisheye2Pano.name = "Panorama"
        fisheye.name = "Onelen"
        fisheye4P.name = "Fourlens"

        return modes
    }

    class func displayName(for demoType: DemoType) -> String? {
        if demoType.rawValue < displayNames.count {
            return displayNames[Int(demoType.rawValue)]
        }
        return nil
    }

    @IBAction func modes(_ sender: Any) {
        showRenderModeMenu()
    }

    @IBAction func play(_ sender: Any) {
        player.play()
    }

    @IBAction func pause(_ sender: Any) {
        player.pause()
    }

    @IBAction func progressTouchDown(_ sender: Any) {
        self.progressSilderTouching = true
    }
    
    @IBAction func progressTouchUp(_ sender: Any) {
        self.progressSilderTouching = false
        self.player.seekToTime(time: self.player.duration * Double(self.progressSilder.value))
    }
}

extension PlayerViewController {

    @IBAction func back(_ sender: Any) {
        self.navigationController?.popViewController(animated: true)
    }

    func showRenderModeMenu() {
        guard let aryModes = modes else { return }

        if aryModes.count > 0 {
            var aryStreamsTitle = [String]()
            var aryStreamsCheckMark = [UITableViewCell.AccessoryType]()

            let currentRenderMode = player.renderMode

            let alertView = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

            for (index, mode) in aryModes.enumerated() {
                if let tmpRenderMode = mode as? IRGLRenderMode {
                    let renderModeStr = tmpRenderMode.name
                    aryStreamsTitle.append(renderModeStr)

                    if tmpRenderMode == currentRenderMode {
                        aryStreamsCheckMark.append(.checkmark)
                    } else {
                        aryStreamsCheckMark.append(.none)
                    }

                    let itemAction = UIAlertAction(title: renderModeStr, style: .default) { [weak self] action in
                        guard let self = self else { return }
                        if let tmpRenderMode = aryModes[index] as? IRGLRenderMode {
                            self.player.selectRenderMode(renderMode: tmpRenderMode)
                        }
                    }

                    alertView.addAction(itemAction)
                }
            }

            present(alertView, animated: true, completion: nil)
        }
    }
}

extension PlayerViewController {

    @objc func stateAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let state = IRState.state(fromUserInfo: userInfo)
        var text: String?
        switch state.current {
        case .none:
            text = "None"
        case .buffering:
            text = "Buffering..."
        case .readyToPlay:
            text = "Prepare"
            self.totalTimeLabel.text = self.timeString(from: self.player.duration)
            self.player.play()
        case .playing:
            text = "Playing"
        case .suspend:
            text = "Suspend"
        case .finished:
            text = "Finished"
        case .failed:
            text = "Error"
        @unknown default:
            text = "@unknown"
        }
        self.stateLabel.text = text
    }

    @objc func progressAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let progress = IRProgress.progress(fromUserInfo: userInfo)
        if !progressSilderTouching {
            progressSilder.value = Float(progress.percent)
        }
        currentTimeLabel.text = timeString(from: progress.current)
    }

    @objc func playableAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let playable = IRPlayable.playable(fromUserInfo: userInfo)
        print("playable time : \(playable.current)")
    }

    @objc func errorAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let error = IRError.error(fromUserInfo: userInfo)
        print("player did error : \(error.error)")
    }
}

extension PlayerViewController {

    func timeString(from seconds: CGFloat) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%02d:%02d", minutes, remainingSeconds)
        }
    }
}
