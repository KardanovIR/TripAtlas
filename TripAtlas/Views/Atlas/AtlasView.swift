import SwiftUI
import SwiftData

/// Куда можно перейти из сводки на главном экране.
enum AtlasRoute: Hashable {
    case countries
    case cities
    case country(String)
}

/// «Атлас»: все страны мира с отметками посещённых и все ваши города.
struct AtlasView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case countries, cities
        var id: Self { self }
        var title: String { self == .countries ? "Страны" : "Города" }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, visited, notVisited
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "Все"
            case .visited: "Был"
            case .notVisited: "Не был"
            }
        }
    }

    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]

    @State private var tab: Tab
    @State private var filter: Filter = .all
    @State private var search = ""

    init(tab: Tab) {
        _tab = State(initialValue: tab)
    }

    // MARK: - Данные

    private var visitedCodes: Set<String> { Set(trips.flatMap(\.countryCodes)) }
    private var zones: [CityZone] { CityZone.aggregate(trips) }

    private struct CountrySection: Identifiable {
        let continent: Continent
        let countries: [WorldCountry]
        let visited: Int
        let total: Int
        var id: String { continent.id }
    }

    private struct CitySection: Identifiable {
        let code: String
        let cities: [CityZone]
        var id: String { code }
        var name: String { code.isEmpty ? "Без страны" : Geo.countryName(for: code) }
    }

    private func matches(_ text: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }

    // MARK: - Экран

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Раздел", selection: $tab.animation(.snappy)) {
                        ForEach(Tab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .countries: countriesContent(proxy: proxy)
                    case .cities: citiesContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, prompt: tab == .countries ? "Найти страну" : "Найти город")
    }

    // MARK: - Страны

    @ViewBuilder
    private func countriesContent(proxy: ScrollViewProxy) -> some View {
        let visited = visitedCodes
        let all = WorldCountries.list(including: visited)
        let sections = countrySections(all, visited: visited)

        if search.isEmpty {
            WorldProgressCard(
                visited: visited.intersection(WorldCountries.sovereignCodes).count,
                territories: visited.subtracting(WorldCountries.sovereignCodes).count,
                sections: sections.map { ContinentProgress(continent: $0.continent, visited: $0.visited, total: $0.total) }
            ) { continent in
                withAnimation(.smooth) { proxy.scrollTo(continent.id, anchor: .top) }
            }

            FilterBar(selection: $filter)
        }

        let citiesByCountry = Dictionary(grouping: zones) { $0.countryCode ?? "" }
        let tripsByCountry = Dictionary(trips.flatMap { trip in trip.countryCodes.map { ($0, 1) } }, uniquingKeysWith: +)

        ForEach(sections) { section in
            let rows = visibleRows(section, visited: visited)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(section.continent.title, systemImage: section.continent.symbol)
                            .font(Theme.title(22))
                        Spacer()
                        Text("\(section.visited) из \(section.total)")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)

                    CardList(items: rows) { country in
                        let isVisited = visited.contains(country.code)
                        let row = CountryRow(country: country, visited: isVisited,
                                             cities: citiesByCountry[country.code]?.count ?? 0,
                                             trips: tripsByCountry[country.code] ?? 0)
                        if isVisited {
                            NavigationLink(value: AtlasRoute.country(country.code)) { row }
                                .buttonStyle(.plain)
                        } else {
                            row
                        }
                    }
                }
                .id(section.continent.id)
            }
        }

        if sections.allSatisfy({ section in section.countries.allSatisfy { !matches($0.name) } }) {
            ContentUnavailableView.search(text: search)
        }
    }

    private func visibleRows(_ section: CountrySection, visited: Set<String>) -> [WorldCountry] {
        section.countries.filter { country in
            let isVisited = visited.contains(country.code)
            switch filter {
            case .all: break
            case .visited: if !isVisited { return false }
            case .notVisited: if isVisited { return false }
            }
            return matches(country.name)
        }
    }

    private func countrySections(_ all: [WorldCountry], visited: Set<String>) -> [CountrySection] {
        let groups = Dictionary(grouping: all, by: \.continent)
        return Continent.allCases.compactMap { continent in
            guard let countries = groups[continent], !countries.isEmpty else { return nil }
            // Посещённые — наверху, дальше по алфавиту.
            let sorted = countries.filter { visited.contains($0.code) } + countries.filter { !visited.contains($0.code) }
            return CountrySection(continent: continent,
                                  countries: sorted,
                                  visited: countries.filter { visited.contains($0.code) }.count,
                                  total: countries.count)
        }
    }

    // MARK: - Города

    @ViewBuilder
    private var citiesContent: some View {
        let all = zones
        let filtered = all.filter { matches($0.name) || matches($0.countryName ?? "") }

        if all.isEmpty {
            ContentUnavailableView("Городов пока нет", systemImage: "building.2",
                                   description: Text("Создайте страницы поездок — города появятся здесь."))
        } else {
            if search.isEmpty {
                CitiesSummaryCard(cities: all.count, countries: Set(all.compactMap(\.countryCode)).count)
                favorites(all)
            }

            let sections = Dictionary(grouping: filtered) { $0.countryCode ?? "" }
                .map { CitySection(code: $0.key, cities: $0.value.sorted { $0.photoCount > $1.photoCount }) }
                .sorted {
                    $0.cities.count != $1.cities.count
                        ? $0.cities.count > $1.cities.count
                        : $0.name.compare($1.name, locale: .current) == .orderedAscending
                }

            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Geo.flag(for: section.code))  \(section.name)")
                            .font(Theme.title(22))
                        Spacer()
                        Text("\(section.cities.count)")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)

                    CardList(items: section.cities) { zone in
                        NavigationLink {
                            CityPhotosView(zone: zone, trips: trips)
                        } label: {
                            CityRow(zone: zone)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    /// Карусель городов, где снято больше всего фото.
    @ViewBuilder
    private func favorites(_ all: [CityZone]) -> some View {
        let top = Array(all.sorted { $0.photoCount > $1.photoCount }.prefix(6))
        if top.count >= 3 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Больше всего фото")
                    .font(Theme.title(22))
                    .padding(.horizontal, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(top) { zone in
                            NavigationLink {
                                CityPhotosView(zone: zone, trips: trips)
                            } label: {
                                FavoriteCityCard(zone: zone)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}

// MARK: - Карточки-сводки

private struct ContinentProgress: Identifiable {
    let continent: Continent
    let visited: Int
    let total: Int
    var id: String { continent.id }
}

/// Градиентная карточка: кольцо «N из 195» и прогресс по частям света.
private struct WorldProgressCard: View {
    let visited: Int
    let territories: Int
    let sections: [ContinentProgress]
    let onSelect: (Continent) -> Void

    private var fraction: Double { Double(visited) / Double(WorldCountries.total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 20) {
                ProgressRing(progress: fraction)
                    .frame(width: 112, height: 112)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(visited)")
                                .font(Theme.number(36))
                                .contentTransition(.numericText(value: Double(visited)))
                            Text("из \(WorldCountries.total)")
                                .font(.caption.weight(.medium))
                                .opacity(0.8)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0...1))))
                        .font(Theme.title(34))
                    Text("стран мира")
                        .font(.subheadline.weight(.medium))
                        .opacity(0.85)
                    if territories > 0 {
                        Text("+ " + RU.count(territories, "территория", "территории", "территорий"))
                            .font(.caption)
                            .opacity(0.75)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(sections) { item in
                    Button { onSelect(item.continent) } label: {
                        ContinentTile(continent: item.continent, visited: item.visited, total: item.total)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background { SunsetBackground() }
        .card(cornerRadius: 28)
    }
}

private struct ContinentTile: View {
    let continent: Continent
    let visited: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: continent.symbol)
                    .font(.caption)
                Text(continent.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(visited)/\(total)")
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white)
                        .frame(width: total > 0 && visited > 0
                               ? max(6, geo.size.width * CGFloat(visited) / CGFloat(total)) : 0)
                }
            }
            .frame(height: 5)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.white.opacity(visited > 0 ? 0.2 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CitiesSummaryCard: View {
    let cities: Int
    let countries: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(cities)")
                .font(Theme.number(64))
                .contentTransition(.numericText(value: Double(cities)))
            VStack(alignment: .leading, spacing: 2) {
                Text(RU.word(cities, "город", "города", "городов"))
                    .font(Theme.title(26))
                Text("в " + RU.count(countries, "стране", "странах", "странах"))
                    .font(.subheadline.weight(.medium))
                    .opacity(0.85)
            }
            Spacer()
            Image(systemName: "building.2.fill")
                .font(.system(size: 40))
                .opacity(0.35)
        }
        .foregroundStyle(.white)
        .padding(22)
        .background { SunsetBackground() }
        .card(cornerRadius: 28)
    }
}

/// Анимированное кольцо прогресса.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 12

    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(.spring(duration: 1.2).delay(0.15)) { shown = visible(progress) }
        }
        .onChange(of: progress) { _, new in
            withAnimation(.smooth) { shown = visible(new) }
        }
    }

    /// Даже одна страна из 195 должна быть заметна.
    private func visible(_ p: Double) -> Double { p > 0 ? max(p, 0.02) : 0 }
}

