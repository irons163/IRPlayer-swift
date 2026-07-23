import AVFoundation
import Foundation

final class IRAVPlayerSession: @unchecked Sendable {
    enum Phase: Equatable {
        case empty
        case building
        case active
        case reconfiguring
        case resetting
        case closed
    }

    struct Token: Hashable, Sendable {
        fileprivate let generation: UInt64
    }

    enum ItemEvent {
        case statusChanged
        case playbackBufferEmptyChanged
        case loadedTimeRangesChanged
        case didPlayToEnd
    }

    struct Resources {
        let token: Token
        let asset: AVURLAsset
        let item: AVPlayerItem
        let player: AVPlayer
        let output: AVPlayerItemVideoOutput?
    }

    struct Diagnostics: Equatable {
        let phase: Phase
        let generation: UInt64?
        let hasAsset: Bool
        let hasItem: Bool
        let hasPlayer: Bool
        let hasOutput: Bool
        let itemObservationCount: Int
        let hasEndObserver: Bool
        let hasPeriodicTimeObserver: Bool
        let externalLeaseCount: Int
        let activationCount: Int
        let resetCount: Int
        let outputRebuildCount: Int
    }

    typealias ItemEventHandler = (Token, AVPlayerItem, ItemEvent) -> Void
    typealias PeriodicTimeHandler = (Token, CMTime) -> Void

    private struct OwnedResources {
        let token: Token
        let asset: AVURLAsset
        let item: AVPlayerItem
        let player: AVPlayer
        var output: AVPlayerItemVideoOutput?
        let itemObservations: [NSKeyValueObservation]
        let endObserver: NSObjectProtocol
        let periodicTimeObserver: Any
        let resourceLoaderDelegate: IRAVPlayerResourceLoaderDelegate?
        let resourceLoaderQueue: DispatchQueue?
        let itemEventHandler: ItemEventHandler
        let periodicTimeHandler: PeriodicTimeHandler
    }

    private let condition = NSCondition()
    private let mutationLock = NSLock()
    private let notificationCenter: NotificationCenter
    private var phase: Phase = .empty
    private var generationCounter: UInt64 = 0
    private var ownedResources: OwnedResources?
    private var externalLeaseCount = 0
    private var activationCount = 0
    private var resetCount = 0
    private var outputRebuildCount = 0

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    var diagnostics: Diagnostics {
        condition.lock()
        defer { condition.unlock() }
        return Diagnostics(
            phase: phase,
            generation: ownedResources?.token.generation,
            hasAsset: ownedResources != nil,
            hasItem: ownedResources != nil,
            hasPlayer: ownedResources != nil,
            hasOutput: ownedResources?.output != nil,
            itemObservationCount: ownedResources?.itemObservations.count ?? 0,
            hasEndObserver: ownedResources != nil,
            hasPeriodicTimeObserver: ownedResources != nil,
            externalLeaseCount: externalLeaseCount,
            activationCount: activationCount,
            resetCount: resetCount,
            outputRebuildCount: outputRebuildCount
        )
    }

    var currentToken: Token? {
        condition.lock()
        defer { condition.unlock() }
        guard acceptsIdentityChecks else { return nil }
        return ownedResources?.token
    }

