import Foundation

/// «Дом» пользователя по годам — тот же, что использует распознавание поездок.
/// Запоминается при сканировании медиатеки, чтобы видео итогов года не пересчитывало его.
enum HomeStore {
    private static let key = "homeByYear"

    static func home(for year: Int) -> Coordinate? {
        guard let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]],
              let pair = stored[String(year)], pair.count == 2 else { return nil }
        return Coordinate(latitude: pair[0], longitude: pair[1])
    }

    /// Вычисляет и сохраняет дом для всех лет, в которые есть фото. Вызывать не на главном потоке.
    static func save(from samples: [PhotoSample], config: TripDetector.Config) {
        let resolver = HomeResolver(samples: samples, config: config)
        let years = Set(samples.map { Calendar.current.component(.year, from: $0.date) })
        var stored: [String: [Double]] = [:]
        for (year, home) in resolver.homes(for: years) {
            stored[String(year)] = [home.latitude, home.longitude]
        }
        UserDefaults.standard.set(stored, forKey: key)
    }

    /// Дом за год: из сохранённого, а если сканирования ещё не было — посчитать заново.
    static func resolve(year: Int) async -> Coordinate? {
        if let home = home(for: year) { return home }
        return await Task.detached(priority: .userInitiated) {
            save(from: PhotoLibraryService.fetchGeotaggedSamples(), config: .fromDefaults())
            return home(for: year)
        }.value
    }
}
