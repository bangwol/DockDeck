import Cocoa
import Combine
import SwiftUI
import XCTest

@testable import DockDeck

final class WeatherTests: XCTestCase {
    func testHourlyForecastBoundsMissingValuesAndUsesAbsoluteDates() throws {
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: forecastData()) as? [String: Any])
        payload["hourly"] = [
            "time": [-3600, 0, 3600, 3600, 7200, 43200],
            "temperature_2m": [0, 21, NSNull(), 99, 1e50, 20],
            "precipitation_probability": [0, 10, 101, 20, NSNull(), 0],
            "weather_code": [0, 0, 63, 0, 0, 0],
            "is_day": [0, 1, 1, 1, 0, 0],
        ]
        let snapshot = try WeatherAPI.decodeForecast(
            JSONSerialization.data(withJSONObject: payload), location: fixtureLocation(),
            unit: .celsius, receivedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snapshot.hourly.map { $0.date.timeIntervalSince1970 }, [0, 3600, 7200])
        XCTAssertEqual(snapshot.hourly[0].precipitationProbability, 10)
        XCTAssertNil(snapshot.hourly[1].temperature)
        XCTAssertNil(snapshot.hourly[1].precipitationProbability)
        XCTAssertNil(snapshot.hourly[2].temperature)
    }

    func testForecastRejectsTemperatureThatWouldOverflowCompactFormatting() throws {
        let data = String(data: forecastData(), encoding: .utf8)!.replacingOccurrences(of: "21.2", with: "1e50")
        XCTAssertThrowsError(try WeatherAPI.decodeForecast(Data(data.utf8), location: fixtureLocation(), unit: .celsius))
    }

    func testLocationNormalizationRejectsInvalidCoordinatesAndBoundsText() {
        var location = fixtureLocation()
        location.name = String(repeating: "S", count: 100)

        XCTAssertEqual(
            location.normalizedForStorage()?.name.count,
            WeatherLocation.maximumTextLength)

        location.latitude = 91
        XCTAssertNil(location.normalizedForStorage())
    }

    func testForecastURLUsesFixedHTTPSHostAndSelectedUnit() throws {
        let url = try XCTUnwrap(
            WeatherAPI.forecastURL(location: fixtureLocation(), unit: .fahrenheit))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(
            uniqueKeysWithValues: try XCTUnwrap(components.queryItems).map { ($0.name, $0.value) })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "api.open-meteo.com")
        XCTAssertEqual(query["temperature_unit"], "fahrenheit")
        XCTAssertEqual(query["forecast_days"], "1")
        XCTAssertEqual(query["forecast_hours"], "13")
        XCTAssertEqual(query["timeformat"], "unixtime")
    }

    func testForecastDecoderReadsCurrentAndDailyValues() throws {
        let snapshot = try WeatherAPI.decodeForecast(
            forecastData(), location: fixtureLocation(), unit: .celsius,
            receivedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(snapshot.temperature, 21.2)
        XCTAssertEqual(snapshot.apparentTemperature, 24.7)
        XCTAssertEqual(snapshot.highTemperature, 28.9)
        XCTAssertEqual(snapshot.lowTemperature, 21.2)
        XCTAssertEqual(snapshot.weatherCode, 3)
        XCTAssertTrue(snapshot.isDay)
        XCTAssertEqual(snapshot.temperatureUnit, .celsius)
    }

    func testGeocodingDecoderRemovesDuplicateAndInvalidResults() throws {
        let data = Data(
            """
            {"results":[
              {"id":1,"name":"Seoul","latitude":37.566,"longitude":126.9784,
               "country_code":"KR","country":"South Korea","admin1":"Seoul",
               "timezone":"Asia/Seoul"},
              {"id":1,"name":"Duplicate","latitude":37.5,"longitude":127.0},
              {"id":2,"name":"Invalid","latitude":200,"longitude":127.0},
              {"id":2,"name":"Busan","latitude":35.1796,"longitude":129.0756,
               "country_code":"KR","country":"South Korea"}
            ]}
            """.utf8)

        let locations = try WeatherAPI.decodeLocations(data)

        XCTAssertEqual(locations.map(\.name), ["Seoul", "Busan"])
        XCTAssertEqual(locations.first?.detail, "South Korea")
    }

    func testWeatherConditionMapsDayNightAndPrecipitation() {
        XCTAssertEqual(WeatherCondition.symbolName(code: 0, isDay: true), "sun.max.fill")
        XCTAssertEqual(WeatherCondition.symbolName(code: 0, isDay: false), "moon.stars.fill")
        XCTAssertEqual(WeatherCondition.title(code: 63), "Rain")
        XCTAssertEqual(WeatherCondition.title(code: 95), "Thunderstorm")
    }

    func testStorePublishesForecastFromGETRequest() throws {
        let session = makeSession()
        WeatherURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "api.open-meteo.com")
            return (200, self.forecastData())
        }
        let store = WeatherStore(
            location: fixtureLocation(), unit: .celsius,
            refreshInterval: 3_600, session: session)
        let completed = expectation(description: "Forecast completed")
        var fulfilled = false
        let cancellable = store.$status.sink { status in
            guard !fulfilled, status == .ready else { return }
            fulfilled = true
            completed.fulfill()
        }

        store.start()
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(store.snapshot?.temperature, 21.2)
        cancellable.cancel()
        store.stop()
        session.invalidateAndCancel()
        WeatherURLProtocol.handler = nil
    }

    func testLocationSearchPublishesResultsOnlyOnRequest() throws {
        let session = makeSession()
        WeatherURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "geocoding-api.open-meteo.com")
            XCTAssertTrue(request.url?.query?.contains("name=Seoul") == true)
            let data = Data(
                """
                {"results":[{"id":1835848,"name":"Seoul","latitude":37.566,
                "longitude":126.9784,"country_code":"KR","country":"South Korea",
                "admin1":"Seoul","timezone":"Asia/Seoul"}]}
                """.utf8)
            return (200, data)
        }
        let store = WeatherLocationSearchStore(session: session)
        store.query = "Seoul"
        let completed = expectation(description: "Search completed")
        var fulfilled = false
        let cancellable = store.$status.sink { status in
            guard !fulfilled, status == .ready else { return }
            fulfilled = true
            completed.fulfill()
        }

        store.search()
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(store.results.first?.name, "Seoul")
        cancellable.cancel()
        store.cancel()
        session.invalidateAndCancel()
        WeatherURLProtocol.handler = nil
    }

    func testPanelRendersLoadedWeatherAtCompactSize() throws {
        let session = makeSession()
        WeatherURLProtocol.handler = { _ in (200, self.forecastData()) }
        let store = WeatherStore(
            location: fixtureLocation(), unit: .celsius,
            refreshInterval: 3_600, session: session)
        let completed = expectation(description: "Panel forecast completed")
        var fulfilled = false
        let cancellable = store.$status.sink { status in
            guard !fulfilled, status == .ready else { return }
            fulfilled = true
            completed.fulfill()
        }
        store.start()
        wait(for: [completed], timeout: 1)

        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: WeatherPanelView(store: store, theme: Theme.theme(id: "")))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        cancellable.cancel()
        store.stop()
        session.invalidateAndCancel()
        WeatherURLProtocol.handler = nil
    }

    private func fixtureLocation() -> WeatherLocation {
        WeatherLocation(
            id: 1_835_848,
            name: "Seoul",
            latitude: 37.566,
            longitude: 126.9784,
            countryCode: "KR",
            country: "South Korea",
            admin1: "Seoul",
            timezone: "Asia/Seoul")
    }

    private func forecastData() -> Data {
        Data(
            """
            {"current":{"temperature_2m":21.2,"apparent_temperature":24.7,
            "is_day":1,"weather_code":3},"daily":{"temperature_2m_max":[28.9],
            "temperature_2m_min":[21.2]}}
            """.utf8)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeatherURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class WeatherURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (statusCode: Int, data: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let result = try handler(request)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: result.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
