import SwiftUI

/// Карточка 360×640 pt (при рендере — 1080×1920).
/// Только «плоские» вью: без материалов и `Map` — они не рендерятся в картинку.
struct ShareCardView: View {
    let template: ShareTemplate
    let data: ShareCardData
    let options: ShareOptions

    var body: some View {
        Group {
            switch template {
            case .poster: PosterCard(data: data, options: options)
            case .collage: CollageCard(data: data, options: options)
            case .map: MapCard(data: data, options: options)
            }
        }
        .frame(width: ShareConfig.canvas.width, height: ShareConfig.canvas.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Постер

private struct PosterCard: View {
    let data: ShareCardData
    let options: ShareOptions

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CardPhoto(image: data.photos.first)
                .frame(width: 360, height: 640)

            LinearGradient(stops: [
                .init(color: .black.opacity(0.45), location: 0),
                .init(color: .clear, location: 0.22),
                .init(color: .clear, location: 0.42),
                .init(color: .black.opacity(0.55), location: 0.65),
                .init(color: .black.opacity(0.9), location: 1),
            ], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    BrandPill()
                    Spacer()
                    Text(data.flags).font(.system(size: 22))
                }
                Spacer()

                if !data.silhouettes.isEmpty {
                    SilhouetteRow(items: Array(data.silhouettes.prefix(4)))
                        .padding(.bottom, 4)
                }

                Text(data.title)
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.3), radius: 8)

                if options.showDates {
                    Text(data.dateText.uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.5)
                        .opacity(0.85)
                }

                if options.showStats {
                    StatsStrip(data: data)
                        .padding(.top, 6)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .background(Color.black)
    }
}

// MARK: - Коллаж

private struct CollageCard: View {
    let data: ShareCardData
    let options: ShareOptions

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.coral, Theme.rose, Theme.violet],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.28), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 420)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandPill()
                    Spacer()
                    Text(data.flags).font(.system(size: 22))
                }

                Text(data.title)
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 18)

                if options.showDates {
                    Text(data.dateText)
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(0.85)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
                PolaroidStack(photos: data.photos, captions: data.captions)
                    .frame(width: 312, height: 360)
                Spacer(minLength: 0)

                if options.showStats {
                    StatsStrip(data: data)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
    }
}

/// До пяти фото «полароидами» внахлёст.
private struct PolaroidStack: View {
    let photos: [UIImage]
    let captions: [String]

    private struct Slot { let x: CGFloat; let y: CGFloat; let angle: Double; let width: CGFloat }

    /// Раскладки для 1…5 фото; последнее рисуется сверху.
    private var slots: [Slot] {
        switch photos.count {
        case 0: []
        case 1: [Slot(x: 0, y: 0, angle: -3, width: 230)]
        case 2: [Slot(x: -55, y: -40, angle: -7, width: 190), Slot(x: 55, y: 50, angle: 5, width: 190)]
        case 3: [Slot(x: -70, y: -70, angle: -8, width: 165), Slot(x: 70, y: -55, angle: 7, width: 160),
                 Slot(x: 0, y: 70, angle: -2, width: 185)]
        case 4: [Slot(x: -72, y: -85, angle: -7, width: 160), Slot(x: 74, y: -95, angle: 6, width: 155),
                 Slot(x: -68, y: 75, angle: 5, width: 160), Slot(x: 76, y: 65, angle: -6, width: 160)]
        default: [Slot(x: -75, y: -95, angle: -8, width: 150), Slot(x: 78, y: -105, angle: 6, width: 145),
                  Slot(x: -70, y: 80, angle: 6, width: 150), Slot(x: 80, y: 75, angle: -7, width: 150),
                  Slot(x: 0, y: -8, angle: -2, width: 165)]
        }
    }

    var body: some View {
        ZStack {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                Polaroid(image: photos[index], caption: index < captions.count ? captions[index] : "", width: slot.width)
                    .rotationEffect(.degrees(slot.angle))
                    .offset(x: slot.x, y: slot.y)
            }
        }
    }
}

private struct Polaroid: View {
    let image: UIImage
    let caption: String
    let width: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width - 16, height: width - 16)
                .clipped()
            Text(caption)
                .font(.system(size: 12, weight: .medium, design: .serif).italic())
                .foregroundStyle(Color(white: 0.25))
                .lineLimit(1)
                .frame(height: 14)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(white: 0.98))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
    }
}

// MARK: - Карта

private struct MapCard: View {
    let data: ShareCardData
    let options: ShareOptions

    private static let background = Color(red: 0.086, green: 0.063, blue: 0.122)

    var body: some View {
        ZStack {
            Self.background
            RadialGradient(colors: [Theme.violet.opacity(0.45), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 380)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    BrandPill()
                    Spacer()
                    Text(data.flags).font(.system(size: 22))
                }

                Group {
                    if let map = data.map {
                        Image(uiImage: map).resizable().scaledToFill()
                    } else {
                        SunsetFill()
                    }
                }
                .frame(width: 312, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(data.title)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if options.showDates {
                        Text(data.dateText)
                            .font(.system(size: 14, weight: .semibold))
                            .opacity(0.7)
                    }
                }

                CityTimeline(cities: data.cities)

                Spacer(minLength: 0)

                if options.showStats {
                    StatsStrip(data: data)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
    }
}

/// «1 Рим → 2 Флоренция → 3 Венеция» в две колонки.
private struct CityTimeline: View {
    let cities: [String]

    private var shown: [String] { Array(cities.prefix(cities.count > 4 ? 3 : 4)) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(MapSnapshotRenderer.zoneColor(index + 1)))
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
            }
            if cities.count > 4 {
                Text("и ещё \(cities.count - 3)")
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.6)
            }
        }
    }
}

// MARK: - Общие элементы

/// Фото или градиент-заглушка, если фото нет.
private struct CardPhoto: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            SunsetFill()
        }
    }
}

struct SunsetFill: View {
    var body: some View {
        LinearGradient(colors: [Theme.coral, Theme.rose, Theme.violet],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Логотип приложения — реклама, ради которой всё и затевается.
struct BrandPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("ShareLogo")
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(ShareConfig.brandName)
                .font(.system(size: 13, weight: .bold))
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.18)))
        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.5))
        .foregroundStyle(.white)
    }
}

/// Цифры поездки в одну строку.
struct StatsStrip: View {
    let data: ShareCardData

    private var items: [(String, String)] {
        var result = [
            ("\(data.days)", RU.word(data.days, "день", "дня", "дней")),
            ("\(data.cityCount)", RU.word(data.cityCount, "город", "города", "городов")),
            ("\(data.photoCount)", "фото"),
        ]
        if data.distanceKm >= 10 { result.append((data.distanceKm.formatted(), "км")) }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 28)
                }
                VStack(spacing: 2) {
                    Text(item.0)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(item.1)
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.75)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 0.5))
    }
}

/// Силуэты городов по их настоящим границам.
private struct SilhouetteRow: View {
    let items: [ShareSilhouette]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(items) { item in
                VStack(spacing: 5) {
                    SilhouetteShape(rings: item.rings)
                        .fill(.white.opacity(0.2))
                        .overlay(SilhouetteShape(rings: item.rings).stroke(.white, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round)))
                        .frame(width: 44, height: 44)
                    Text(item.name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 64)
                }
            }
        }
    }
}

struct SilhouetteShape: Shape {
    let rings: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for ring in rings {
            guard let first = ring.first else { continue }
            path.move(to: point(first, in: rect))
            for p in ring.dropFirst() { path.addLine(to: point(p, in: rect)) }
            path.closeSubpath()
        }
        return path
    }

    private func point(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }
}
