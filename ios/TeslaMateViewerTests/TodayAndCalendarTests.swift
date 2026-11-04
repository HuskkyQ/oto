import XCTest
@testable import TeslaMate

/// The pure parts of the day board and the trip calendar: state clipping, the month grid, and
/// the two derived row figures.
@MainActor
final class TodayAndCalendarTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))!
        return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: base)!
    }

    private func bucket(_ day: Date, drive: Int = 0, distance: Double = 0, duration: Int = 0, charge: Int = 0) -> StatsBucket {
        StatsBucket(
            bucket: day,
            driveCount: drive,
            distanceKm: distance,
            durationMin: duration,
            chargeCount: charge,
            chargeEnergyKwh: 0,
            chargeCost: nil
        )
    }

    // MARK: - State band

    func testCoveringStateFromYesterdayIsClippedToMidnight() {
        let dayStart = calendar.startOfDay(for: Date())
        let now = date(9)

        let periods = [
            StatePeriod(state: "asleep", startDate: date(22, dayOffset: -1), endDate: date(1)),
            StatePeriod(state: "online", startDate: date(1), endDate: date(9))
        ]

        let slices = TodayViewModel.slices(from: periods, dayStart: dayStart, now: now)

        XCTAssertEqual(slices.map(\.state), ["asleep", "online"])
        XCTAssertEqual(slices[0].minutes, 60)
        XCTAssertEqual(slices[1].minutes, 8 * 60)
    }

    func testHoleBetweenStatesBecomesUnknown() {
        let dayStart = calendar.startOfDay(for: Date())

        let periods = [
            StatePeriod(state: "asleep", startDate: date(0), endDate: date(2)),
            StatePeriod(state: "online", startDate: date(4), endDate: date(6))
        ]

        let slices = TodayViewModel.slices(from: periods, dayStart: dayStart, now: date(6))

        XCTAssertEqual(slices.map(\.state), ["asleep", "unknown", "online"])
        XCTAssertEqual(slices[1].minutes, 120)
    }

    func testOngoingStateEndsAtNow() {
        let dayStart = calendar.startOfDay(for: Date())

        let periods = [StatePeriod(state: "online", startDate: date(0), endDate: nil)]
        let slices = TodayViewModel.slices(from: periods, dayStart: dayStart, now: date(3))

        XCTAssertEqual(slices.map(\.state), ["online"])
        XCTAssertEqual(slices[0].minutes, 180)
    }

    func testBandMinutesMatchTheElapsedDay() {
        let dayStart = calendar.startOfDay(for: Date())
        let periods = [StatePeriod(state: "asleep", startDate: date(0), endDate: nil)]

        let slices = TodayViewModel.slices(from: periods, dayStart: dayStart, now: date(12))

        XCTAssertEqual(slices.reduce(0) { $0 + $1.minutes }, 12 * 60)
    }

    // MARK: - Calendar grid

    func testGridZeroFillsEveryDayOfTheMonth() {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        let october = calendar.date(from: components)!
        let day18 = calendar.date(byAdding: .day, value: 17, to: october)!

        let grid = TripCalendarViewModel.grid(
            [bucket(day18, drive: 2, distance: 24.6, duration: 74)],
            month: october,
            calendar: calendar
        )

        XCTAssertEqual(grid.count, 31)
        XCTAssertEqual(grid.filter(\.hasDrive).count, 1)
        XCTAssertEqual(grid[17].bucket.distanceKm, 24.6)
        XCTAssertEqual(grid[0].bucket.driveCount, 0)
    }

    func testOctober2026StartsOnThursdaySoThreeBlanks() {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        let october = calendar.date(from: components)!

        let model = TripCalendarViewModel(month: october)

        XCTAssertEqual(model.leadingBlanks, 3)
        XCTAssertEqual(model.title, "2026 年 10 月")
    }

    func testCalendarCannotMoveIntoTheFuture() {
        let model = TripCalendarViewModel(month: Date())
        XCTAssertFalse(model.canGoForward)

        model.goBack()
        XCTAssertTrue(model.canGoForward)
    }

    // MARK: - Row figures

    func testAchievementIsDistanceOverIdealRangeSpent() {
        let drive = sampleDrive(distanceKm: 14.8, durationMin: 34, startIdeal: 300, endIdeal: 284)

        XCTAssertEqual(drive.achievementPercent, 93)
        XCTAssertEqual(drive.averageSpeedKmh ?? 0, 26.1, accuracy: 0.1)
        XCTAssertEqual(drive.batteryTransition, "78% → 71%")
    }

    func testAchievementHiddenWhenTheRangeDidNotMove() {
        let drive = sampleDrive(distanceKm: 14.8, durationMin: 34, startIdeal: 300, endIdeal: 300)
        XCTAssertNil(drive.achievementPercent)
    }

    private func sampleDrive(
        distanceKm: Double,
        durationMin: Int,
        startIdeal: Double,
        endIdeal: Double
    ) -> Drive {
        Drive(
            id: 1,
            startDate: Date(),
            endDate: Date(),
            distanceKm: distanceKm,
            durationMin: durationMin,
            speedMax: 80,
            powerMax: 100,
            powerMin: -40,
            startKm: 32_000,
            endKm: 32_014.8,
            startIdealRangeKm: startIdeal,
            endIdealRangeKm: endIdeal,
            startRatedRangeKm: 320,
            endRatedRangeKm: 304,
            startBatteryLevel: 78,
            endBatteryLevel: 71,
            outsideTempAvg: 14,
            insideTempAvg: 20,
            ascent: 10,
            descent: 8,
            startAddress: nil,
            startAddressDisplay: nil,
            endAddress: nil,
            endAddressDisplay: nil,
            startGeofence: "家",
            endGeofence: "公司"
        )
    }
}
