import SwiftUI
import SwiftData
import MapKit

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TripImporter.self) private var importer
    @Environment(BoundaryStore.self) private var boundaryStore
    @AppStorage(SettingsKeys.cityBoundaries) private var useBoundaries = true

    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query private var dismissed: [DismissedSuggestion]

    @State private var showSuggestions = false
    @State private var showSettings = false
    @State private var countryToRemove: String?
    @State private var heroPosition: MapCameraPosition = .automatic
    @Namespace private var transition

    private var stats: TravelStats { TravelStats(trips: trips) }
    private var zones: [CityZone] { CityZone.aggregate(trips) }

    /// Поездки, сгруппированные по году начала (новые сверху).
    private var tripsByYear: [(year: Int, trips: [Trip])] {
        let groups = Dictionary(grouping: trips) { Calendar.current.component(.year, from: $0.startDate) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero

                    VStack(alignment: .leading, spacing: 32) {
                        StatsPanel(stats: stats, transition: transition)
                            .padding(.top, -52)

                        if !stats.countryCodes.isEmpty { countriesSection }

                        statusSection

                        ForEach(tripsByYear, id: \.year) { group in
                            yearSection(group.year, trips: group.trips)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await rescan() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(importer.phase == .scanning)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: AtlasRoute.self) { route in
                switch route {
                case .countries:
                    AtlasView(tab: .countries)
                        .navigationTransition(.zoom(sourceID: "atlas-countries", in: transition))
                case .cities:
                    AtlasView(tab: .cities)
                        .navigationTransition(.zoom(sourceID: "atlas-cities", in: transition))
                case .country(let code):
                    CountryDetailView(code: code)
                }
            }
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
                    .navigationTransition(.zoom(sourceID: trip.signature, in: transition))
            }
            .refreshable { await rescan() }
            .confirmationDialog(
                "Убрать \(countryToRemove.map { Geo.flag(for: $0) + " " + Geo.countryName(for: $0) } ?? "")?",
                isPresented: Binding(get: { countryToRemove != nil }, set: { if !$0 { countryToRemove = nil } }),
                titleVisibility: .visible
            ) {
                Button("Убрать из всех поездок", role: .destructive) {
                    if let code = countryToRemove {
                        withAnimation { importer.removeCountryEverywhere(code, trips: trips, in: context) }
                    }
                }
            } message: {
                Text("Например, если фото из самолёта определились в стране, где вы не были. Сами фото останутся в поездках.")
            }
            .sheet(isPresented: $showSuggestions) { SuggestionsView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task {
                if importer.lastScan == nil { await rescan() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let last = importer.lastScan,
                      Date().timeIntervalSince(last) > 600 else { return }
                Task { await rescan() }
            }
            .onChange(of: trips.count) {
                heroPosition = .automatic   // перецентрировать карту на новые зоны
            }
        }
    }

    // MARK: - Hero-карта

    private var hero: some View {
        NavigationLink {
            WorldMapView(trips: trips)
        } label: {
            ZStack(alignment: .bottomLeading) {
                ZoneMap(zones: zones, position: $heroPosition, interactive: false, showsAttribution: false)
                    .allowsHitTesting(false)

                // Затемнение под статус-бар и плавный переход в фон снизу.
                LinearGradient(colors: [Color(.systemBackground).opacity(0.7), .clear],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22))
                LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.85), Color(.systemBackground)],
                               startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Мой атлас")
                        .font(Theme.title(44))
                    Text(heroSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    if useBoundaries && !boundaryStore.polygons.isEmpty {
                        Text("Границы городов © OpenStreetMap")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 76)
            }
            .frame(height: 470)
            .contentShape(Rectangle())
            .visualEffect { content, proxy in
                // Растягивание при оттягивании вниз.
                let y = proxy.frame(in: .scrollView).minY
                return content.scaleEffect(y > 0 ? 1 + y / 470 : 1, anchor: .bottom)
            }
        }
        .buttonStyle(.plain)
    }

    private var heroSubtitle: String {
        if trips.isEmpty { return "Ваши путешествия появятся на этой карте" }
        return [RU.countries(stats.countryCount), RU.cities(stats.cityCount), RU.photos(stats.photoCount)]
            .joined(separator: " · ")
    }

    // MARK: - Секции

    private var countriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: AtlasRoute.countries) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Страны").font(Theme.title(26))
                    Spacer()
                    Text("Все \(Image(systemName: "chevron.right"))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stats.countryCodes, id: \.self) { code in
                        NavigationLink(value: AtlasRoute.country(code)) {
                            Chip(text: "\(Geo.flag(for: code))  \(Geo.countryName(for: code))")
                        }
                        .buttonStyle(PressableButtonStyle())
                        .contextMenu {
                            Button("Я не был в этой стране", systemImage: "flag.slash", role: .destructive) {
                                countryToRemove = code
                            }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func yearSection(_ year: Int, trips: [Trip]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(year))
                    .font(Theme.number(34))
                    .foregroundStyle(Theme.sunset)
                Spacer()
                Text(RU.trips(trips.count))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 18) {
                ForEach(trips) { trip in
                    NavigationLink(value: trip) {
                        TripCard(trip: trip)
                            .matchedTransitionSource(id: trip.signature, in: transition)
                    }
                    .buttonStyle(.plain)
                    .scrollFade()
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch importer.phase {
        case .scanning:
            HStack(spacing: 12) {
                ProgressView()
                Text("Ищу поездки в фотографиях…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .glass()

        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                Label("Нет доступа к фото", systemImage: "lock.fill").font(.headline)
                Text("Разрешите доступ к медиатеке, чтобы приложение нашло ваши поездки.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()

        case .ready where !importer.candidates.isEmpty:
            SuggestionsBanner(count: importer.candidates.count) { showSuggestions = true }

        case .ready where trips.isEmpty:
            ContentUnavailableView(
                "Поездок пока нет",
                systemImage: "airplane.departure",
                description: Text("В медиатеке не нашлось фото с геолокацией вдали от дома. Попробуйте изменить настройки распознавания.")
            )

        default:
            EmptyView()
        }
    }

    private func rescan() async {
        await importer.scan(existing: trips, dismissed: Set(dismissed.map(\.signature)))
        if !importer.candidates.isEmpty && trips.isEmpty { showSuggestions = true }
    }
}

// MARK: - Панель статистики

private struct StatsPanel: View {
    let stats: TravelStats
    let transition: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            item(stats.tripCount, RU.word(stats.tripCount, "поездка", "поездки", "поездок"))
            divider
            NavigationLink(value: AtlasRoute.countries) {
                item(stats.countryCount, RU.word(stats.countryCount, "страна", "страны", "стран"), tappable: true)
            }
            .buttonStyle(PressableButtonStyle())
            .matchedTransitionSource(id: "atlas-countries", in: transition)
            divider
            NavigationLink(value: AtlasRoute.cities) {
                item(stats.cityCount, RU.word(stats.cityCount, "город", "города", "городов"), tappable: true)
            }
            .buttonStyle(PressableButtonStyle())
            .matchedTransitionSource(id: "atlas-cities", in: transition)
            divider
            item(stats.dayCount, RU.word(stats.dayCount, "день", "дня", "дней") + " в пути")
        }
        .padding(.vertical, 18)
        .glass(cornerRadius: 26)
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }

    private var divider: some View {
        Rectangle().fill(.separator).frame(width: 1, height: 34)
    }

    private func item(_ value: Int, _ label: String, tappable: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(Theme.number(28))
                .foregroundStyle(tappable ? AnyShapeStyle(Theme.sunset) : AnyShapeStyle(.primary))
                .contentTransition(.numericText(value: Double(value)))
            HStack(spacing: 2) {
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Баннер с найденными поездками

private struct SuggestionsBanner: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.22), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Новые поездки: \(count)")
                        .font(.headline)
                    Text("Нашёл в ваших фото — посмотрите")
                        .font(.subheadline)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background {
                MeshGradient(
                    width: 3, height: 3,
                    points: [[0, 0], [0.5, 0], [1, 0],
                             [0, 0.5], [0.65, 0.45], [1, 0.5],
                             [0, 1], [0.5, 1], [1, 1]],
                    colors: [Theme.coral, Theme.rose, Theme.violet,
                             Theme.rose, Theme.coral, Theme.violet,
                             Theme.coral, Theme.violet, Theme.rose]
                )
            }
            .card(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }
}
