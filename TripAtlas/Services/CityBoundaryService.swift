import Foundation
import CryptoKit

/// Загружает границы городов из OpenStreetMap (Nominatim) и кэширует их на диске.
///
/// Правила Nominatim (https://operations.osmfoundation.org/policies/nominatim/):
/// не больше 1 запроса в секунду, осмысленный User-Agent, обязательное кэширование
/// и указание авторства «© OpenStreetMap contributors». Для массового распространения
/// приложения поднимите свой Nominatim или используйте коммерческого провайдера —
/// достаточно поменять `endpoint`.
actor CityBoundaryService {
    static let shared = CityBoundaryService()

    static let endpoint = URL(string: "https://nominatim.openstreetmap.org/reverse")!
    static let userAgent = "TripAtlas/1.0 (iOS app; personal use)"

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
    private let minInterval: TimeInterval = 1.1

    private var memory: [String: CacheEntry] = [:]
    private var tail: Task<Void, Never>?
    private var lastRequest = Date.distantPast

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

    private func fetchIfNeeded(key: String, latitude: Double, longitude: Double) async -> Result {
        if let cached = cachedResult(for: key) { return cached }

        let wait = minInterval - Date().timeIntervalSince(lastRequest)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        lastRequest = Date()

        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "format", value: "jsonv2"),
            .init(name: "lat", value: String(format: "%.5f", latitude)),
            .init(name: "lon", value: String(format: "%.5f", longitude)),
            .init(name: "zoom", value: "10"),                  // уровень города
            .init(name: "polygon_geojson", value: "1"),
            .init(name: "polygon_threshold", value: "0.0005"), // упрощение на сервере (~50 м)
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed }
            if let boundary = try OSMBoundaryParser.parse(data) {
                store(.found(boundary), for: key)
                return .found(boundary)
            } else {
                store(.missing(Date()), for: key)
                return .missing
            }
        } catch {
            return .failed
        }
    }
}
