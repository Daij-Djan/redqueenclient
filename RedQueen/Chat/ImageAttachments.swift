import SwiftUI
import Observation
import ImageIO
import UniformTypeIdentifiers
import MatrixRustSDK

/// ImageIO-based processing (no UIKit, works on macOS too): EXIF-aware
/// downscale and JPEG re-encode for upload, plus small preview thumbnails.
enum ImageProcessor {
    struct Processed: Hashable {
        let fileURL: URL
        let width: UInt64
        let height: UInt64
        let size: UInt64
        /// The pinned SDK version requires a blurhash on image sends.
        let blurhash: String
    }

    enum ProcessingError: Error { case undecodable }

    /// Downscales to `maxDimension` on the long edge and re-encodes as JPEG.
    static func processForUpload(data: Data, maxDimension: CGFloat = 2048) throws -> Processed {
        guard let cgImage = cgImage(from: data, maxDimension: maxDimension) else {
            throw ProcessingError.undecodable
        }
        let url = FileManager.default.temporaryDirectory
            .appending(component: "image-\(UUID().uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.jpeg.identifier as CFString,
                                                                1, nil) else {
            throw ProcessingError.undecodable
        }
        CGImageDestinationAddImage(destination, cgImage,
                                   [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ProcessingError.undecodable
        }
        let size = (try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false))[.size] as? UInt64) ?? 0

        // Blurhash from a tiny copy — the algorithm is O(pixels × components).
        let blurhash = self.cgImage(from: data, maxDimension: 32)
            .flatMap { BlurHash.encode(image: $0) }
            ?? "L00000fQfQfQfQfQfQfQfQfQfQfQ"

        return Processed(fileURL: url,
                         width: UInt64(cgImage.width),
                         height: UInt64(cgImage.height),
                         size: size,
                         blurhash: blurhash)
    }

    /// Decodes (and EXIF-rotates) image data, capped to `maxDimension`.
    static func cgImage(from data: Data, maxDimension: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func previewImage(fileURL: URL, maxDimension: CGFloat = 240) -> Image? {
        guard let data = try? Data(contentsOf: fileURL),
              let cgImage = cgImage(from: data, maxDimension: maxDimension) else { return nil }
        return Image(cgImage, scale: 1, orientation: .up, label: Text("Image attachment"))
    }
}

/// An image staged in the composer, ready to send.
struct PendingImage: Identifiable {
    let id = UUID()
    let processed: ImageProcessor.Processed
    let preview: Image?
}

/// Horizontal strip of staged images with per-image remove buttons; shared
/// by the chat composer and the home screen.
struct PendingImageStrip: View {
    @Binding var images: [PendingImage]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { pending in
                    ZStack(alignment: .topTrailing) {
                        (pending.preview ?? Image(systemName: "photo"))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(.rect(cornerRadius: 10))
                        Button {
                            images.removeAll { $0.id == pending.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .offset(x: 5, y: -5)
                        .accessibilityLabel("Remove image")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }
}

/// Downloads media for image bubbles, with a per-message in-memory cache.
@MainActor @Observable
final class ImageLoaderService {
    var client: Client?

    private(set) var thumbnails: [String: Image] = [:]
    private var inflight: Set<String> = []

    func loadThumbnail(messageID: String, attachment: ImageAttachment) {
        guard thumbnails[messageID] == nil, !inflight.contains(messageID), let client else { return }
        inflight.insert(messageID)
        Task {
            defer { inflight.remove(messageID) }
            var data = try? await client.getMediaThumbnail(mediaSource: attachment.source,
                                                           width: 800, height: 800)
            if data == nil {
                data = try? await fullData(client: client, attachment: attachment)
            }
            guard let data,
                  let cgImage = ImageProcessor.cgImage(from: data, maxDimension: 800) else { return }
            thumbnails[messageID] = Image(cgImage, scale: 1, orientation: .up, label: Text("Image"))
        }
    }

    /// Full-resolution image for the viewer.
    func loadFull(attachment: ImageAttachment) async -> Image? {
        guard let client,
              let data = try? await fullData(client: client, attachment: attachment),
              let cgImage = ImageProcessor.cgImage(from: data, maxDimension: 4096) else { return nil }
        return Image(cgImage, scale: 1, orientation: .up, label: Text("Image"))
    }

    private func fullData(client: Client, attachment: ImageAttachment) async throws -> Data {
        let handle = try await client.getMediaFile(mediaSource: attachment.source,
                                                   filename: attachment.filename,
                                                   mimeType: attachment.mimetype ?? "image/jpeg",
                                                   useCache: true,
                                                   tempDir: nil)
        return try Data(contentsOf: URL(filePath: handle.path()))
    }
}