/// Фон «закат» — тот же, что у баннера найденных поездок.
struct SunsetBackground: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0],
                     [0, 0.5], [0.6, 0.4], [1, 0.5],
                     [0, 1], [0.5, 1], [1, 1]],
            colors: [Theme.coral, Theme.rose, Theme.violet,
                     Theme.coral, Theme.rose, Theme.violet,
                     Theme.rose, Theme.violet, Theme.violet]
        )
    }
}

// MARK: - Фильтр

private struct FilterBar: View {
    @Binding var selection: AtlasView.Filter
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AtlasView.Filter.allCases) { filter in
                let isSelected = filter == selection
                Button {
                    withAnimation(.snappy) { selection = filter }
                } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule().fill(Theme.sunset)
                                    .matchedGeometryEffect(id: "filter", in: namespace)
                            } else {
                                Capsule().fill(Color(.secondarySystemGroupedBackground))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Строки

/// Список строк в скруглённой карточке с разделителями.
struct CardList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 68) }
                row(item)
            }
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct CountryRow: View {
    let country: WorldCountry
    let visited: Bool
    let cities: Int
    let trips: Int

    var body: some View {
        HStack(spacing: 14) {
            Text(country.flag)
                .font(.system(size: 34))
                .grayscale(visited ? 0 : 1)
                .opacity(visited ? 1 : 0.4)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(country.name)
                    .font(.body.weight(visited ? .semibold : .regular))
                    .foregroundStyle(visited ? Color.primary : Color.secondary)
                if visited {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if visited {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.sunset, in: Circle())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if cities > 0 { parts.append(RU.cities(cities)) }
        parts.append(RU.trips(trips))
        if !country.isSovereign { parts.append("территория") }
        return parts.joined(separator: " · ")
    }
}

struct CityRow: View {
    let zone: CityZone

    var body: some View {
        HStack(spacing: 14) {
            PhotoThumbnail(assetID: zone.coverAssetID, size: 120)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(zone.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if zone.visits > 1 {
                Text("×\(zone.visits)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.zoneColor(visits: zone.visits), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = [RU.photos(zone.photoCount)]
        if zone.visits > 1 {
            parts.insert(RU.count(zone.visits, "визит", "визита", "визитов"), at: 0)
        } else if let date = zone.firstVisit {
            parts.append(date.formatted(.dateTime.month(.wide).year()))
        }
        return parts.joined(separator: " · ")
    }
}

private struct FavoriteCityCard: View {
    let zone: CityZone

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PhotoThumbnail(assetID: zone.coverAssetID, size: 320)
                .frame(width: 150, height: 190)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(Geo.flag(for: zone.countryCode)).font(.title3)
                Text(zone.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(RU.photos(zone.photoCount))
                    .font(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(12)
        }
        .frame(width: 150, height: 190)
        .card(cornerRadius: 22)
    }
}
