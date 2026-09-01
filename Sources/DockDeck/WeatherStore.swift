import Foundation

enum WeatherTemperatureUnit: String, CaseIterable, Codable {
    case celsius
    case fahrenheit

    var title: String {
        switch self {
        case .celsius: "Celsius"
        case .fahrenheit: "Fahrenheit"
        }
    }

    var symbol: String { self == .celsius ? "°C" : "°F" }
}

struct WeatherLocation: Codable, Equatable, Identifiable {
    static let maximumTextLength = 80

    let id: Int
    var name: String
    var latitude: Double
    var longitude: Double
    var countryCode: String
    var country: String
    var admin1: String?
    var timezone: String

    var detail: String {
        var parts: [String] = []
        if let admin1, admin1.caseInsensitiveCompare(name) != .orderedSame {
            parts.append(admin1)
        }
        if !country.isEmpty { parts.append(country) }
        return parts.joined(separator: ", ")
    }

    func normalizedForStorage() -> Self? {
        guard latitude.isFinite, longitude.isFinite,
            (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return nil }
        let name = Self.bounded(name)
        guard !name.isEmpty else { return nil }
        return Self(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            countryCode: String(Self.bounded(countryCode).uppercased().prefix(2)),
            country: Self.bounded(country),
            admin1: admin1.map(Self.bounded).flatMap { $0.isEmpty ? nil : $0 },
            timezone: Self.bounded(timezone))
    }

    private static func bounded(_ value: String) -> String {
        String(
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumTextLength))
    }
}

struct WeatherSnapshot: Equatable {
    let location: WeatherLocation
    let temperature: Double
    let apparentTemperature: Double
    let highTemperature: Double?
    let lowTemperature: Double?
    let weatherCode: Int
    let isDay: Bool
    let temperatureUnit: WeatherTemperatureUnit
    let receivedAt: Date
}

enum WeatherLoadStatus: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

enum WeatherCondition {
    static func title(code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55, 56, 57: "Drizzle"
        case 61, 63, 65, 66, 67: "Rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Rain showers"
        case 85, 86: "Snow showers"
        case 95, 96, 99: "Thunderstorm"
        default: "Conditions unavailable"
        }
    }

    static func symbolName(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

enum WeatherAPI {
    static let attributionURL = URL(string: "https://open-meteo.com/")!
    static let licenseURL = URL(string: "https://open-meteo.com/en/license")!

    static func forecastURL(
        location: WeatherLocation, unit: WeatherTemperatureUnit
    ) -> URL? {
        guard let location = location.normalizedForStorage() else { return nil }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,is_day,weather_code"),
            URLQueryItem(
                name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
        ]
        return components?.url
    }

    static func searchURL(query: String, language: String, count: Int = 5) -> URL? {
        let query = String(
            query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard query.count >= 2 else { return nil }
        let language = language.lowercased().prefix(2)
        var components = URLComponents(
            string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: String(min(max(count, 1), 10))),
            URLQueryItem(name: "language", value: language.isEmpty ? "en" : String(language)),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components?.url
    }

    static func decodeForecast(
        _ data: Data, location: WeatherLocation, unit: WeatherTemperatureUnit,
        receivedAt: Date = Date()
    ) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return WeatherSnapshot(
            location: location,
            temperature: response.current.temperature,
            apparentTemperature: response.current.apparentTemperature,
            highTemperature: response.daily?.maximumTemperature.first,
            lowTemperature: response.daily?.minimumTemperature.first,
            weatherCode: response.current.weatherCode,
            isDay: response.current.isDay != 0,
            temperatureUnit: unit,
            receivedAt: receivedAt)
    }

    static func decodeLocations(_ data: Data) throws -> [WeatherLocation] {
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        var seen: Set<Int> = []
        return (response.results ?? []).compactMap { result in
            let location = WeatherLocation(
                id: result.id,
                name: result.name,
                latitude: result.latitude,
                longitude: result.longitude,
                countryCode: result.countryCode ?? "",
                country: result.country ?? "",
                admin1: result.admin1,
                timezone: result.timezone ?? "").normalizedForStorage()
            guard let location else { return nil }
            guard seen.insert(location.id).inserted else { return nil }
            return location
        }
    }

    private struct ForecastResponse: Decodable {
        let current: Current
        let daily: Daily?
    }

    private struct Current: Decodable {
        let temperature: Double
        let apparentTemperature: Double
        let isDay: Int
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case isDay = "is_day"
            case weatherCode = "weather_code"
        }
    }

    private struct Daily: Decodable {
        let maximumTemperature: [Double]
        let minimumTemperature: [Double]

        enum CodingKeys: String, CodingKey {
            case maximumTemperature = "temperature_2m_max"
            case minimumTemperature = "temperature_2m_min"
        }
    }

    private struct GeocodingResponse: Decodable {
        let results: [GeocodingResult]?
    }

    private struct GeocodingResult: Decodable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let countryCode: String?
        let country: String?
        let admin1: String?
        let timezone: String?

        enum CodingKeys: String, CodingKey {
            case id, name, latitude, longitude, country, admin1, timezone
            case countryCode = "country_code"
        }
    }
}