    @discardableResult
    func activate(
        asset: AVURLAsset,
        automaticallyLoadedAssetKeys: [String]?,
        contentHeaders: [String: String]?,
        itemEventHandler: @escaping ItemEventHandler,
        periodicTimeHandler: @escaping PeriodicTimeHandler
    ) -> Token? {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard phaseSnapshot != .closed else { return nil }
        if let resources = drainResources(finalPhase: .empty) {
            teardown(resources)
        }

        condition.lock()
        generationCounter &+= 1
        let token = Token(generation: generationCounter)
        phase = .building
        condition.unlock()

        let loaderDelegate: IRAVPlayerResourceLoaderDelegate?
        let loaderQueue: DispatchQueue?
        if let contentHeaders, !contentHeaders.isEmpty {
            let delegate = IRAVPlayerResourceLoaderDelegate(
                contentHeaders: contentHeaders
            )
            let queue = DispatchQueue(
                label: "IRAVPlayer.AssetResourceLoader.\(token.generation)"
            )
            asset.resourceLoader.setDelegate(delegate, queue: queue)
            loaderDelegate = delegate
            loaderQueue = queue
        } else {
            loaderDelegate = nil
            loaderQueue = nil
        }

        let item: AVPlayerItem
        if let automaticallyLoadedAssetKeys {
            item = AVPlayerItem(
                asset: asset,
                automaticallyLoadedAssetKeys: automaticallyLoadedAssetKeys
            )
        } else {
            item = AVPlayerItem(asset: asset)
        }
        let player = AVPlayer(playerItem: item)

        let itemObservations = makeItemObservations(
            item: item,
            token: token
        )
        let endObserver = notificationCenter.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self, weak item] _ in
            guard let item else { return }
            self?.enqueueItemEvent(
                .didPlayToEnd,
                item: item,
                token: token
            )
        }
        let periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 1),
            queue: .main
        ) { [weak self] time in
            self?.deliverPeriodicTime(time, token: token)
        }

        let resources = OwnedResources(
            token: token,
            asset: asset,
            item: item,
            player: player,
            output: nil,
            itemObservations: itemObservations,
            endObserver: endObserver,
            periodicTimeObserver: periodicTimeObserver,
            resourceLoaderDelegate: loaderDelegate,
            resourceLoaderQueue: loaderQueue,
            itemEventHandler: itemEventHandler,
            periodicTimeHandler: periodicTimeHandler
        )

        condition.lock()
        guard phase == .building else {
            condition.unlock()
            teardown(resources)
            return nil
        }
        ownedResources = resources
        phase = .active
        activationCount += 1
        condition.broadcast()
        condition.unlock()
        return token
    }

    func withResources<Result>(
        default defaultValue: Result,
        _ body: (Resources) -> Result
    ) -> Result {
        condition.lock()
        guard phase == .active, let ownedResources else {
            condition.unlock()
            return defaultValue
        }
        externalLeaseCount += 1
        let resources = resourceSnapshot(from: ownedResources)
        condition.unlock()

        defer { releaseExternalLease() }
        return body(resources)
    }

    func isCurrent(
        _ token: Token,
        asset: AVURLAsset? = nil,
        item: AVPlayerItem? = nil,
        player: AVPlayer? = nil
    ) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard acceptsIdentityChecks,
              let ownedResources,
              ownedResources.token == token else {
            return false
        }
        if let asset, ownedResources.asset !== asset {
            return false
        }
        if let item, ownedResources.item !== item {
            return false
        }
        if let player, ownedResources.player !== player {
            return false
        }
        return true
    }

    @discardableResult
    func withCurrentPlayer(
        _ token: Token,
        _ body: (AVPlayer) -> Void
    ) -> Bool {
        withResources(default: false) { resources in
            guard resources.token == token else { return false }
            body(resources.player)
            return true
        }
    }

    @discardableResult
    func rebuildVideoOutput(for token: Token) -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        condition.lock()
        guard phase == .active,
              let resources = ownedResources,
              resources.token == token else {
            condition.unlock()
            return false
        }
        phase = .reconfiguring
        while externalLeaseCount > 0 {
            condition.wait()
        }
        let item = resources.item
        let previousOutput = resources.output
        condition.unlock()

        if let previousOutput,
           item.outputs.contains(where: { $0 === previousOutput }) {
            item.remove(previousOutput)
        }

        let output = Self.makeVideoOutput()
        item.add(output)

        condition.lock()
        guard phase == .reconfiguring,
              var currentResources = ownedResources,
              currentResources.token == token,
              currentResources.item === item else {
            condition.unlock()
            if item.outputs.contains(where: { $0 === output }) {
                item.remove(output)
            }
            return false
        }
        currentResources.output = output
        ownedResources = currentResources
        outputRebuildCount += 1
        phase = .active
        condition.broadcast()
        condition.unlock()
        return true
    }

    @discardableResult
    func reset() -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard phaseSnapshot != .closed else { return false }
        guard let resources = drainResources(finalPhase: .empty) else {
            return false
        }
        condition.lock()
        resetCount += 1
        condition.unlock()
        teardown(resources)
        return true
    }

    @discardableResult
    func close() -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard phaseSnapshot != .closed else { return false }
        let resources = drainResources(finalPhase: .closed)
        if let resources {
            teardown(resources)
        }
        return true
    }

    static func assetLoadDecision(
        keyStatuses: [AVKeyValueStatus],
        trackStatus: AVKeyValueStatus?
    ) -> IRAVPlayer.AVAssetLoadDecision {
        if keyStatuses.contains(.failed) {
            return .fail
        }
        if trackStatus == .loaded {
            return .setupOutput
        }
        return .ignore
    }

    static func resourceLoaderRedirectRequest(
        for request: URLRequest,
        headers: [String: String]?
    ) -> URLRequest? {
        guard let headers, !headers.isEmpty,
              request.url?.scheme?.lowercased() == "https" else {
            return nil
        }

        var redirectRequest = request
        headers.forEach { key, value in
            redirectRequest.setValue(value, forHTTPHeaderField: key)
        }
        return redirectRequest
    }

    private var phaseSnapshot: Phase {
        condition.lock()
        defer { condition.unlock() }
        return phase
    }

    private var acceptsIdentityChecks: Bool {
        phase == .active || phase == .reconfiguring
    }

    private func makeItemObservations(
        item: AVPlayerItem,
        token: Token
    ) -> [NSKeyValueObservation] {
        let status = item.observe(\.status, options: [.new]) {
            [weak self] item, _ in
            self?.enqueueItemEvent(
                .statusChanged,
                item: item,
                token: token
            )
        }
        let playbackBufferEmpty = item.observe(
            \.isPlaybackBufferEmpty,
            options: [.new]
        ) { [weak self] item, _ in
            self?.enqueueItemEvent(
                .playbackBufferEmptyChanged,
                item: item,
                token: token
            )
        }
        let loadedTimeRanges = item.observe(
            \.loadedTimeRanges,
            options: [.new]
        ) { [weak self] item, _ in
            self?.enqueueItemEvent(
                .loadedTimeRangesChanged,
                item: item,
                token: token
            )
        }
        return [status, playbackBufferEmpty, loadedTimeRanges]
    }

    private func enqueueItemEvent(
        _ event: ItemEvent,
        item: AVPlayerItem,
        token: Token
    ) {
        DispatchQueue.main.async { [weak self, weak item] in
            guard let self, let item else { return }
            self.deliverItemEvent(event, item: item, token: token)
        }
    }

    private func deliverItemEvent(
        _ event: ItemEvent,
        item: AVPlayerItem,
        token: Token
    ) {
        condition.lock()
        guard acceptsIdentityChecks,
              let resources = ownedResources,
              resources.token == token,
              resources.item === item else {
            condition.unlock()
            return
        }
        let handler = resources.itemEventHandler
        condition.unlock()
        handler(token, item, event)
    }

    private func deliverPeriodicTime(_ time: CMTime, token: Token) {
        let delivery = { [weak self] in
            guard let self else { return }
            self.condition.lock()
            guard self.acceptsIdentityChecks,
                  let resources = self.ownedResources,
                  resources.token == token else {
                self.condition.unlock()
                return
            }
            let handler = resources.periodicTimeHandler
            self.condition.unlock()
            handler(token, time)
        }
        if Thread.isMainThread {
            delivery()
        } else {
            DispatchQueue.main.async(execute: delivery)
        }
    }

    private func drainResources(finalPhase: Phase) -> OwnedResources? {
        condition.lock()
        guard phase != .closed else {
            condition.unlock()
            return nil
        }
        phase = .resetting
        while externalLeaseCount > 0 {
            condition.wait()
        }
        let resources = ownedResources
        ownedResources = nil
        phase = finalPhase
        condition.broadcast()
        condition.unlock()
        return resources
    }

    private func teardown(_ resources: OwnedResources) {
        resources.itemObservations.forEach { $0.invalidate() }
        notificationCenter.removeObserver(resources.endObserver)
        resources.player.removeTimeObserver(resources.periodicTimeObserver)

        resources.asset.cancelLoading()
        resources.asset.resourceLoader.setDelegate(nil, queue: nil)
        resources.item.cancelPendingSeeks()
        resources.player.pause()
        resources.player.cancelPendingPrerolls()
        resources.player.replaceCurrentItem(with: nil)

        if let output = resources.output,
           resources.item.outputs.contains(where: { $0 === output }) {
            resources.item.remove(output)
        }

        withExtendedLifetime(resources.resourceLoaderDelegate) {}
        withExtendedLifetime(resources.resourceLoaderQueue) {}
    }

    private func resourceSnapshot(
        from resources: OwnedResources
    ) -> Resources {
        Resources(
            token: resources.token,
            asset: resources.asset,
            item: resources.item,
            player: resources.player,
            output: resources.output
        )
    }

    private func releaseExternalLease() {
        condition.lock()
        externalLeaseCount -= 1
        if externalLeaseCount == 0 {
            condition.broadcast()
        }
        condition.unlock()
    }

    private static func makeVideoOutput() -> AVPlayerItemVideoOutput {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let output = AVPlayerItemVideoOutput(
            pixelBufferAttributes: attributes
        )
        output.requestNotificationOfMediaDataChange(
            withAdvanceInterval: IRAVPlayer.pixelBufferRequestInterval
        )
        return output
    }
}

private final class IRAVPlayerResourceLoaderDelegate:
    NSObject,
    AVAssetResourceLoaderDelegate
{
    private let contentHeaders: [String: String]

    init(contentHeaders: [String: String]) {
        self.contentHeaders = contentHeaders
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest:
            AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let redirectRequest =
            IRAVPlayerSession.resourceLoaderRedirectRequest(
                for: loadingRequest.request,
                headers: contentHeaders
            ) else {
            return false
        }
        loadingRequest.redirect = redirectRequest
        loadingRequest.finishLoading()
        return true
    }
}
