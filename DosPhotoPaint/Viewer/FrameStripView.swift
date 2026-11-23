import SwiftUI
import AppKit
import ImageIO

/// Frame strip under an animated image (Photo Mode): play/pause, frame number and a scrolling
/// row of frame thumbnails. Clicking a frame pauses on it.
struct FrameStripView: View {
    let player: AnimationPlayer
    weak var controller: MainWindowController?

    static let height: CGFloat = 78

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Button { player.step(by: -1) } label: { Image(systemName: "backward.frame.fill") }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Previous Frame", table: "Viewer"))
                Button { player.togglePause() } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill").frame(width: 16)
                }
                .buttonStyle(.borderless)
                .help(player.isPaused ? String(localized: "Play", table: "Viewer") : String(localized: "Pause", table: "Viewer"))
                Button { player.step(by: 1) } label: { Image(systemName: "forward.frame.fill") }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Next Frame", table: "Viewer"))
                Text(verbatim: "\(player.currentFrame + 1) / \(player.frameCount)")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .leading)
                frames
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
        }
        .frame(height: Self.height)
        .background(.bar)
    }

    private var frames: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(0..<player.frameCount, id: \.self) { i in
                        FrameThumbnail(url: player.playingURL, index: i, isCurrent: i == player.currentFrame)
                            .id(i)
                            .onTapGesture {
                                player.show(frame: i)
                                controller?.returnFocusToCanvas()
                            }
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: player.currentFrame) { _, i in proxy.scrollTo(i, anchor: .center) }
        }
    }
}

private struct FrameThumbnail: View {
    let url: URL?
    let index: Int
    let isCurrent: Bool
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: 52, height: 52)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2))
        .overlay(alignment: .bottomTrailing) {
            Text(verbatim: "\(index + 1)").font(.system(size: 9)).monospacedDigit()
                .padding(.horizontal, 2).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2))
        }
        .contentShape(Rectangle())
        .task(id: url) {
            guard let url else { return }
            image = await FrameThumbnails.shared.thumbnail(url: url, index: index)
        }
    }
}

/// Decoded frame thumbnails, cached by file and frame.
final class FrameThumbnails {
    static let shared = FrameThumbnails()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.countLimit = 2000 }

    func thumbnail(url: URL, index: Int) async -> CGImage? {
        let key = "\(url.path)#\(index)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let src = try? ImageLoader.makeSource(url) else { return nil }
            return AnimationPlayer.decode(src, index, maxPixelSize: 104)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
