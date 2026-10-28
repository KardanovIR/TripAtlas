import Foundation
import MapKit
import Observation

/// Границы городов для экранов: загружает их по мере появления на карте
/// и держит готовые `MKPolygon`, чтобы не пересоздавать их при каждой перерисовке.
@Observable
@MainActor
final class BoundaryStore {
    private(set) var boundaries: [String: CityBoundary] = [:]
    private(set) var polygons: [String: [MKPolygon]] = [:]
    /// Сколько городов ещё ждут загрузки (для индикатора).
    private(set) var pending = 0
    /// Увеличивается при очистке кэша — карты перезапрашивают границы.
    private(set) var generation = 0

    @ObservationIgnored private var requested = Set<String>()

    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.cityBoundaries) as? Bool ?? true
    }

    /// Регион города: по границе, если она есть, иначе по кругу.
    func region(for zone: CityZone) -> MKCoordinateRegion {
        boundaries[zone.id]?.region ?? zone.region
    }

    /// Подгружает границы для зон, которых ещё нет. Порядок зон — порядок загрузки.
    func load(_ zones: [CityZone]) async {
        guard Self.isEnabled else { return }
        let todo = zones.filter { !requested.contains($0.id) }
        guard !todo.isEmpty else { return }
        todo.forEach { requested.insert($0.id) }
        pending += todo.count

        for zone in todo {
            let result = await CityBoundaryService.shared.boundary(
                key: zone.id, latitude: zone.latitude, longitude: zone.longitude)
            pending -= 1
            switch result {
            case .found(let boundary):
                boundaries[zone.id] = boundary
                polygons[zone.id] = boundary.makeMKPolygons()
            case .missing:
                break
            case .failed:
                requested.remove(zone.id)   // повторим при следующем показе карты
            }
        }
    }

    func clear() async {
        await CityBoundaryService.shared.clearCache()
        boundaries.removeAll()
        polygons.removeAll()
        requested.removeAll()
        generation += 1
    }

    /// Заранее скачивает границы городов новой поездки (в фоне, сразу после её создания).
    nonisolated static func prefetch(_ places: [Place]) {
        guard isEnabled else { return }
        Task.detached(priority: .utility) {
            for place in places {
                _ = await CityBoundaryService.shared.boundary(
                    key: place.id, latitude: place.latitude, longitude: place.longitude)
            }
        }
    }
}
