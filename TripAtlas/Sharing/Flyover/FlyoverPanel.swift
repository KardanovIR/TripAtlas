import SwiftUI
import AVFoundation
import Photos

/// Режим «Видео» в редакторе шеринга: сборка облёта, превью и отправка.
struct FlyoverPanel: View {
    /// Модель живёт в редакторе, чтобы готовое видео не пропадало при переключении режимов.
    let model: FlyoverModel
    @State private var activityItems: [Any]?
    @State private var toast: String?
    @State private var isWorking = false
    @State private var successCount = 0

    var body: some View {
        VStack(spacing: 18) {
            stage
            options
            actions
        }
        .padding(.bottom, 8)
        .overlay(alignment: .top) { toastView }
        .sheet(isPresented: Binding(get: { activityItems != nil }, set: { if !$0 { activityItems = nil } })) {
            ActivityView(items: activityItems ?? []) { completed in
                if completed { successCount += 1 }
            }
            .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.success, trigger: successCount)
        .task {
            if model.state == .idle { model.build() }
        }
    }

    // MARK: - Видео

    private var stage: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = min(geo.size.width - 80, height * 9 / 16)
            ZStack {
                Group {
                    if let url = model.videoURL {
                        LoopingVideoView(url: url)
                    } else if let preview = model.preview {
                        Image(uiImage: preview).resizable().scaledToFill()
                    } else {
                        SunsetFill()
                    }
                }
                .frame(width: width, height: width * 16 / 9)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)

                statusOverlay
                    .frame(width: width, height: width * 16 / 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch model.state {
        case .idle, .preparing:
            progressBadge(value: model.state == .idle ? 0 : fraction, title: "Готовлю карту и фото…")
        case .rendering(let value):
            progressBadge(value: value, title: "Собираю видео…")
        case .ready:
            if model.isOutdated {
                Button("Пересобрать с новыми настройками") { model.build() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                Button("Попробовать снова") { model.build() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(20)
        }
    }

    private var fraction: Double {
        if case .preparing(let value) = model.state { return value }
        return 0
    }

    private func progressBadge(value: Double, title: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(value, 0.02))
                    .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: value)
                Text("\(Int(value * 100))%")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
            }
            .frame(width: 64, height: 64)
            Text(title).font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Настройки

    private var options: some View {
        HStack(spacing: 8) {
            ForEach(FlyoverPace.allCases) { pace in
                chip(pace.title, selected: model.pace == pace) { model.pace = pace }
            }
            chip("Фото", systemImage: model.showPhotos ? "checkmark.circle.fill" : "photo",
                 selected: model.showPhotos) { model.showPhotos.toggle() }
        }
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.5 : 1)
    }

    private func chip(_ title: String, systemImage: String? = nil, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if selected {
                    Capsule().fill(Theme.sunset)
                } else {
                    Capsule().fill(Color(.secondarySystemGroupedBackground))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Кнопки

    private var actions: some View {
        let disabled = model.videoURL == nil || isWorking
        return VStack(spacing: 10) {
            Button {
                Task { await shareToStories() }
            } label: {
                HStack(spacing: 10) {
                    if isWorking { ProgressView().tint(.white) } else { Image(systemName: "play.rectangle.fill") }
                    Text(ShareService.canShareToInstagram ? "В историю Instagram" : "Поделиться видео")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.sunset, in: Capsule())
                .shadow(color: Theme.rose.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(disabled)
            .opacity(disabled ? 0.6 : 1)

            HStack(spacing: 10) {
                secondaryButton("Сохранить", systemImage: "square.and.arrow.down") { Task { await save() } }
                secondaryButton("Ещё", systemImage: "square.and.arrow.up") { openActivity() }
            }
            .disabled(disabled)
            .opacity(disabled ? 0.6 : 1)
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

    private func shareToStories() async {
        guard let url = model.videoURL else { return }
        isWorking = true
        defer { isWorking = false }
        if await ShareService.shareVideoToInstagramStories(url) {
            successCount += 1
        } else {
            openActivity()
        }
    }

    private func save() async {
        guard let url = model.videoURL else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await ShareService.saveVideoToPhotos(url)
            successCount += 1
            showToast("Видео сохранено в Фото")
        } catch ShareService.SaveError.denied {
            showToast("Нет доступа к Фото — разрешите в Настройках")
        } catch {
            showToast("Не удалось сохранить")
        }
    }

    private func openActivity() {
        guard let url = model.videoURL else { return }
        activityItems = [url, ShareService.caption(for: model.trip.title)]
    }

    private func showToast(_ text: String) {
        withAnimation(.snappy) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.snappy) { if toast == text { toast = nil } }
        }
    }
}

/// Бесшумное зацикленное видео без элементов управления.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
        var url: URL?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        configure(view)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.url != url { configure(view) }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
        view.looper = nil
    }

    private func configure(_ view: PlayerView) {
        let player = AVQueuePlayer()
        player.isMuted = true
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.url = url
        player.play()
    }
}
