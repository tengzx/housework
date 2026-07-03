import SwiftUI
import ImageIO
import UIKit

// MARK: - Shared cache

enum FitnessMediaCache {
    /// Enlarge the shared URL cache once so exercise thumbnails / GIFs persist to
    /// disk across launches instead of being re-fetched every time.
    static let configure: Void = {
        let cache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,   // 16 MB
            diskCapacity: 200 * 1024 * 1024,     // 200 MB
            diskPath: "fitness_media"
        )
        URLCache.shared = cache
    }()
}

// MARK: - Thumbnail (static image with placeholder)

struct ExerciseThumbnail: View {
    let urlString: String?
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 12

    init(urlString: String?, size: CGFloat = 48, cornerRadius: CGFloat = 12) {
        _ = FitnessMediaCache.configure
        self.urlString = urlString
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(hex: "F2F2F5"))
            .frame(width: size, height: size)
            .overlay {
                if let url = validURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .empty:
                            ProgressView().scaleEffect(0.6)
                        case .failure(let error):
                            BarbellIcon()
                                .onAppear {
                                    #if DEBUG
                                    print("🖼️ thumbnail failed: \(url.absoluteString) — \(error.localizedDescription)")
                                    #endif
                                }
                        @unknown default:
                            BarbellIcon()
                        }
                    }
                } else {
                    BarbellIcon()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var validURL: URL? {
        FitnessAPIClient.mediaURL(urlString)
    }
}

// MARK: - Animated GIF view

/// Plays an animated GIF from a remote URL. Falls back to a placeholder while
/// loading or on failure. Uses ImageIO to decode frames — no third-party deps.
struct AnimatedGIFView: View {
    let urlString: String
    @State private var image: UIImage?
    @State private var failed = false

    init(urlString: String) {
        _ = FitnessMediaCache.configure
        self.urlString = urlString
    }

    var body: some View {
        Group {
            if let image {
                GIFPlayer(image: image)
            } else if failed {
                BarbellIcon()
            } else {
                ProgressView()
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        guard let url = FitnessAPIClient.mediaURL(urlString) else {
            failed = true
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                #if DEBUG
                print("🎞️ gif http \(http.statusCode): \(url.absoluteString)")
                #endif
                failed = true
                return
            }
            if let animated = UIImage.animatedImage(fromGIF: data) {
                image = animated
            } else if let still = UIImage(data: data) {
                image = still
            } else {
                #if DEBUG
                print("🎞️ gif decode failed (\(data.count) bytes): \(url.absoluteString)")
                #endif
                failed = true
            }
        } catch {
            #if DEBUG
            print("🎞️ gif load error: \(url.absoluteString) — \(error.localizedDescription)")
            #endif
            failed = true
        }
    }
}

private struct GIFPlayer: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.image = image
        // Don't let the (possibly large) image drive SwiftUI layout — the parent
        // frame decides the size; the image just fits inside it.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = image
    }

    // Respect the size proposed by the SwiftUI parent frame instead of the
    // image's intrinsic size, so the view can't overflow into other content.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

// MARK: - GIF decoding

extension UIImage {
    /// Builds an animated UIImage from GIF data, honoring per-frame durations.
    static func animatedImage(fromGIF data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        var frames: [UIImage] = []
        var totalDuration: Double = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            totalDuration += frameDuration(source: source, index: i)
        }

        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: totalDuration)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        let defaultDuration = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return defaultDuration
        }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let duration = unclamped ?? clamped ?? defaultDuration
        // Browsers clamp very small delays to ~0.1s.
        return duration < 0.011 ? defaultDuration : duration
    }
}
