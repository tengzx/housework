//
//  HealthDataExportTests.swift
//  HealthDataExportTests
//
//  Created by tengzx on 8.6.2026.
//

import Foundation
import HealthKit
import Testing
@testable import HealthDataExport

struct HealthDataExportTests {

    @Test func sleepMinutesUsePerRecordRounding() async throws {
        let start = Date(timeIntervalSince1970: 0)
        let firstEnd = start.addingTimeInterval((10 * 60) + 24)
        let secondStart = firstEnd
        let secondEnd = secondStart.addingTimeInterval((10 * 60) + 24)

        let firstRounded = SleepMinuteMath.roundedMinutes(from: start, to: firstEnd)
        let secondRounded = SleepMinuteMath.roundedMinutes(from: secondStart, to: secondEnd)
        let rawAggregateMinutes = secondEnd.timeIntervalSince(start) / 60

        #expect(firstRounded == 10)
        #expect(secondRounded == 10)
        #expect(firstRounded + secondRounded == 20)
        #expect(Int(rawAggregateMinutes.rounded()) == 21)
    }

    @Test func overlappingInBedIntervalsAreOnlyCountedOnce() async throws {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(6 * 60 * 60)
        let overlappingStart = start.addingTimeInterval(10 * 60)
        let overlappingEnd = end.addingTimeInterval(-10 * 60)

        let unionMinutes = SleepMinuteMath.roundedUnionMinutes(from: [
            (start, end),
            (overlappingStart, overlappingEnd)
        ])

        #expect(unionMinutes == 360)
    }

    @Test func genericAsleepIsDroppedWhenDetailedSleepStagesExist() async throws {
        if #available(iOS 16.0, *) {
            let values = [
                HKCategoryValueSleepAnalysis.asleep.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.awake.rawValue
            ]
            #expect(SleepSampleFilter.shouldDropGenericAsleep(from: values))
        }
    }

    @Test func genericAsleepIsKeptWhenNoDetailedSleepStagesExist() async throws {
        let values = [
            HKCategoryValueSleepAnalysis.inBed.rawValue,
            HKCategoryValueSleepAnalysis.asleep.rawValue
        ]
        #expect(!SleepSampleFilter.shouldDropGenericAsleep(from: values))
    }

}
