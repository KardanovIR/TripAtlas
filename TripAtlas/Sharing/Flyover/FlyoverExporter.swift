import AVFoundation
import UIKit

/// Рисует кадры и кодирует их в MP4 (H.264, 1080×1920, 30 к/с).
enum FlyoverExporter {

    enum ExportError: Error { case writer, buffer, cancelled }

    /// `progress` получает долю готовности и изредка — превью текущего кадра.
    static func export(renderer: FlyoverRenderer, to url: URL,
                       progress: @escaping @MainActor (Double, UIImage?) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)

        let size = FlyoverRenderer.size
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: FlyoverScript.fps,
                AVVideoMaxKeyFrameIntervalKey: FlyoverScript.fps,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw ExportError.writer }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.writer }
        writer.startSession(atSourceTime: .zero)

        let frames = renderer.script.frameCount
        for frame in 0..<frames {
            if Task.isCancelled {
                writer.cancelWriting()
                throw ExportError.cancelled
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw ExportError.buffer }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ExportError.buffer }

            let time = Double(frame) / Double(FlyoverScript.fps)
            let wantsPreview = frame % 12 == 0
            let preview = autoreleasepool { draw(renderer, time: time, into: buffer, snapshot: wantsPreview) }

            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame),
                                                                       timescale: CMTimeScale(FlyoverScript.fps))) else {
                throw ExportError.writer
            }
            if wantsPreview || frame == frames - 1 {
                await progress(Double(frame + 1) / Double(frames), preview)
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ExportError.writer }
    }

    /// Рисует кадр прямо в буфер видео. Возвращает уменьшенное превью, если просили.
    private static func draw(_ renderer: FlyoverRenderer, time: Double, into buffer: CVPixelBuffer,
                             snapshot: Bool) -> UIImage? {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let size = FlyoverRenderer.size
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Переводим в координаты UIKit: начало слева сверху.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        renderer.draw(time: time, in: context)
        UIGraphicsPopContext()

        guard snapshot, let image = context.makeImage() else { return nil }
        return UIImage(cgImage: image)
    }
}
