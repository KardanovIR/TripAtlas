import Foundation

/// Чем делимся: одной поездкой или итогами года. Карточки и видео-облёт
/// работают с этим описанием и не зависят от того, что внутри.
struct ShareSubject {
    enum Kind: Equatable {
        case trip
        case year(Int)
    }

    /// Остановка видео-облёта: город поездки или целая поездка в итогах года.
    struct Stop {
        let name: String
        let subtitle: String?
        let places: [Place]
        let photoIDs: [String]
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let flags: String
    let stats: [ShareStat]
    /// Все места (без повторов), в порядке посещения.
    let places: [Place]
    /// Все фото, по времени.
    let assetIDs: [String]
    let assetDates: [String: Date]
    let coverID: String?
    let timeline: [String]
    let timelineNumbered: Bool
    let stops: [Stop]

    private let placeByAsset: [String: Place]

    func place(containing assetID: String) -> Place? { placeByAsset[assetID] }

    /// Для подписи к публикации и имени файла.
    var shareTitle: String {
        switch kind {
        case .trip: title
        case .year(let year): "Мой \(year) год в путешествиях"
        }
    }

    init(kind: Kind, title: String, subtitle: String, flags: String, stats: [ShareStat], places: [Place],
         assetIDs: [String], assetDates: [String: Date], coverID: String?, timeline: [String],
         timelineNumbered: Bool, stops: [Stop]) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.flags = flags
        self.stats = stats
        self.places = places
        self.assetIDs = assetIDs
        self.assetDates = assetDates
        self.coverID = coverID
        self.timeline = timeline
        self.timelineNumbered = timelineNumbered
        self.stops = stops
        var map: [String: Place] = [:]
        for place in places {
            for id in place.assetIDs ?? [] { map[id] = place }
        }
        placeByAsset = map
    }
}

// MARK: - Поездка

extension ShareSubject {
    @MainActor
    static func trip(_ trip: Trip) -> ShareSubject {
        var stats = [
            ShareStat(value: "\(trip.dayCount)", label: RU.word(trip.dayCount, "день", "дня", "дней")),
            ShareStat(value: "\(trip.cityKeys.count)", label: RU.word(trip.cityKeys.count, "город", "города", "городов")),
            ShareStat(value: "\(trip.assetIdentifiers.count)", label: "фото"),
        ]
        let km = Int(trip.distanceKm.rounded())
        if km >= 10 { stats.append(ShareStat(value: km.formatted(), label: "км")) }

        let stops = trip.places.map { place in
            Stop(name: place.name,
                 subtitle: place.countryCode.map { "\(Geo.flag(for: $0))  \(Geo.countryName(for: $0))" },
                 places: [place],
                 photoIDs: place.assetIDs ?? [])
        }

        return ShareSubject(
            kind: .trip,
            title: trip.title,
            subtitle: trip.dateRangeText,
            flags: trip.flags,
            stats: stats,
            places: trip.places,
            assetIDs: trip.assetIdentifiers,
            assetDates: dates(of: trip),
            coverID: trip.coverAssetIdentifier,
            timeline: trip.places.map(\.name),
            timelineNumbered: true,
            stops: stops
        )
    }

    @MainActor
    private static func dates(of trip: Trip) -> [String: Date] {
        guard trip.assetDates.count == trip.assetIdentifiers.count else { return [:] }
        var result: [String: Date] = [:]
        for (id, date) in zip(trip.assetIdentifiers, trip.assetDates) { result[id] = date }
        return result
    }
}

// MARK: - Год

extension ShareSubject {
    /// Годы, в которые начинались поездки, — новые сверху.
    @MainActor
    static func years(in trips: [Trip]) -> [Int] {
        Set(trips.map { Calendar.current.component(.year, from: $0.startDate) }).sorted(by: >)
    }

    @MainActor
    static func year(_ year: Int, trips allTrips: [Trip]) -> ShareSubject {
        let trips = allTrips
            .filter { Calendar.current.component(.year, from: $0.startDate) == year }
            .sorted { $0.startDate < $1.startDate }

        // Один город из разных поездок — одна зона (с самыми полными данными).
        var places: [Place] = []
        var index: [String: Int] = [:]
        for place in trips.flatMap(\.places) {
            if let i = index[place.id] {
                var merged = places[i]
                merged.assetIDs = (merged.assetIDs ?? []) + (place.assetIDs ?? [])
                merged.photoCount = (merged.photoCount ?? 0) + (place.photoCount ?? 0)
                if (place.radiusKm ?? 0) > (merged.radiusKm ?? 0) { merged.radiusKm = place.radiusKm }
                places[i] = merged
            } else {
                index[place.id] = places.count
                places.append(place)
            }
        }

        let countries = trips.flatMap(\.countryCodes).uniqued()
        let cityCount = Set(trips.flatMap(\.cityKeys)).count
        let days = trips.reduce(0) { $0 + $1.dayCount }
        let stats = [
            ShareStat(value: "\(trips.count)", label: RU.word(trips.count, "поездка", "поездки", "поездок")),
            ShareStat(value: "\(countries.count)", label: RU.word(countries.count, "страна", "страны", "стран")),
            ShareStat(value: "\(cityCount)", label: RU.word(cityCount, "город", "города", "городов")),
            ShareStat(value: "\(days)", label: RU.word(days, "день", "дня", "дней")),
        ]

        var dates: [String: Date] = [:]
        for trip in trips { dates.merge(Self.dates(of: trip)) { a, _ in a } }

        // Обложка — обложка поездки, где больше всего фото.
        let cover = trips.max { $0.assetIdentifiers.count < $1.assetIdentifiers.count }?.coverAssetIdentifier

        let stops = trips.map { trip in
            Stop(name: trip.title,
                 subtitle: [trip.flags, trip.dateRangeText].filter { !$0.isEmpty }.joined(separator: "  "),
                 places: trip.places,
                 photoIDs: trip.assetIdentifiers)
        }

        return ShareSubject(
            kind: .year(year),
            title: String(year),
            subtitle: "Мой год в путешествиях",
            flags: countries.map(Geo.flag(for:)).joined(),
            stats: stats,
            places: places,
            assetIDs: trips.flatMap(\.assetIdentifiers),
            assetDates: dates,
            coverID: cover,
            timeline: countries.map { "\(Geo.flag(for: $0)) \(Geo.countryName(for: $0))" },
            timelineNumbered: false,
            stops: stops
        )
    }
}
