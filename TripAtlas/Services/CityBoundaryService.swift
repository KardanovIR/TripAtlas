import Foundation
import CryptoKit

/// Загружает границы городов с нашего сервера и кэширует их на диске.
///
/// Сервер — свой Nominatim 5.3 на данных OpenStreetMap: только административные границы
/// и населённые пункты, без поиска и обновлений (см. `Server/geo/README.md`). Публичный
/// nominatim.openstreetmap.org не подходит: его лимит — 1 запрос в секунду на всё приложение.
/// Данные OSM — по лицензии ODbL: на картах и в видео с границами — подпись «© OpenStreetMap».
actor CityBoundaryService {
    static let shared = CityBoundaryService()

    static let endpoint = URL(string: "https://geo.agstatus.online/reverse")!
    static let userAgent: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "TripAtlas/\(version) (\(build); iOS)"
    }()

    enum Result: Sendable {
        case found(CityBoundary)
        /// Границы нет (у места только точка) — показываем круг.
        case missing
        /// Ошибка сети — попробуем позже, в кэш не пишем.
        case failed
    }

    private enum CacheEntry: Codable {
        case found(CityBoundary)
        case missing(Date)
    }

    /// Через сколько перепроверять места без границы.
    private let missingTTL: TimeInterval = 30 * 86_400
    /// Промежуток между запросами с одного устройства (сервер пускает 5 в секунду с одного адреса).
    private let minInterval: TimeInterval = 0.25

    private var memory: [String: CacheEntry] = [:]
    private var tail: Task<Void, Never>?
    private var lastRequest = Date.distantPast
    /// Пауза после ошибок сервера: пока она идёт, запросы не уходят в сеть.
    private var backoff = RetryBackoff()

    private let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CityBoundaries", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - API

    /// Граница города `key` (ключ города), найденная по точке внутри него.
    func boundary(key: String, latitude: Double, longitude: Double) async -> Result {
        if let cached = cachedResult(for: key) { return cached }

        // Последовательная очередь: соблюдаем лимит 1 запрос/с.
        let previous = tail
        let task = Task { () -> Result in
            await previous?.value
            return await self.fetchIfNeeded(key: key, latitude: latitude, longitude: longitude)
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    func clearCache() {
        memory.removeAll()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: - Кэш

    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }

    private func cachedResult(for key: String) -> Result? {
        if memory[key] == nil,
           let data = try? Data(contentsOf: fileURL(for: key)),
           let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) {
            memory[key] = entry
        }
        switch memory[key] {
        case .found(let boundary): return .found(boundary)
        case .missing(let date) where Date().timeIntervalSince(date) < missingTTL: return .missing
        default: return nil
        }
    }

    private func store(_ entry: CacheEntry, for key: String) {
        memory[key] = entry
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
    }

    // MARK: - Сеть

    /// Запрос города по точке. nginx на сервере пропускает только эту строку запроса целиком —
    /// в этом порядке и с этими значениями (Server/geo/nginx.conf), так что менять её можно
    /// только вместе с настройкой сервера.
    static func requestURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "format", value: "jsonv2"),
            .init(name: "lat", value: String(format: "%.5f", latitude)),
            .init(name: "lon", value: String(format: "%.5f", longitude)),
            .init(name: "zoom", value: "10"),                  // уровень города
            .init(name: "polygon_geojson", value: "1"),
            .init(name: "polygon_threshold", value: "0.0005"), // упрощение на сервере (~50 м)
        ]
        return components.url!
    }

    private func fetchIfNeeded(key: String, latitude: Double, longitude: Double) async -> Result {
        if let cached = cachedResult(for: key) { return cached }
        // Сервер недавно не ответил — не дёргаем его: город пока покажется кругом,
        // а карта попросит границу снова при следующем показе.
        guard backoff.allows(at: Date()) else { return .failed }

        let wait = minInterval - Date().timeIntervalSince(lastRequest)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        lastRequest = Date()

        var request = URLRequest(url: Self.requestURL(latitude: latitude, longitude: longitude), timeoutInterval: 20)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if Self.isServerFailure(error) { backoff.recordFailure(at: Date()) }
            return .failed
        }
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            let retryAfter = (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            backoff.recordFailure(at: Date(), retryAfter: retryAfter)
            return .failed
        }
        backoff.recordSuccess()

        do {
            if let boundary = try OSMBoundaryParser.parse(data) {
                store(.found(boundary), for: key)
                return .found(boundary)
            } else {
                store(.missing(Date()), for: key)
                return .missing
            }
        } catch {
            return .failed   // ответ не разобрался: сервер жив, паузу не включаем, в кэш не пишем
        }
    }
}

extension CityBoundaryService {
    /// Включать ли паузу из-за этой ошибки. Нет: если запрос не ушёл с устройства (нет сети,
    /// авиарежим, роуминг, экономия трафика) или задачу отменили — сервер тут ни при чём,
    /// а пауза держала бы границы выключенными ещё долго после того, как сеть вернулась.
    static func isServerFailure(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return true }
        if urlError.networkUnavailableReason != nil { return false }
        switch urlError.code {
        case .cancelled, .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff,
             .callIsActive, .networkConnectionLost:
            return false
        default:
            return true
        }
    }
}

/// Пауза после ошибок сервера границ: 30 с, затем 1, 2, 4… минуты, но не больше часа.
/// `Retry-After` из ответа может её удлинить (до того же часа). Удачный ответ сбрасывает паузу.
struct RetryBackoff {
    static let base: TimeInterval = 30
    static let cap: TimeInterval = 3600

    private(set) var failures = 0
    private(set) var resumeAt: Date?

    func allows(at now: Date) -> Bool { resumeAt.map { now >= $0 } ?? true }

    mutating func recordFailure(at now: Date, retryAfter: TimeInterval? = nil) {
        failures += 1
        let delay = min(Self.base * pow(2, Double(min(failures - 1, 16))), Self.cap)
        let requested = min(max(retryAfter ?? 0, 0), Self.cap)
        resumeAt = now.addingTimeInterval(max(delay, requested))
    }

    mutating func recordSuccess() {
        failures = 0
        resumeAt = nil
    }
}
