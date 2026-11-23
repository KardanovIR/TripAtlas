import UIKit
import SwiftUI

/// Шаблон карточки для сторис.
enum ShareTemplate: String, CaseIterable, Identifiable {
    case poster, collage, map

    var id: Self { self }

    var title: String {
        switch self {
        case .poster: "Постер"
        case .collage: "Коллаж"
        case .map: "Карта"
        }
    }

    /// Сколько фото использует шаблон.
    var photoSlots: Int {
        switch self {
        case .poster: 1
        case .collage: 5
        case .map: 0
        }
    }
}

/// Контур города, приведённый к квадрату 0…1 (ось Y вниз).
struct ShareSilhouette: Identifiable {
    let id: String
    let name: String
    let rings: [[CGPoint]]
}

/// Всё, что нужно карточке. Картинки уже загружены — `ImageRenderer`
/// не умеет ждать асинхронную загрузку.
struct ShareCardData {
    var title: String
    var dateText: String
    var flags: String
    var days: Int
    var cityCount: Int
    var photoCount: Int
    var distanceKm: Int
    /// Города в порядке посещения.
    var cities: [String]
    /// Выбранные фото; первое — обложка.
    var photos: [UIImage]
    /// Подписи к фото (город съёмки), параллельно `photos`.
    var captions: [String]
    var map: UIImage?
    var silhouettes: [ShareSilhouette]
}

struct ShareOptions: Equatable {
    var showDates = true
    var showStats = true
}

/// Настройки шеринга.
enum ShareConfig {
    /// Холст карточки в поинтах; при рендере ×3 = 1080×1920 (формат сторис).
    static let canvas = CGSize(width: 360, height: 640)
    static let renderScale: CGFloat = 3

    /// Facebook App ID — Instagram требует его для прямой отправки в сторис
    /// (developers.facebook.com → создать приложение → App ID). Пока пусто,
    /// кнопка Instagram открывает обычное меню «Поделиться».
    static let facebookAppID = ""

    /// Ссылка на приложение для подписи к публикации. Пока приложения нет в App Store,
    /// можно подставить ссылку TestFlight.
    static let appLink: String? = nil

    static let brandName = "TripAtlas"
}

// MARK: - Контуры городов

enum SilhouetteBuilder {
    /// Нормализует контуры границы в квадрат 0…1 с сохранением пропорций.
    static func normalize(_ boundary: CityBoundary) -> [[CGPoint]] {
        let rings: [[Coordinate]] = boundary.polygons
            .sorted { GeoPolygon.areaKm2($0.outer) > GeoPolygon.areaKm2($1.outer) }
            .prefix(6)
            .map(\.outer)
        guard !rings.isEmpty else { return [] }

        let lat0 = (boundary.minLatitude + boundary.maxLatitude) / 2 * .pi / 180
        let k = cos(lat0)
        func project(_ c: Coordinate) -> CGPoint { CGPoint(x: c.longitude * k, y: -c.latitude) }

        let projected: [[CGPoint]] = rings.map { $0.map(project) }
        let all: [CGPoint] = projected.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        let w = maxX - minX, h = maxY - minY
        let size = max(w, h)
        guard size > 0 else { return [] }
        let dx = (size - w) / 2, dy = (size - h) / 2

        return projected.map { ring in
            ring.map { CGPoint(x: ($0.x - minX + dx) / size, y: ($0.y - minY + dy) / size) }
        }
    }
}
