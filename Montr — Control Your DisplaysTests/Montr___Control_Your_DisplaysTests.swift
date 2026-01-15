import XCTest
@testable import Montr

final class MontrTests: XCTestCase {

    override func setUpWithError() throws {
        // Reset settings before each test
    }

    override func tearDownWithError() throws {
        // Cleanup after tests
    }

    // MARK: - DisplaySettings Tests

    func testDisplaySettingsClamping() throws {
        var settings = DisplaySettings(
            displayId: "test",
            brightness: 150, // Over max
            colorTemperature: 1000 // Under min
        )

        XCTAssertEqual(settings.brightness, 100)
        XCTAssertEqual(settings.colorTemperature, 2700)
    }

    func testDisplaySettingsDefaultValues() throws {
        let settings = DisplaySettings(displayId: "test")

        XCTAssertEqual(settings.brightness, 75)
        XCTAssertEqual(settings.colorTemperature, 6500)
        XCTAssertFalse(settings.nightShiftEnabled)
    }

    // MARK: - TimeOfDay Tests

    func testTimeOfDayComparison() throws {
        let morning = TimeOfDay(hour: 8, minute: 0)
        let afternoon = TimeOfDay(hour: 14, minute: 30)
        let evening = TimeOfDay(hour: 20, minute: 0)

        XCTAssertTrue(morning < afternoon)
        XCTAssertTrue(afternoon < evening)
        XCTAssertFalse(evening < morning)
    }

    // MARK: - TimeRange Tests

    func testTimeRangeContainsSameDay() throws {
        // 9 AM to 5 PM
        let range = TimeRange(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 17, minute: 0)
        )

        XCTAssertFalse(range.spansMidnight)

        // Test times
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!

        XCTAssertTrue(range.contains(noon))
        XCTAssertFalse(range.contains(midnight))
    }

    func testTimeRangeContainsOverMidnight() throws {
        // 10 PM to 7 AM (spans midnight)
        let range = TimeRange(
            start: TimeOfDay(hour: 22, minute: 0),
            end: TimeOfDay(hour: 7, minute: 0)
        )

        XCTAssertTrue(range.spansMidnight)

        let calendar = Calendar.current
        let elevenPM = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        let threeAM = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: Date())!
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

        XCTAssertTrue(range.contains(elevenPM))
        XCTAssertTrue(range.contains(threeAM))
        XCTAssertFalse(range.contains(noon))
    }

    // MARK: - Profile Tests

    func testProfileCreation() throws {
        let profile = Profile(name: "Test Profile")

        XCTAssertEqual(profile.name, "Test Profile")
        XCTAssertTrue(profile.displaySettings.isEmpty)
        XCTAssertTrue(profile.triggers.isEmpty)
    }

    func testProfileSettingsUpdate() throws {
        var profile = Profile(name: "Test")

        let settings = DisplaySettings(displayId: "display1", brightness: 80)
        profile.updateSettings(settings)

        XCTAssertEqual(profile.displaySettings.count, 1)
        XCTAssertEqual(profile.settings(for: "display1")?.brightness, 80)
    }

    // MARK: - KelvinToRGB Tests

    func testKelvinToRGBDaylight() throws {
        let rgb = KelvinToRGB.convert(kelvin: 6500)

        // At 6500K (daylight), should be close to white (1, 1, 1)
        XCTAssertEqual(rgb.red, 1.0, accuracy: 0.1)
        XCTAssertEqual(rgb.green, 1.0, accuracy: 0.1)
        XCTAssertEqual(rgb.blue, 1.0, accuracy: 0.1)
    }

    func testKelvinToRGBCandlelight() throws {
        let rgb = KelvinToRGB.convert(kelvin: 2700)

        // At 2700K (candlelight), should be warm (more red, less blue)
        XCTAssertGreaterThan(rgb.red, rgb.blue)
        XCTAssertGreaterThan(rgb.green, rgb.blue)
    }

    // MARK: - NightShiftSchedule Tests

    func testNightShiftScheduleManual() throws {
        let schedule = NightShiftSchedule(mode: .manual)

        XCTAssertFalse(schedule.shouldBeActive())
    }

    func testNightShiftScheduleTransitionProgress() throws {
        let schedule = NightShiftSchedule(mode: .manual, transitionDuration: 30)
        let startTime = Date()

        // After 15 minutes (50% through 30 minute transition)
        let halfwayTime = startTime.addingTimeInterval(15 * 60)

        let progress = schedule.transitionProgress(
            currentTime: halfwayTime,
            targetActiveState: true,
            stateChangedAt: startTime
        )

        XCTAssertEqual(progress, 0.5, accuracy: 0.01)
    }
}
