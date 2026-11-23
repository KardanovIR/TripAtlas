import SwiftUI
import Observation

/// Состояние экрана «Поделиться поездкой»: выбранный шаблон, фото, опции
/// и заранее загруженные картинки для карточек.
@Observable
@MainActor
final class ShareComposerModel {
    let trip: Trip

    var template: ShareTemplate = .poster
    var options = ShareOptions()
    /// Выбранные фото по порядку; первое — обложка.
    private(set) var selectedIDs: [String] = []
    /// Фото, из которых можно выбирать (равномерно по поездке).
    let candidateIDs: [String]

    private(set) var images: [String: UIImage] = [:]
    private(set) var mapImage: UIImage?
    private(set) var silhouettes: [ShareSilhouette] = []
    private(set) var isPreparing = true

    static let maxSelection = 5

    init(trip: Trip) {
        self.trip = trip
        candidateIDs = Self.spread(trip.assetIdentifiers, count: 40, first: trip.coverAssetIdentifier)
        let defaults = Self.spread(candidateIDs, count: Self.maxSelection, first: trip.coverAssetIdentifier)
        selectedIDs = defaults
    }

    // MARK: - Данные для карточки

    var data: ShareCardData {
        let photos: [UIImage] = selectedIDs.compactMap { images[$0] }
        let captions: [String] = selectedIDs.filter { images[$0] != nil }.map { trip.place(containing: $0)?.name ?? "" }
        return ShareCardData(
            title: trip.title,
            dateText: trip.dateRangeText,
            flags: trip.flags,
            days: trip.dayCount,
            cityCount: trip.cityKeys.count,
            photoCount: trip.assetIdentifiers.count,
            distanceKm: Int(trip.distanceKm.rounded()),
            cities: trip.places.map(\.name),
            photos: photos,
            captions: captions,
            map: mapImage,
            silhouettes: silhouettes
        )
    }

    // MARK: - Выбор фото

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }
    func position(of id: String) -> Int? { selectedIDs.firstIndex(of: id).map { $0 + 1 } }

    func toggle(_ id: String) {
        if let index = selectedIDs.firstIndex(of: id) {
            guard selectedIDs.count > 1 else { return }   // хотя бы одно фото остаётся
            selectedIDs.remove(at: index)
        } else {
            if selectedIDs.count >= Self.maxSelection { selectedIDs.removeLast() }
            selectedIDs.append(id)
            Task { await loadPhoto(id) }
        }
    }

    /// Делает фото обложкой (первым).
    func makeCover(_ id: String) {
        selectedIDs.removeAll { $0 == id }
        selectedIDs.insert(id, at: 0)
        if selectedIDs.count > Self.maxSelection { selectedIDs.removeLast() }
        Task { await loadPhoto(id) }
    }

    // MARK: - Загрузка

    func prepare() async {
        isPreparing = true
        async let photos: Void = loadSelectedPhotos()
        async let map: Void = loadMapAndSilhouettes()
        _ = await (photos, map)
        isPreparing = false
    }

    private func loadSelectedPhotos() async {
        for id in selectedIDs { await loadPhoto(id) }
    }

    private func loadPhoto(_ id: String) async {
        guard images[id] == nil else { return }
        // Обложка постера — на весь экран 1080×1920, остальным хватит поменьше.
        let side: CGFloat = id == selectedIDs.first ? 1920 : 900
        if let image = await ImageLoader.shared.image(for: id, targetSize: CGSize(width: side, height: side)) {
            images[id] = image
        }
    }

    private func loadMapAndSilhouettes() async {
        var zones: [MapSnapshotRenderer.Zone] = []
        var shapes: [ShareSilhouette] = []
        for (index, place) in trip.places.enumerated() {
            var boundary: CityBoundary?
            if BoundaryStore.isEnabled,
               case .found(let b) = await CityBoundaryService.shared.boundary(
                   key: place.id, latitude: place.latitude, longitude: place.longitude) {
                boundary = b
                let rings = SilhouetteBuilder.normalize(b)
                if !rings.isEmpty { shapes.append(ShareSilhouette(id: place.id, name: place.name, rings: rings)) }
            }
            zones.append(.init(place: place, boundary: boundary, order: index + 1))
        }
        silhouettes = shapes
        mapImage = await MapSnapshotRenderer.render(zones: zones, size: CGSize(width: 312, height: 300), dark: true)
    }

    // MARK: - Утилиты

    /// `count` элементов, равномерно разбросанных по массиву; `first` — в начало.
    static func spread(_ ids: [String], count: Int, first: String?) -> [String] {
        guard !ids.isEmpty else { return [] }
        var result: [String] = []
        if let first, ids.contains(first) { result.append(first) }
        let step = max(1, Double(ids.count) / Double(count))
        var position = 0.0
        while result.count < count && Int(position) < ids.count {
            let id = ids[Int(position)]
            if !result.contains(id) { result.append(id) }
            position += step
        }
        return result
    }
}
