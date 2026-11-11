import SwiftUI
import SwiftData
import MapKit

/// Страница страны: карта городов, список городов и поездки.
struct CountryDetailView: View {
    let code: String

    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @State private var position: MapCameraPosition = .automatic
    @State private var openedZone: CityZone?

    private var countryTrips: [Trip] { trips.filter { $0.countryCodes.contains(code) } }
    private var zones: [CityZone] {
        CityZone.aggregate(countryTrips)
            .filter { $0.countryCode == code }
            .sorted { $0.photoCount > $1.photoCount }
    }
    private var name: String { Geo.countryName(for: code) }

    var body: some View {
        let zones = self.zones
        let countryTrips = self.countryTrips

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(zones: zones, trips: countryTrips)

                if !zones.isEmpty {
                    ZoneMap(zones: zones, position: $position,
                            onSelect: { openedZone = $0 }, labelDistance: 1_500_000)
                        .frame(height: 280)
                        .card()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Города", trailing: "\(zones.count)")
                        CardList(items: zones) { zone in
                            Button { openedZone = zone } label: { CityRow(zone: zone) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !countryTrips.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "Поездки", trailing: "\(countryTrips.count)")
                        ForEach(countryTrips) { trip in
                            NavigationLink(value: trip) { TripCard(trip: trip) }
                                .buttonStyle(PressableButtonStyle())
                        }
                    }
                }

                if zones.isEmpty && countryTrips.isEmpty {
                    ContentUnavailableView("Здесь вы ещё не были", systemImage: "airplane",
                                           description: Text("Когда в поездке появятся фото из этой страны, они будут здесь."))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedZone) { zone in
            CityPhotosView(zone: zone, trips: countryTrips)
        }
    }

    private func header(zones: [CityZone], trips: [Trip]) -> some View {
        let photos = zones.reduce(0) { $0 + $1.photoCount }
        let days = trips.reduce(0) { $0 + $1.dayCount }
        return VStack(alignment: .leading, spacing: 10) {
            Text(Geo.flag(for: code))
                .font(.system(size: 72))
            Text(name)
                .font(Theme.title(38))
            HStack(spacing: 0) {
                stat(trips.count, RU.word(trips.count, "поездка", "поездки", "поездок"))
                stat(zones.count, RU.word(zones.count, "город", "города", "городов"))
                stat(days, RU.word(days, "день", "дня", "дней"))
                stat(photos, "фото")
            }
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(.top, 8)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(Theme.number(24))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
