import Foundation
import UIKit
import Vision

/// Оценка фото: служебное ли оно и насколько удачное.
struct PhotoAssessment: Codable, Sendable {
    /// Чек, документ, скриншот, фото экрана или доски — Vision называет это «utility».
    let isUtility: Bool
    /// Эстетическая оценка Vision, от -1 (неудачное) до 1 (красивое).
    let score: Double
}

/// Анализ фото на устройстве (Vision, iOS 18): `CalculateImageAestheticsScoresRequest`
/// даёт и оценку красоты, и признак служебного снимка. Работает по маленьким превью,
/// результаты кэшируются на диске — каждое фото анализируется один раз.
actor PhotoQualityService {
    static let shared = PhotoQualityService()

    private var cache: [String: PhotoAssessment] = [:]
    private var isDirty = false

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("photo-quality.json")
    }()

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: PhotoAssessment].self, from: data) {
            cache = decoded
        }
    }

    /// Оценки для фото. Фото, которые не удалось проанализировать, в результат не попадают.
    func assess(_ ids: [String], progress: (@Sendable (Double) -> Void)? = nil) async -> [String: PhotoAssessment] {
        var result: [String: PhotoAssessment] = [:]
        let todo = ids.filter { cache[$0] == nil }
        for id in ids { if let cached = cache[id] { result[id] = cached } }

        var done = 0
        // По 4 фото параллельно: Vision и загрузка превью хорошо распараллеливаются.
        for chunk in stride(from: 0, to: todo.count, by: 4).map({ Array(todo[$0..<min($0 + 4, todo.count)]) }) {
            let assessed = await withTaskGroup(of: (String, PhotoAssessment?).self) { group in
                for id in chunk {
                    group.addTask { (id, await Self.analyze(id)) }
                }
                var pairs: [(String, PhotoAssessment?)] = []
                for await pair in group { pairs.append(pair) }
                return pairs
            }
            for (id, assessment) in assessed {
                guard let assessment else { continue }
                cache[id] = assessment
                result[id] = assessment
                isDirty = true
            }
            done += chunk.count
            progress?(Double(done) / Double(max(todo.count, 1)))
        }
        persist()
        return result
    }

    private static func analyze(_ id: String) async -> PhotoAssessment? {
        guard let image = await ImageLoader.shared.image(for: id, targetSize: CGSize(width: 360, height: 360),
                                                        contentMode: .aspectFit),
              let cgImage = image.cgImage else { return nil }
        do {
            let observation = try await CalculateImageAestheticsScoresRequest()
                .perform(on: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            return PhotoAssessment(isUtility: observation.isUtility, score: Double(observation.overallScore))
        } catch {
            return nil
        }
    }

    private func persist() {
        guard isDirty, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
        isDirty = false
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
