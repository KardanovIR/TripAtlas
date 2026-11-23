import SwiftUI

/// Экран «Поделиться поездкой»: карусель шаблонов, выбор фото, отправка.
struct ShareComposerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case image, video
        var id: Self { self }
        var title: String { self == .image ? "Картинка" : "Видео" }
    }

    @State private var model: ShareComposerModel
    @State private var mode: Mode
    @State private var flyover: FlyoverModel?
    @State private var selectedTemplate: ShareTemplate? = .poster
    @State private var activityItems: ActivityItems?
    @State private var toast: String?
    @State private var isWorking = false
    @State private var successCount = 0

    @Environment(\.dismiss) private var dismiss

    private struct ActivityItems: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    /// Дополнительная строка над превью (например, выбор года).
    private let header: AnyView?
    private let onModeChange: (Mode) -> Void

    init(subject: ShareSubject, mode: Mode = .image, header: AnyView? = nil,
         onModeChange: @escaping (Mode) -> Void = { _ in }) {
        _model = State(initialValue: ShareComposerModel(subject: subject))
        _mode = State(initialValue: mode)
        self.header = header
        self.onModeChange = onModeChange
    }

    @MainActor
    init(trip: Trip, mode: Mode = .image) {
        self.init(subject: .trip(trip), mode: mode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let header { header.padding(.top, 8) }
                switch mode {
                case .image:
                    VStack(spacing: 18) {
                        carousel
                        templatePicker
                        optionsRow
                        photoStrip
                        actions
                    }
                    .padding(.bottom, 8)
                case .video:
                    if let flyover { FlyoverPanel(model: flyover) }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Picker("Формат", selection: $mode.animation(.snappy)) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
            .onChange(of: mode, initial: true) { _, new in
                if new == .video, flyover == nil { flyover = FlyoverModel(subject: model.subject) }
                onModeChange(new)
            }
            .onDisappear { flyover?.cancel() }
            .overlay(alignment: .top) { toastView }
            .sheet(item: $activityItems) { payload in
                ActivityView(items: payload.items) { completed in
                    if completed { successCount += 1 }
                }
                .presentationDetents([.medium, .large])
            }
            .sensoryFeedback(.success, trigger: successCount)
            .task { await model.prepare() }
            .onChange(of: selectedTemplate) { _, new in
                if let new { model.template = new }
            }
        }
    }

    // MARK: - Карусель шаблонов

    private var carousel: some View {
        GeometryReader { geo in
            let scale = min((geo.size.width - 80) / ShareConfig.canvas.width, geo.size.height / ShareConfig.canvas.height)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(ShareTemplate.allCases) { template in
                        preview(template, scale: scale)
                            .containerRelativeFrame(.horizontal)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.88)
                                    .opacity(phase.isIdentity ? 1 : 0.6)
                            }
                            .id(template)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selectedTemplate)
        }
        .padding(.top, 8)
    }

    private func preview(_ template: ShareTemplate, scale: CGFloat) -> some View {
        ShareCardView(template: template, data: model.data, options: model.options)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: ShareConfig.canvas.width * scale, height: ShareConfig.canvas.height * scale,
                   alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 28 * scale, style: .continuous))
            .overlay {
                if model.isPreparing {
                    ProgressView().tint(.white).controlSize(.large)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            .animation(.smooth, value: model.selectedIDs)
            .animation(.smooth, value: model.options)
    }

    private var templatePicker: some View {
        HStack(spacing: 8) {
            ForEach(ShareTemplate.allCases) { template in
                let isSelected = model.template == template
                Button {
                    withAnimation(.snappy) { selectedTemplate = template }
                } label: {
                    Text(template.title)
                        .font(.subheadline.weight(.semibold))
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
            }
        }
    }

    // MARK: - Опции и фото

    private var optionsRow: some View {
        HStack(spacing: 10) {
            optionToggle("Даты", systemImage: "calendar", isOn: $model.options.showDates)
            optionToggle("Цифры", systemImage: "number", isOn: $model.options.showStats)
        }
    }

    private func optionToggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) { isOn.wrappedValue.toggle() }
        } label: {
            Label(title, systemImage: isOn.wrappedValue ? "checkmark.circle.fill" : systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isOn.wrappedValue ? Color.primary : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var photoStrip: some View {
        if model.template.photoSlots > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.template.photoSlots == 1
                     ? "Обложка — нажмите на фото"
                     : "Фото для коллажа — до \(ShareComposerModel.maxSelection)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(model.candidateIDs, id: \.self) { id in
                            photoCell(id)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 64)
            }
            .transition(.opacity)
        } else {
            Text("Карта строится по границам городов из поездки")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: 86)
        }
    }

    private func photoCell(_ id: String) -> some View {
        let isCover = model.template.photoSlots == 1
        let position = model.position(of: id)
        let highlighted = isCover ? position == 1 : position != nil

        return Button {
            withAnimation(.snappy) {
                if isCover { model.makeCover(id) } else { model.toggle(id) }
            }
        } label: {
            PhotoThumbnail(assetID: id, size: 120)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.coral, lineWidth: highlighted ? 3 : 0)
                }
                .overlay(alignment: .topTrailing) {
                    if highlighted, let position {
                        Text(isCover ? "★" : "\(position)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Theme.sunset, in: Circle())
                            .padding(4)
                    }
                }
                .opacity(highlighted ? 1 : 0.75)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Кнопки

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await shareToStories() }
            } label: {
                HStack(spacing: 10) {
                    if isWorking { ProgressView().tint(.white) } else { Image(systemName: "camera.aperture") }
                    Text(ShareService.canShareToInstagram ? "В историю Instagram" : "Поделиться")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.sunset, in: Capsule())
                .shadow(color: Theme.rose.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isWorking || model.isPreparing)

            HStack(spacing: 10) {
                secondaryButton("Сохранить", systemImage: "square.and.arrow.down") {
                    Task { await save() }
                }
                secondaryButton("Ещё", systemImage: "square.and.arrow.up") {
                    openActivity()
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isWorking || model.isPreparing)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassCapsule()
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Действия

    private func renderCurrent() -> UIImage? {
        ShareService.render(model.template, data: model.data, options: model.options)
    }

    private func shareToStories() async {
        guard let image = renderCurrent() else { return showToast("Не удалось создать картинку") }
        isWorking = true
        defer { isWorking = false }
        if await ShareService.shareToInstagramStories(image) {
            successCount += 1
        } else {
            openActivity(image: image)
        }
    }

    private func save() async {
        guard let image = renderCurrent() else { return showToast("Не удалось создать картинку") }
        isWorking = true
        defer { isWorking = false }
        do {
            try await ShareService.saveToPhotos(image)
            successCount += 1
            showToast("Сохранено в Фото")
        } catch ShareService.SaveError.denied {
            showToast("Нет доступа к Фото — разрешите в Настройках")
        } catch {
            showToast("Не удалось сохранить")
        }
    }

    private func openActivity(image: UIImage? = nil) {
        guard let image = image ?? renderCurrent() else { return showToast("Не удалось создать картинку") }
        let file: Any = ShareService.temporaryFile(for: image, name: model.subject.shareTitle) ?? image
        activityItems = ActivityItems(items: [file, ShareService.caption(for: model.subject.shareTitle)])
    }

    private func showToast(_ text: String) {
        withAnimation(.snappy) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.snappy) { if toast == text { toast = nil } }
        }
    }
}
