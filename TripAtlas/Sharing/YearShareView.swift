import SwiftUI
import SwiftData

/// «Мой год в путешествиях»: те же карточки и видео-облёт, но по всем поездкам года.
struct YearShareView: View {
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var year: Int
    @State private var mode: ShareComposerView.Mode = .image

    init(year: Int) {
        _year = State(initialValue: year)
    }

    private var years: [Int] { ShareSubject.years(in: trips) }

    var body: some View {
        ShareComposerView(
            subject: .year(year, trips: trips),
            mode: mode,
            header: AnyView(YearPicker(years: years, selection: $year)),
            onModeChange: { mode = $0 }
        )
        // Новый год — новые фото, карта и видео: пересоздаём редактор.
        .id(year)
    }
}

/// Чипы с годами, в которые были поездки.
struct YearPicker: View {
    let years: [Int]
    @Binding var selection: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(years, id: \.self) { year in
                        let isSelected = year == selection
                        Button {
                            withAnimation(.snappy) { selection = year }
                        } label: {
                            Text(String(year))
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background {
                                    if isSelected {
                                        Capsule().fill(Theme.sunset)
                                    } else {
                                        Capsule().fill(Color(.secondarySystemGroupedBackground))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(year)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}

/// Баннер на главном экране.
struct YearRecapBanner: View {
    let year: Int
    let trips: Int
    let countries: Int

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Мой \(String(year))")
                    .font(Theme.title(30))
                Text("\(RU.trips(trips)) · \(RU.countries(countries))")
                    .font(.subheadline.weight(.medium))
                    .opacity(0.9)
                Text("Итоги года — картинкой или видео")
                    .font(.caption.weight(.semibold))
                    .opacity(0.75)
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 60, height: 60)
                .background(.white.opacity(0.2), in: Circle())
        }
        .foregroundStyle(.white)
        .padding(20)
        .background { SunsetBackground() }
        .card(cornerRadius: 26)
    }
}
