//
//  IRFFDecodeAdmission.swift
//  IRPlayer-swift
//

import Foundation

/// Allocation-free capacity policy for bounded decode pipelines.
///
/// A producer may resume pending codec output whenever one destination credit
/// is available. New compressed input requires a larger packet headroom so a
/// multi-frame packet cannot immediately exhaust the backing frame pool.
enum IRFFDecodeAdmission {
    enum Phase:
        Equatable,
        Hashable,
        Sendable
    {
        case open
        case closed
    }

    struct Limits:
        Equatable,
        Hashable,
        Sendable
    {
        let frameCapacity: Int
        let packetHeadroom: Int

        init(
            frameCapacity: Int,
            packetHeadroom: Int
        ) {
            let boundedCapacity = max(0, frameCapacity)
            self.frameCapacity = boundedCapacity
            self.packetHeadroom = min(
                boundedCapacity,
                max(0, packetHeadroom)
            )
        }

        var highWatermark: Int {
            frameCapacity - packetHeadroom
        }
    }

    struct Snapshot:
        Equatable,
        Hashable,
        Sendable
    {
        let phase: Phase
        let limits: Limits
        let occupiedFrameCount: Int
        let availableCredits: Int

        init(
            limits: Limits,
            occupiedFrameCount: Int,
            phase: Phase = .open
        ) {
            self.phase = phase
            self.limits = limits

            let boundedOccupiedCount = min(
                limits.frameCapacity,
                max(0, occupiedFrameCount)
            )
            self.occupiedFrameCount =
                boundedOccupiedCount
            self.availableCredits =
                phase == .open
                ? limits.frameCapacity -
                    boundedOccupiedCount
                : 0
        }

        var highWatermark: Int {
            limits.highWatermark
        }

        var canResumeOutput: Bool {
            phase == .open &&
                availableCredits > 0
        }

        var canAdmitPacket: Bool {
            // Use a strict boundary: a newly admitted packet starts below the
            // high-water mark and may spend the reserved credits on multiple
            // decoded frames without exceeding the hard pool capacity.
            phase == .open &&
                limits.packetHeadroom > 0 &&
                availableCredits >
                    limits.packetHeadroom
        }

        var shouldThrottlePacketRead: Bool {
            !canAdmitPacket
        }
    }
}
