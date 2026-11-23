import SwiftUI
import Observation

/// Сборка видео-облёта: подготовка карты и фото, рендер, готовый файл.
@Observable
@MainActor
final class FlyoverModel {
    enum State: Equatable {
        case idle
        case preparing(Double)
        case rendering(Double)
        case ready(URL)
        case failed(String)
    }

    let subject: ShareSubject
    private(set) var state: State = .idle
    /// Последний отрисованный кадр — живое превью во время сборки.
    private(set) var preview: UIImage?
    private(set) var duration: Double = 0

    var pace: FlyoverPace = .calm
    var showPhotos = true
    /// Настройки, с которыми собран текущий ролик.
    private var builtWith: (FlyoverPace, Bool)?

    private var task: Task<Void, Never>?
    private var exportTask: Task<Void, Error>?

    init(subject: ShareSubject) {
        self.subject = subject
    }

    var isBusy: Bool {
        switch state {
        case .preparing, .rendering: true
        default: false
        }
    }

    var videoURL: URL? {
        if case .ready(let url) = state { return url }
        return nil
    }

    /// Настройки поменялись после сборки — нужна пересборка.
    var isOutdated: Bool {
        guard let builtWith, videoURL != nil else { return false }
        return builtWith.0 != pace || builtWith.1 != showPhotos
    }

    func build() {
        cancel()
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
        exportTask?.cancel()
        task = nil
        exportTask = nil
    }

    private func run() async {
        let pace = self.pace, showPhotos = self.showPhotos
        state = .preparing(0)
        preview = nil

        let cities = await FlyoverPreparation.stops(for: subject)
        guard !cities.isEmpty else {
            state = .failed("Нет городов — нечего показать на карте")
            return
        }
        let script = FlyoverScript(cities: cities, pace: pace)
        duration = script.duration

        let assets = await FlyoverPreparation.assets(for: script, loadPhotos: showPhotos) { [weak self] fraction in
            self?.state = .preparing(fraction)
        }
        guard !Task.isCancelled else { return }

        let renderer = FlyoverRenderer(script: script, assets: assets,
                                       info: FlyoverPreparation.info(for: subject), showPhotos: showPhotos)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ShareConfig.brandName) — \(Self.safeName(subject.shareTitle)).mp4")
        state = .rendering(0)

        do {
            let export = Task.detached(priority: .userInitiated) {
                try await FlyoverExporter.export(renderer: renderer, to: url) { [weak self] fraction, image in
                    self?.state = .rendering(fraction)
                    if let image { self?.preview = image }
                }
            }
            exportTask = export
            try await export.value
            builtWith = (pace, showPhotos)
            state = .ready(url)
        } catch {
            if !Task.isCancelled { state = .failed("Не удалось собрать видео") }
        }
    }

    private static func safeName(_ title: String) -> String {
        title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
    }
}
