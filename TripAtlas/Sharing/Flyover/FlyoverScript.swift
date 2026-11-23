import Foundation
import CoreGraphics

// MARK: - Меркатор

/// Веб-Меркатор в единицах 0…1 (как у тайлов карт): x — восток, y — вниз (на юг).
/// В этой проекции снимки MapKit линейны, поэтому камеру удобно двигать в ней.
enum Mercator {
    static func project(latitude: Double, longitude: Double) -> CGPoint {
        let lat = min(max(latitude, -85), 85) * .pi / 180
        let x = (longitude + 180) / 360
        let y = 0.5 - log(tan(.pi / 4 + lat / 2)) / (2 * .pi)
        return CGPoint(x: x, y: y)
    }

    static func project(_ c: Coordinate) -> CGPoint { project(latitude: c.latitude, longitude: c.longitude) }

    static func unproject(_ p: CGPoint) -> Coordinate {
        let lon = Double(p.x) * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * Double(p.y)))) * 180 / .pi
        return Coordinate(latitude: lat, longitude: lon)
    }

    /// Сколько единиц Меркатора занимает `km` по горизонтали на широте `latitude`.
    static func units(km: Double, latitude: Double) -> Double {
        km / (40_075 * max(cos(latitude * .pi / 180), 0.05))
    }
}

/// Камера: центр и ширина кадра в единицах Меркатора. Высота — по пропорции 9:16.
struct FlyCamera: Equatable {
    var center: CGPoint
    var width: Double

    static let aspect = 1920.0 / 1080.0   // высота / ширина

    var height: Double { width * Self.aspect }

    var rect: CGRect {
        CGRect(x: Double(center.x) - width / 2, y: Double(center.y) - height / 2, width: width, height: height)
    }

    /// Полёт с «подскоком»: на длинных перелётах камера сначала отдаляется, потом снова
    /// приближается — как в навигаторах (упрощённый вариант алгоритма ван Вейка).
    static func fly(from a: FlyCamera, to b: FlyCamera, t: Double) -> FlyCamera {
        let ax = Double(a.center.x), ay = Double(a.center.y)
        let bx = Double(b.center.x), by = Double(b.center.y)
        let center = CGPoint(x: ax + (bx - ax) * t, y: ay + (by - ay) * t)
        let logA = log(a.width), logB = log(b.width)
        var logW = logA + (logB - logA) * t

        let distance: Double = hypot(bx - ax, by - ay)
        let peak = log(max(distance * 1.6, a.width, b.width))
        let bump = peak - max(logA, logB)
        if bump > 0 { logW += bump * sin(.pi * t) }
        return FlyCamera(center: center, width: exp(logW))
    }
}

// MARK: - Сценарий

/// Круг вместо границы (если её нет в OSM), в Меркаторе.
struct FlyoverCircle {
    let center: CGPoint
    let radius: Double
}

/// Остановка облёта: город поездки или целая поездка в итогах года.
struct FlyoverCity {
    let name: String
    /// «🇮🇹 Италия» для города или флаги и даты для поездки года.
    let subtitle: String?
    let order: Int
    /// Центр остановки (среднее положение фото), Меркатор.
    let center: CGPoint
    /// Контуры границ в Меркаторе (внешние кольца и вырезы — заливка even-odd).
    let rings: [[CGPoint]]
    /// Города без границы — кругами.
    let circles: [FlyoverCircle]
    let photoIDs: [String]
    let photoDates: [Date?]
    /// Остановка «дома» в итогах года: короткая пересадка, без зоны и фото.
    var isHome = false

    /// Камера, в которую город помещается с запасом.
    var camera: FlyCamera {
        let cx = Double(center.x), cy = Double(center.y)
        var minX = cx, maxX = cx, minY = cy, maxY = cy
        for circle in circles {
            let x = Double(circle.center.x), y = Double(circle.center.y)
            minX = min(minX, x - circle.radius); maxX = max(maxX, x + circle.radius)
            minY = min(minY, y - circle.radius); maxY = max(maxY, y + circle.radius)
        }
        for p in rings.flatMap({ $0 }) {
            minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
            minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
        }
        let latitude = Mercator.unproject(center).latitude
        let minWidth = Mercator.units(km: 14, latitude: latitude)
        let fit: Double = max(maxX - minX, (maxY - minY) / FlyCamera.aspect) * 1.9
        return FlyCamera(center: center, width: max(fit, minWidth))
    }
}

enum FlyoverPace: String, CaseIterable, Identifiable {
    case calm, dynamic
    var id: Self { self }
    var title: String { self == .calm ? "Спокойно" : "Динамично" }
}

/// Хронометраж ролика и положение камеры в любой момент времени.
struct FlyoverScript {
    enum Phase: Equatable {
        case intro(t: Double)
        case fly(to: Int, t: Double)
        case stay(city: Int, t: Double)
        case outroFly(t: Double)
        case outroHold(t: Double)
    }

    let cities: [FlyoverCity]
    let overview: FlyCamera

    let intro: Double
    let outroFly: Double
    let outroHold: Double
    /// Длительность перелёта к остановке `i` и стоянки в ней.
    let flyDurations: [Double]
    let stayDurations: [Double]
    private let flyStarts: [Double]