final class WeatherStore: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var status: WeatherLoadStatus = .idle

    private var location: WeatherLocation?
    private var unit: WeatherTemperatureUnit
    private var refreshInterval: TimeInterval
    private var timer: Timer?
    private var task: URLSessionDataTask?
    private var generation = 0
    private var isRunning = false
    private let session: URLSession

    init(
        location: WeatherLocation? = PanelSettings.weatherLocation,
        unit: WeatherTemperatureUnit = PanelSettings.weatherTemperatureUnit,
        refreshInterval: TimeInterval = PanelSettings.weatherRefreshInterval,
        session: URLSession? = nil
    ) {
        self.location = location?.normalizedForStorage()
        self.unit = unit
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
        self.session = session ?? Self.makeSession()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        scheduleTimer()
    }

    func stop() {
        guard isRunning || timer != nil || task != nil else { return }
        isRunning = false
        generation += 1
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
    }

    func updateConfiguration(
        location: WeatherLocation?, unit: WeatherTemperatureUnit,
        refreshInterval: TimeInterval
    ) {
        let location = location?.normalizedForStorage()
        let contentChanged = self.location != location || self.unit != unit
        self.location = location
        self.unit = unit
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
        if contentChanged {
            snapshot = nil
            status = .idle
        }
        guard isRunning else { return }
        generation += 1
        task?.cancel()
        task = nil
        scheduleTimer()
        refresh()
    }

    func refresh() {
        guard isRunning else { return }
        guard let location else {
            snapshot = nil
            status = .idle
            return
        }
        guard let url = WeatherAPI.forecastURL(location: location, unit: unit) else {
            snapshot = nil
            status = .failed("Invalid location")
            return
        }

        generation += 1
        let generation = generation
        task?.cancel()
        status = .loading
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.complete(
                    data: data, response: response, error: error,
                    location: location, generation: generation)
            }
        }
        self.task = task
        task.resume()
    }

    private func complete(
        data: Data?, response: URLResponse?, error: Error?,
        location: WeatherLocation, generation: Int
    ) {
        guard isRunning, generation == self.generation else { return }
        task = nil
        if let error {
            status = .failed(Self.failureLabel(error))
            return
        }
        guard let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode), let data
        else {
            status = .failed("Weather service unavailable")
            return
        }
        do {
            snapshot = try WeatherAPI.decodeForecast(data, location: location, unit: unit)
            status = .ready
        } catch {
            status = .failed("Weather response changed")
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard isRunning, location != nil else {
            timer = nil
            return
        }
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }

    private static func failureLabel(_ error: Error) -> String {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return "Network error" }
        switch error.code {
        case NSURLErrorTimedOut: return "Weather request timed out"
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "Offline"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "Weather host not found"
        case NSURLErrorCannotConnectToHost: return "Weather service unavailable"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return "Weather TLS error"
        default: return "Network error"
        }
    }

    private static func resolvedRefreshInterval(_ value: TimeInterval) -> TimeInterval {
        PanelSettings.weatherRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultWeatherRefreshInterval
    }
}

enum WeatherSearchStatus: Equatable {
    case idle
    case searching
    case ready
    case failed(String)
}

final class WeatherLocationSearchStore: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [WeatherLocation] = []
    @Published private(set) var status: WeatherSearchStatus = .idle

    private var task: URLSessionDataTask?
    private var generation = 0
    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
    }

    func search() {
        generation += 1
        let generation = generation
        task?.cancel()
        task = nil
        let language = Locale.preferredLanguages.first.map {
            String($0.prefix(2)).lowercased()
        } ?? "en"
        guard let url = WeatherAPI.searchURL(query: query, language: language) else {
            results = []
            status = .failed("Enter at least two characters.")
            return
        }
        status = .searching
        results = []
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.complete(
                    data: data, response: response, error: error, generation: generation)
            }
        }
        self.task = task
        task.resume()
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        if status == .searching { status = .idle }
    }

    private func complete(
        data: Data?, response: URLResponse?, error: Error?, generation: Int
    ) {
        guard generation == self.generation else { return }
        task = nil
        if error != nil {
            results = []
            status = .failed("Location search failed.")
            return
        }
        guard let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode), let data,
            let locations = try? WeatherAPI.decodeLocations(data)
        else {
            results = []
            status = .failed("Location search failed.")
            return
        }
        results = Array(locations.prefix(5))
        status = results.isEmpty ? .failed("No matching cities.") : .ready
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }
}
