import Foundation
import CoreLocation
import Combine

/// Service for calculating sunrise and sunset times based on location
@MainActor
final class SunriseSunsetService: NSObject, ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @Published private(set) var sunrise: Date?
    @Published private(set) var sunset: Date?
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastUpdate: Date?

    // MARK: - Private Properties

    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var updateTimer: Timer?

    // MARK: - Singleton

    @MainActor static let shared = SunriseSunsetService()

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        setupDailyUpdate()
    }

    // MARK: - Public Methods

    /// Request location permission
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Update sunrise/sunset times
    func updateTimes() {
        if let location = lastLocation {
            calculateTimes(for: location)
        } else if locationStatus == .authorized || locationStatus == .authorizedAlways {
            locationManager.requestLocation()
        }
    }

    /// Check if currently between sunset and sunrise (night time)
    var isNightTime: Bool {
        guard let sunrise = sunrise, let sunset = sunset else {
            return false
        }

        let now = Date()

        // If sunset is after sunrise (same day), we're in night if after sunset OR before sunrise
        // This handles the midnight crossover
        if now >= sunset {
            return true
        }
        if now < sunrise {
            return true
        }
        return false
    }

    /// Get time until next sunrise
    var timeUntilSunrise: TimeInterval? {
        guard let sunrise = sunrise else { return nil }

        let now = Date()
        if now < sunrise {
            return sunrise.timeIntervalSince(now)
        }

        // Sunrise already passed today, calculate for tomorrow
        let calendar = Calendar.current
        if let tomorrowSunrise = calendar.date(byAdding: .day, value: 1, to: sunrise) {
            return tomorrowSunrise.timeIntervalSince(now)
        }

        return nil
    }

    /// Get time until next sunset
    var timeUntilSunset: TimeInterval? {
        guard let sunset = sunset else { return nil }

        let now = Date()
        if now < sunset {
            return sunset.timeIntervalSince(now)
        }

        // Sunset already passed today, calculate for tomorrow
        let calendar = Calendar.current
        if let tomorrowSunset = calendar.date(byAdding: .day, value: 1, to: sunset) {
            return tomorrowSunset.timeIntervalSince(now)
        }

        return nil
    }

    // MARK: - Private Methods

    private func setupDailyUpdate() {
        // Update times at midnight each day
        updateTimer?.invalidate()

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 0
        components.minute = 1
        components.second = 0

        if let midnight = calendar.date(from: components),
           let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight) {

            let timeUntilMidnight = nextMidnight.timeIntervalSinceNow

            // Schedule initial update
            DispatchQueue.main.asyncAfter(deadline: .now() + timeUntilMidnight) { [weak self] in
                self?.updateTimes()
                // Then update every 24 hours
                self?.updateTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.updateTimes()
                    }
                }
            }
        }
    }

    private func calculateTimes(for location: CLLocation) {
        let calculator = SolarCalculator(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        let today = Date()
        sunrise = calculator.sunrise(for: today)
        sunset = calculator.sunset(for: today)
        lastUpdate = Date()
    }
}

// MARK: - CLLocationManagerDelegate

extension SunriseSunsetService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            locationStatus = manager.authorizationStatus

            if manager.authorizationStatus == .authorized ||
               manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            lastLocation = location
            calculateTimes(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error)")

        // Use default location (approximate center of user's timezone)
        Task { @MainActor in
            let timeZone = TimeZone.current
            let longitude = Double(timeZone.secondsFromGMT()) / 3600.0 * 15.0
            let defaultLocation = CLLocation(latitude: 40.0, longitude: longitude)
            lastLocation = defaultLocation
            calculateTimes(for: defaultLocation)
        }
    }
}

// MARK: - Solar Calculator

private struct SolarCalculator {
    let latitude: Double
    let longitude: Double

    func sunrise(for date: Date) -> Date? {
        return calculateSunEvent(for: date, isSunrise: true)
    }

    func sunset(for date: Date) -> Date? {
        return calculateSunEvent(for: date, isSunrise: false)
    }

    private func calculateSunEvent(for date: Date, isSunrise: Bool) -> Date? {
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1

        // Solar calculations (simplified)
        let zenith = 90.833 // Official zenith for sunrise/sunset

        // Convert latitude to radians
        let latRad = latitude * .pi / 180

        // Calculate approximate time
        let lngHour = longitude / 15

        let t: Double
        if isSunrise {
            t = Double(dayOfYear) + ((6 - lngHour) / 24)
        } else {
            t = Double(dayOfYear) + ((18 - lngHour) / 24)
        }

        // Calculate sun's mean anomaly
        let M = (0.9856 * t) - 3.289

        // Calculate sun's true longitude
        var L = M + (1.916 * sin(M * .pi / 180)) + (0.020 * sin(2 * M * .pi / 180)) + 282.634
        L = L.truncatingRemainder(dividingBy: 360)
        if L < 0 { L += 360 }

        // Calculate sun's right ascension
        var RA = atan(0.91764 * tan(L * .pi / 180)) * 180 / .pi
        RA = RA.truncatingRemainder(dividingBy: 360)
        if RA < 0 { RA += 360 }

        // Adjust RA to same quadrant as L
        let Lquadrant = (floor(L / 90)) * 90
        let RAquadrant = (floor(RA / 90)) * 90
        RA = RA + (Lquadrant - RAquadrant)

        // Convert RA to hours
        RA = RA / 15

        // Calculate sun's declination
        let sinDec = 0.39782 * sin(L * .pi / 180)
        let cosDec = cos(asin(sinDec))

        // Calculate sun's local hour angle
        let cosH = (cos(zenith * .pi / 180) - (sinDec * sin(latRad))) / (cosDec * cos(latRad))

        // Check if sun never rises or sets
        if cosH > 1 || cosH < -1 {
            return nil
        }

        // Calculate local time of sun event
        var H: Double
        if isSunrise {
            H = 360 - (acos(cosH) * 180 / .pi)
        } else {
            H = acos(cosH) * 180 / .pi
        }
        H = H / 15

        // Calculate local mean time
        let T = H + RA - (0.06571 * t) - 6.622

        // Convert to UTC
        var UT = T - lngHour
        UT = UT.truncatingRemainder(dividingBy: 24)
        if UT < 0 { UT += 24 }

        // Convert to date
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = Int(UT)
        components.minute = Int((UT - floor(UT)) * 60)
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")

        if let utcDate = calendar.date(from: components) {
            // Convert to local time
            return utcDate
        }

        return nil
    }
}