    static let fps = 30
    static let maxCities = 6
    /// В итогах года остановки — поездки.
    static let maxTrips = 8

    init(cities: [FlyoverCity], pace: FlyoverPace) {
        self.cities = cities
        overview = Self.overview(for: cities)

        let visits = cities.filter { !$0.isHome }.count
        let dynamic = pace == .dynamic || visits > 5
        let fly = dynamic ? 1.2 : 1.7
        let stay = visits == 1 ? 4.0 : (dynamic ? 2.0 : 2.8)
        intro = dynamic ? 1.6 : 2.2
        outroFly = dynamic ? 1.3 : 1.7
        outroHold = 2.8

        // Дом — короткая пересадка: подольше только в самом начале.
        flyDurations = cities.map { $0.isHome ? fly * 0.85 : fly }
        stayDurations = cities.enumerated().map { i, city in
            city.isHome ? (i == 0 ? 0.9 : 0.4) : stay
        }
        var starts: [Double] = []
        var time = intro
        for i in cities.indices {
            starts.append(time)
            time += flyDurations[i] + stayDurations[i]
        }
        flyStarts = starts
    }

    var duration: Double { outroStart + outroFly + outroHold }

    var frameCount: Int { Int((duration * Double(Self.fps)).rounded(.up)) }

    /// Начало перелёта к остановке `i`.
    func flyStart(_ i: Int) -> Double { flyStarts[i] }
    /// Начало стоянки в остановке `i`.
    func stayStart(_ i: Int) -> Double { flyStarts[i] + flyDurations[i] }
    func stayEnd(_ i: Int) -> Double { stayStart(i) + stayDurations[i] }
    var outroStart: Double { cities.isEmpty ? intro : stayEnd(cities.count - 1) }

    /// Номер посещения (без учёта дома) и общее число посещений — для «2 / 5».
    func visitNumber(_ i: Int) -> (Int, Int) {
        let visits = cities.indices.filter { !cities[$0].isHome }
        return ((visits.firstIndex(of: i) ?? 0) + 1, visits.count)
    }

    func phase(at time: Double) -> Phase {
        if time < intro { return .intro(t: time / intro) }
        for i in cities.indices {
            if time < stayStart(i) { return .fly(to: i, t: (time - flyStart(i)) / flyDurations[i]) }
            if time < stayEnd(i) { return .stay(city: i, t: (time - stayStart(i)) / stayDurations[i]) }
        }
        if time < outroStart + outroFly { return .outroFly(t: (time - outroStart) / outroFly) }
        return .outroHold(t: min(1, (time - outroStart - outroFly) / outroHold))
    }

    func camera(at time: Double) -> FlyCamera {
        switch phase(at: time) {
        case .intro(let t):
            return FlyCamera(center: overview.center, width: overview.width * (1.08 - 0.08 * Ease.inOutCubic(t)))
        case .fly(let i, let t):
            let from = i == 0 ? overview : cityCamera(i - 1, t: 1)
            return FlyCamera.fly(from: from, to: cityCamera(i, t: 0), t: Ease.inOutCubic(t))
        case .stay(let i, let t):
            return cityCamera(i, t: t)
        case .outroFly(let t):
            return FlyCamera.fly(from: cityCamera(cities.count - 1, t: 1), to: overview, t: Ease.inOutCubic(t))
        case .outroHold(let t):
            return FlyCamera(center: overview.center, width: overview.width * (1 + 0.04 * t))
        }
    }

    /// Камера над городом с медленным «наездом» (дома — без него: это пересадка).
    func cityCamera(_ i: Int, t: Double) -> FlyCamera {
        var camera = cities[i].camera
        if !cities[i].isHome { camera.width *= 1 - 0.1 * t }
        return camera
    }

    /// Какая часть маршрута к остановке `i` уже нарисована (0…1).
    func routeProgress(to i: Int, at time: Double) -> Double {
        guard i > 0 else { return 0 }
        return min(max((time - flyStart(i)) / flyDurations[i], 0), 1)
    }

    /// Насколько «зажжён» город `i` (0…1): разгорается за 0,6 с после прилёта.
    func reveal(_ i: Int, at time: Double) -> Double {
        min(max((time - stayStart(i) + 0.15) / 0.6, 0), 1)
    }

    static func overview(for cities: [FlyoverCity]) -> FlyCamera {
        guard !cities.isEmpty else { return FlyCamera(center: CGPoint(x: 0.5, y: 0.5), width: 1) }
        let rects = cities.map(\.camera.rect)
        let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        let width: Double = max(Double(union.width), Double(union.height) / FlyCamera.aspect) * 1.15
        let maxCity: Double = cities.map(\.camera.width).max() ?? width
        return FlyCamera(center: CGPoint(x: union.midX, y: union.midY), width: min(max(width, maxCity * 1.8), 1))
    }
}

// MARK: - Плавность

enum Ease {
    static func inOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    static func outCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    /// С лёгким «перелётом» за 1 — для выскакивающих фото.
    static func outBack(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    /// 0 до `a`, 1 после `b`, плавно между.
    static func step(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
