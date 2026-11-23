import SwiftUI
import SwiftData

/// Служебные фото, скрытые из поездки: посмотреть и вернуть.
struct HiddenPhotosView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Приложение решило, что это чеки, документы, фото экранов или досок, и убрало их из поездки, карточек и видео. Отметьте те, что нужно вернуть.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(trip.hiddenAssets, id: \.id) { asset in
                            cell(asset.id)
                        }
                    }
                    .padding(.horizontal, 3)
                }
                .padding(.vertical, 12)
            }
            .overlay {
                if trip.hiddenAssets.isEmpty {
                    ContentUnavailableView("Всё вернули", systemImage: "checkmark.circle")
                }
            }
            .navigationTitle("Скрытые фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(selected.isEmpty ? "Вернуть все" : "Вернуть выбранные (\(selected.count))") {
                        restore(selected.isEmpty ? Set(trip.hiddenAssets.map(\.id)) : selected)
                    }
                    .fontWeight(.semibold)
                    .disabled(trip.hiddenAssets.isEmpty)
                }
            }
        }
    }

    private func cell(_ id: String) -> some View {
        let isSelected = selected.contains(id)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { PhotoThumbnail(assetID: id, size: 130) }
            .clipped()
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Theme.coral : .black.opacity(0.25))
                    .padding(6)
            }
            .opacity(isSelected ? 1 : 0.85)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelected { selected.remove(id) } else { selected.insert(id) }
            }
    }

    private func restore(_ ids: Set<String>) {
        withAnimation {
            trip.restore(ids)
            selected.subtract(ids)
        }
        try? context.save()
    }
}
