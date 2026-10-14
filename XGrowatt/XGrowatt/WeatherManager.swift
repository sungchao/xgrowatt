import Foundation
import Combine
import SwiftUI
import CoreLocation
import WeatherKit

// MARK: - Weather Data Models

struct OpenMeteoResponse: Codable {
    let current: CurrentWeather
}

struct CurrentWeather: Codable {
    let temperature2m: Double
    let weatherCode: Int
    let isDay: Int

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case weatherCode   = "weather_code"
        case isDay         = "is_day"
    }
}

// MARK: - Resolved Weather Display Info

struct WeatherInfo {
    let icon: String
    let color: Color
    let description: String   // e.g. "Sunny 18°"
    let temperature: Double?
    let isRealData: Bool      // false = no data yet / fallback
}

// MARK: - WeatherManager

@MainActor
class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published var weather: WeatherInfo = WeatherInfo(
        icon: "sun.max.fill",
        color: Color(red: 247/255, green: 176/255, blue: 91/255),
        description: "Solar",
        temperature: nil,
        isRealData: false
    )

    @Published var isDay: Bool = true

    private var fetchTask: Task<Void, Never>?
    private var lastFetchTime: Date?
    private let cacheTTL: TimeInterval = 600   // re-fetch every 10 min

    private init() {}

    // MARK: - Public API

    func fetchIfNeeded(timezone: String, latitude: Double? = nil, longitude: Double? = nil) {
        updateFallbackIsDay(timezone: timezone)
        if let last = lastFetchTime, Date().timeIntervalSince(last) < cacheTTL { return }
        fetch(timezone: timezone, latitude: latitude, longitude: longitude)
    }

    func fetch(timezone: String, latitude: Double? = nil, longitude: Double? = nil) {
        updateFallbackIsDay(timezone: timezone)
        fetchTask?.cancel()
        
        let lat: Double
        let lon: Double
        if let customLat = latitude, let customLon = longitude {
            lat = customLat
            lon = customLon
        } else {
            let coords = coordinates(for: timezone)
            lat = coords.lat
            lon = coords.lon
        }
        
        fetchTask = Task {
            await fetchWeather(lat: lat, lon: lon, timezone: timezone)
        }
    }
    
    private func updateFallbackIsDay(timezone: String) {
        // Fallback calculations until network finishes loading
        guard lastFetchTime == nil else { return }
        var cal = Calendar.current
        if let tz = TimeZone(identifier: timezone) { cal.timeZone = tz }
        self.isDay = cal.component(.hour, from: Date()) >= 6 && cal.component(.hour, from: Date()) < 18
    }

    // MARK: - Network

    private func fetchWeather(lat: Double, lon: Double, timezone: String) async {
        updateFallbackIsDay(timezone: timezone)

        // 1. Try Apple WeatherKit
        let location = CLLocation(latitude: lat, longitude: lon)
        do {
            let appleWeather = try await WeatherService.shared.weather(for: location)
            let current = appleWeather.currentWeather
            let temp = current.temperature.converted(to: .celsius).value
            
            // Map Apple Weather conditions to WeatherInfo
            let info = buildWeatherInfo(condition: current.condition, temp: temp, isDay: current.isDaylight)
            
            self.weather = info
            self.isDay = current.isDaylight
            self.lastFetchTime = Date()
            print("WeatherManager: Successfully fetched weather from Apple WeatherKit")
            return
        } catch {
            print("WeatherManager: Apple WeatherKit failed/unconfigured (\(error)). Falling back to Open-Meteo REST API.")
        }

        // 2. Fallback to Open-Meteo REST API
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude",  value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current",   value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone",  value: timezone)
        ]
        guard let url = comps.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded   = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let info      = buildWeatherInfoFromOpenMeteo(from: decoded.current)
            self.weather       = info
            self.lastFetchTime = Date()
            print("WeatherManager: Successfully fetched weather from Open-Meteo fallback")
        } catch {
            print("WeatherManager Open-Meteo fallback error: \(error)")
        }
    }

    // MARK: - Apple WeatherKit Condition → Display Info

    private func buildWeatherInfo(condition: WeatherCondition, temp: Double, isDay: Bool) -> WeatherInfo {
        let tStr = String(format: "%.0f°C", temp)
        
        let gold    = Color(red: 247/255, green: 176/255, blue: 91/255)
        let night   = Color(red: 0.75,    green: 0.80,    blue: 0.95)
        let rain    = Color(red: 0.55,    green: 0.65,    blue: 0.85)
        let storm   = Color(red: 0.70,    green: 0.55,    blue: 0.95)
        let fog     = Color(white: 0.65)
        let snow    = Color(white: 0.88)

        if !isDay {
            let (ico, label) = nightIconLabel(for: condition)
            return WeatherInfo(icon: ico, color: night,
                               description: "\(label) \(tStr)",
                               temperature: temp, isRealData: true)
        }

        switch condition {
        case .clear, .mostlyClear:
            return WeatherInfo(icon: "sun.max.fill",        color: gold,
                               description: "Sunny \(tStr)",     temperature: temp, isRealData: true)
        case .partlyCloudy:
            return WeatherInfo(icon: "cloud.sun.fill",      color: gold.opacity(0.85),
                               description: "P.Cloudy \(tStr)",  temperature: temp, isRealData: true)
        case .cloudy, .mostlyCloudy:
            return WeatherInfo(icon: "cloud.fill",          color: fog,
                               description: "Overcast \(tStr)",  temperature: temp, isRealData: true)
        case .foggy, .haze, .blowingDust, .blowingSnow, .smoky:
            return WeatherInfo(icon: "cloud.fog.fill",      color: fog,
                               description: "Foggy \(tStr)",     temperature: temp, isRealData: true)
        case .drizzle:
            return WeatherInfo(icon: "cloud.drizzle.fill",  color: rain,
                               description: "Drizzle \(tStr)",   temperature: temp, isRealData: true)
        case .rain, .heavyRain, .sunShowers:
            return WeatherInfo(icon: "cloud.rain.fill",     color: rain,
                               description: "Rainy \(tStr)",     temperature: temp, isRealData: true)
        case .snow, .heavySnow, .flurries, .sleet, .freezingDrizzle, .freezingRain, .hail, .wintryMix:
            return WeatherInfo(icon: "cloud.snow.fill",     color: snow,
                               description: "Snowy \(tStr)",     temperature: temp, isRealData: true)
        case .thunderstorms:
            return WeatherInfo(icon: "cloud.bolt.rain.fill",color: storm,
                               description: "Stormy \(tStr)",    temperature: temp, isRealData: true)
        default:
            return WeatherInfo(icon: "cloud.sun.fill",      color: gold.opacity(0.80),
                               description: "Solar \(tStr)",     temperature: temp, isRealData: true)
        }
    }

    private func nightIconLabel(for condition: WeatherCondition) -> (String, String) {
        switch condition {
        case .clear, .mostlyClear:              return ("moon.stars.fill",       "Clear Night")
        case .partlyCloudy, .cloudy, .mostlyCloudy: return ("cloud.moon.fill",   "Cloudy Night")
        case .foggy, .haze, .blowingDust, .blowingSnow, .smoky: return ("cloud.fog.fill", "Foggy Night")
        case .drizzle, .rain, .heavyRain, .sunShowers: return ("cloud.moon.rain.fill", "Rainy Night")
        case .snow, .heavySnow, .flurries, .sleet, .freezingDrizzle, .freezingRain, .hail, .wintryMix: return ("snowflake", "Snowy Night")
        case .thunderstorms:                    return ("cloud.bolt.rain.fill",  "Stormy Night")
        default:                                return ("moon.fill",             "Night")
        }
    }

    // MARK: - Open-Meteo Fallback WMO Code → Display Info

    private func buildWeatherInfoFromOpenMeteo(from current: CurrentWeather) -> WeatherInfo {
        let isDay  = current.isDay == 1
        self.isDay = isDay
        let code   = current.weatherCode
        let temp   = current.temperature2m
        let tStr   = String(format: "%.0f°C", temp)

        let gold    = Color(red: 247/255, green: 176/255, blue: 91/255)
        let night   = Color(red: 0.75,    green: 0.80,    blue: 0.95)
        let rain    = Color(red: 0.55,    green: 0.65,    blue: 0.85)
        let storm   = Color(red: 0.70,    green: 0.55,    blue: 0.95)
        let fog     = Color(white: 0.65)
        let snow    = Color(white: 0.88)

        if !isDay {
            let (ico, label) = nightIconLabelFromOpenMeteo(for: code)
            return WeatherInfo(icon: ico, color: night,
                               description: "\(label) \(tStr)",
                               temperature: temp, isRealData: true)
        }

        switch code {
        case 0:
            return WeatherInfo(icon: "sun.max.fill",        color: gold,
                               description: "Sunny \(tStr)",     temperature: temp, isRealData: true)
        case 1:
            return WeatherInfo(icon: "sun.max.fill",        color: gold,
                               description: "Clear \(tStr)",     temperature: temp, isRealData: true)
        case 2:
            return WeatherInfo(icon: "cloud.sun.fill",      color: gold.opacity(0.85),
                               description: "P.Cloudy \(tStr)",  temperature: temp, isRealData: true)
        case 3:
            return WeatherInfo(icon: "cloud.fill",          color: fog,
                               description: "Overcast \(tStr)",  temperature: temp, isRealData: true)
        case 45, 48:
            return WeatherInfo(icon: "cloud.fog.fill",      color: fog,
                               description: "Foggy \(tStr)",     temperature: temp, isRealData: true)
        case 51, 53, 55:
            return WeatherInfo(icon: "cloud.drizzle.fill",  color: rain,
                               description: "Drizzle \(tStr)",   temperature: temp, isRealData: true)
        case 61, 63, 65, 80, 81, 82:
            return WeatherInfo(icon: "cloud.rain.fill",     color: rain,
                               description: "Rainy \(tStr)",     temperature: temp, isRealData: true)
        case 71, 73, 75, 77, 85, 86:
            return WeatherInfo(icon: "cloud.snow.fill",     color: snow,
                               description: "Snowy \(tStr)",     temperature: temp, isRealData: true)
        case 95, 96, 99:
            return WeatherInfo(icon: "cloud.bolt.rain.fill",color: storm,
                               description: "Stormy \(tStr)",    temperature: temp, isRealData: true)
        default:
            return WeatherInfo(icon: "cloud.sun.fill",      color: gold.opacity(0.80),
                               description: "Solar \(tStr)",     temperature: temp, isRealData: true)
        }
    }

    private func nightIconLabelFromOpenMeteo(for code: Int) -> (String, String) {
        switch code {
        case 0, 1:              return ("moon.stars.fill",       "Clear Night")
        case 2, 3:              return ("cloud.moon.fill",       "Cloudy Night")
        case 45, 48:            return ("cloud.fog.fill",        "Foggy Night")
        case 51...65, 80...82:  return ("cloud.moon.rain.fill",  "Rainy Night")
        case 71...77, 85, 86:   return ("snowflake",             "Snowy Night")
        case 95, 96, 99:        return ("cloud.bolt.rain.fill",  "Stormy Night")
        default:                return ("moon.fill",             "Night")
        }
    }

    // MARK: - Timezone → Coordinates

    private func coordinates(for timezone: String) -> (lat: Double, lon: Double) {
        let map: [String: (Double, Double)] = [
            "Australia/Sydney":    (-33.87, 151.21),
            "Australia/Canberra":  (-35.28, 149.13),
            "Australia/Melbourne": (-37.81, 144.96),
            "Australia/Brisbane":  (-27.47, 153.02),
            "Australia/Perth":     (-31.95, 115.86),
            "Australia/Adelaide":  (-34.93, 138.60),
            "Australia/Darwin":    (-12.46, 130.84),
            "Australia/Hobart":    (-42.88, 147.32),
            "Pacific/Auckland":    (-36.86, 174.77),
            "Asia/Shanghai":       ( 31.23, 121.47),
            "Asia/Tokyo":          ( 35.68, 139.69),
            "Europe/London":       ( 51.51,  -0.13),
            "America/New_York":    ( 40.71, -74.00),
            "America/Los_Angeles": ( 34.05,-118.24),
        ]
        return map[timezone] ?? (-35.28, 149.13)
    }
}
