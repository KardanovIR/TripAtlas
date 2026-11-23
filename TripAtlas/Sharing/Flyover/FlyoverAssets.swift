import MapKit
import UIKit

/// Снимок карты и прямоугольник, который он покрывает (в Меркаторе).
struct MapLayer {
    let image: UIImage
    let rect: CGRect
}

/// Всё, что нужно для отрисовки кадров. Загружается один раз до рендера.
struct FlyoverAssets {
    /// От крупного масштаба к мелкому: сначала обзор, потом детальные снимки.
    var layers: [MapLayer]
    var photos: [String: UIImage]
    var logo: UIImage?
    var plane: UIImage?
}

/// Текстовая часть ролика.
struct FlyoverInfo {
    let title: String
    let dateText: String
    let flags: String
    let days: Int
    let cityCount: Int
    let photoCount: Int
    let distanceKm: Int
}

@MainActor
enum FlyoverPreparation {

    /// Города поездки для ролика: не больше 6 (где больше всего фото), в порядке посещения.
    static func cities(for trip: Trip) async -> [FlyoverCity] {
        var places = trip.places
        if places.count > FlyoverScript.maxCities {
            let keep = Set(places.sorted { ($0.assetIDs?.count ?? 0) > ($1.assetIDs?.count ?? 0) }
                .prefix(FlyoverScript.maxCities).map(\.id))
            places = places.filter { keep.contains($0.id) }
        }

        var dates: [String: Date] = [:]
        if trip.assetDates.count == trip.assetIdentifiers.count {
            for (id, date) in zip(trip.assetIdentifiers, trip.assetDates) { dates[id] = date }
        }

        var result: [FlyoverCity] = []
        for (index, place) in places.enumerated() {
            var rings: [[CGPoint]] = []
            if BoundaryStore.isEnabled,
               case .found(let boundary) = await CityBoundaryService.shared.boundary(
                   key: place.id, latitude: place.latitude, longitude: place.longitude) {
                for polygon in boundary.polygons {
                    rings.append(polygon.outer.map { Mercator.project($0) })
                    rings.append(contentsOf: polygon.holes.map { ring in ring.map { Mercator.project($0) } })
                }
            }
            let ids = ShareComposerModel.spread(place.assetIDs ?? [], count: 3, first: place.coverAssetID)
            result.append(FlyoverCity(
                name: place.name,
                countryCode: place.countryCode,
                order: index + 1,
                center: Mercator.project(latitude: place.latitude, longitude: place.longitude),
                rings: rings,
                radius: Mercator.units(km: place.radiusKm ?? 3, latitude: place.latitude),
                photoIDs: ids,
                photoDates: ids.map { dates[$0] }
            ))
        }
        return result
    }

    static func info(for trip: Trip) -> FlyoverInfo {
        FlyoverInfo(title: trip.title, dateText: trip.dateRangeText, flags: trip.flags,
                    days: trip.dayCount, cityCount: trip.cityKeys.count,
                    photoCount: trip.assetIdentifiers.count, distanceKm: Int(trip.distanceKm.rounded()))
    }

    /// Снимки карты и фото. `progress` — от 0 до 1.
    static func assets(for script: FlyoverScript, loadPhotos: Bool,
                       progress: @escaping (Double) -> Void) async -> FlyoverAssets {
        // Обзор берём с запасом: камера отдаляется на перелётах и в финале.
        var plans: [(CGRect, CGSize)] = [(expand(script.overview.rect, by: 1.7), CGSize(width: 1620, height: 2880))]
        for (i, city) in script.cities.enumerated() {
            plans.append((expand(city.camera.rect, by: 1.45), CGSize(width: 1512, height: 2688)))
            if i > 0 {
                let pair = script.cities[i - 1].camera.rect.union(city.camera.rect)
                plans.append((fit(pair, scale: 1.3), CGSize(width: 1080, height: 1920)))
            }
        }

        let photoIDs: [String] = loadPhotos ? script.cities.flatMap(\.photoIDs) : []
        let total = Double(plans.count + photoIDs.count)
        var done = 0.0

        var layers: [MapLayer] = []
        for (rect, size) in plans {
            if let layer = await snapshot(rect, size: size) { layers.append(layer) }
            done += 1
            progress(done / total)
        }
        layers.sort { $0.rect.width > $1.rect.width }

        var photos: [String: UIImage] = [:]
        for id in photoIDs {
            if let image = await ImageLoader.shared.image(for: id, targetSize: CGSize(width: 640, height: 640)) {
                photos[id] = image
            }
            done += 1
            progress(done / total)
        }

        let plane = UIImage(systemName: "airplane",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .bold))?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        return FlyoverAssets(layers: layers, photos: photos, logo: UIImage(named: "ShareLogo"), plane: plane)
    }

    // MARK: - Снимки

    private static func expand(_ rect: CGRect, by k: Double) -> CGRect {
        let w = Double(rect.width) * k, h = Double(rect.height) * k
        return CGRect(x: Double(rect.midX) - w / 2, y: Double(rect.midY) - h / 2, width: w, height: h)
    }

    /// Прямоугольник 9:16, в который `rect` помещается с запасом.
    private static func fit(_ rect: CGRect, scale: Double) -> CGRect {
        let w = max(Double(rect.width), Double(rect.height) / FlyCamera.aspect) * scale
        let h = w * FlyCamera.aspect
        return CGRect(x: Double(rect.midX) - w / 2, y: Double(rect.midY) - h / 2, width: w, height: h)
    }

    private static func snapshot(_ rect: CGRect, size: CGSize) async -> MapLayer? {
        let clamped = rect.intersection(CGRect(x: 0, y: 0.02, width: 1, height: 0.96))
        guard !clamped.isNull, clamped.width > 0 else { return nil }

        let northWest = Mercator.unproject(CGPoint(x: clamped.minX, y: clamped.minY))
        let southEast = Mercator.unproject(CGPoint(x: clamped.maxX, y: clamped.maxY))
        let center = Mercator.unproject(CGPoint(x: clamped.midX, y: clamped.midY))

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            span: MKCoordinateSpan(latitudeDelta: northWest.latitude - southEast.latitude,
                                   longitudeDelta: southEast.longitude - northWest.longitude))
        options.size = size
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = .dark
            traits.displayScale = 1
        }
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        // MapKit может слегка подогнать регион — восстанавливаем точное соответствие
        // «Меркатор → пиксели» по двум известным точкам.
        let a = northWest, b = southEast
        let pa = snapshot.point(for: CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude))
        let pb = snapshot.point(for: CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude))
        let ma = Mercator.project(a), mb = Mercator.project(b)
        let sx = Double(pb.x - pa.x) / Double(mb.x - ma.x)
        let sy = Double(pb.y - pa.y) / Double(mb.y - ma.y)
        guard sx.isFinite, sy.isFinite, sx > 0, sy > 0 else { return nil }

        let minX = Double(ma.x) - Double(pa.x) / sx
        let minY = Double(ma.y) - Double(pa.y) / sy
        let rectOut = CGRect(x: minX, y: minY, width: Double(size.width) / sx, height: Double(size.height) / sy)
        return MapLayer(image: snapshot.image, rect: rectOut)
    }
}
