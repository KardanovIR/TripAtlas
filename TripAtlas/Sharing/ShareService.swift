import SwiftUI
import Photos
import UIKit

/// Рендер карточек и отправка их наружу.
@MainActor
enum ShareService {

    /// Карточка → картинка 1080×1920.
    static func render(_ template: ShareTemplate, data: ShareCardData, options: ShareOptions) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(template: template, data: data, options: options))
        renderer.scale = ShareConfig.renderScale
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(ShareConfig.canvas)
        return renderer.uiImage
    }

    /// Готовая JPEG-картинка во временной папке — так в меню «Поделиться» у неё
    /// будет понятное имя. Метаданных (геолокации) в ней нет: картинка нарисована заново.
    static func temporaryFile(for image: UIImage, name: String) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ShareConfig.brandName) — \(safe).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Подпись к публикации.
    static func caption(for title: String) -> String {
        var text = "\(title) — мои путешествия в \(ShareConfig.brandName) ✈️"
        if let link = ShareConfig.appLink { text += "\n\(link)" }
        return text
    }

    // MARK: - Instagram Stories

    static var canShareToInstagram: Bool { !ShareConfig.facebookAppID.isEmpty }

    /// Открывает редактор сторис Instagram с картинкой на фоне.
    /// Возвращает `false`, если Instagram не установлен или не настроен App ID.
    static func shareToInstagramStories(_ image: UIImage) async -> Bool {
        guard canShareToInstagram,
              let url = URL(string: "instagram-stories://share?source_application=\(ShareConfig.facebookAppID)"),
              let png = image.pngData() else { return false }

        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": png]],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        return await UIApplication.shared.open(url)
    }

    /// То же для видео: Instagram открывает редактор сторис с роликом на фоне.
    static func shareVideoToInstagramStories(_ url: URL) async -> Bool {
        guard canShareToInstagram,
              let link = URL(string: "instagram-stories://share?source_application=\(ShareConfig.facebookAppID)"),
              let data = try? Data(contentsOf: url) else { return false }

        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundVideo": data]],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        return await UIApplication.shared.open(link)
    }

    // MARK: - Фото

    enum SaveError: Error { case denied, failed }

    static func saveVideoToPhotos(_ url: URL) async throws {
        try await requestAddAccess()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            throw SaveError.failed
        }
    }

    private static func requestAddAccess() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { throw SaveError.denied }
    }

    static func saveToPhotos(_ image: UIImage) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            throw SaveError.failed
        }
    }
}

/// Системное меню «Поделиться».
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    var completion: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
