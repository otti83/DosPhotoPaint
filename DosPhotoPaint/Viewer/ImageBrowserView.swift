import SwiftUI
import AppKit

/// Photo Mode image browser shown over the canvas: the images of the current folder (and,
/// optionally, its subfolders) as tiles or as a list. Double-click (or Return) opens an image.
struct ImageBrowserView: View {
    let model: ImageBrowserModel
    let session: BrowsingSession
    @Bindable var settings: AppSettings
    weak var controller: MainWindowController?
    @State private var selection: Set<URL> = []

    private func t(_ key: String.LocalizationValue) -> String { String(localized: key, table: "Viewer") }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { controller?.hideImageBrowser() }
        .onAppear { selection = session.currentURL.map { [$0] } ?? [] }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Picker(t("View"), selection: $settings.photoBrowserStyle) {
                Label(t("Tiles"), systemImage: "square.grid.2x2").tag(ImageBrowserStyle.tiles)
                Label(t("List"), systemImage: "list.bullet").tag(ImageBrowserStyle.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(t("Tiles / List"))
            if !session.isExplicit {
                Toggle(t("Include Subfolders"), isOn: $settings.photoBrowserIncludeSubfolders)
                    .toggleStyle(.checkbox)
            }
            if model.isLoading { ProgressView().controlSize(.small) }
            Spacer()
            Text(countText).foregroundStyle(.secondary).monospacedDigit()
            Button { controller?.hideImageBrowser() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .help(t("Close (Esc)"))
                .accessibilityLabel(t("Close"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var countText: String {
        let n = model.items.count
        return model.isTruncated ? String(localized: "\(n)+ images", table: "Viewer") : String(localized: "\(n) images", table: "Viewer")
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.accessDenied {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("Allow access to this folder to browse its images", tableName: "Viewer")
                Button(t("Allow…")) { controller?.grantFolderAccess(nil) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            Group {
                if model.isLoading { ProgressView() } else { Text("No images", tableName: "Viewer").foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if settings.photoBrowserStyle == .tiles {
            tiles
        } else {
            list
        }
    }

    /// Thumbnail edge set with the status bar slider.
    private var tileSide: CGFloat { CGFloat(settings.photoBrowserThumbnailSize) }
    private var rowSide: CGFloat { max(16, tileSide / 4) }

    private var showsFolders: Bool { session.isExplicit || settings.photoBrowserIncludeSubfolders }

    private var tiles: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSide + 12, maximum: tileSide * 1.5 + 12), spacing: 12)], spacing: 14) {
                    ForEach(model.items) { item in
                        BrowserTile(item: item, side: tileSide, showsFolder: showsFolders,
                                    isCurrent: item.url == session.currentURL, isSelected: selection.contains(item.url))
                            .id(item.url)
                            .onTapGesture(count: 2) { controller?.openFromBrowser(item.url) }
                            .onTapGesture { selection = [item.url] }
                    }
                }
                .padding(12)
            }
            .onAppear { scrollToCurrent(proxy) }
            .onChange(of: model.items.count) { scrollToCurrent(proxy) }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard let current = session.currentURL, model.items.contains(where: { $0.url == current }) else { return }
        proxy.scrollTo(current, anchor: .center)
    }

    private var list: some View {
        Table(model.items, selection: $selection) {
            TableColumn(t("Name")) { item in
                HStack(spacing: 8) {
                    BrowserThumbnail(url: item.url, side: rowSide)
                    Text(item.name).lineLimit(1)
                        .fontWeight(item.url == session.currentURL ? .semibold : .regular)
                }
            }
            .width(min: 180, ideal: 320)
            TableColumn(t("Folder")) { item in
                Text(item.folder).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: showsFolders ? 160 : 80)
            TableColumn(t("Date Modified")) { item in
                if let date = item.modified { Text(date, format: .dateTime.year().month().day().hour().minute()) }
            }
            .width(min: 120, ideal: 150)
            TableColumn(t("Size")) { item in
                if let size = item.fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).monospacedDigit()
                }
            }
            .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: URL.self) { _ in
            EmptyView()
        } primaryAction: { urls in
            if let url = urls.first { controller?.openFromBrowser(url) }
        }
    }
}

/// One tile: thumbnail and file name.
struct BrowserTile: View {
    let item: BrowserItem
    let side: CGFloat
    let showsFolder: Bool
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            BrowserThumbnail(url: item.url, side: side)
                .frame(height: side)
            Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
            if showsFolder, !item.folder.isEmpty {
                Text(item.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .help(item.folder.isEmpty ? item.name : "\(item.folder)/\(item.name)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Asynchronously loaded thumbnail (aspect ratio kept).
struct BrowserThumbnail: View {
    let url: URL
    let side: CGFloat
    @State private var image: CGImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
        }
        .frame(width: side, height: side)
        .task(id: url) {
            if let hit = BrowserThumbnails.shared.cached(url) { image = hit; return }
            // One decode size for all slider positions (the largest tile), so resizing never re-decodes.
            image = await BrowserThumbnails.shared.thumbnail(for: url, maxPixelSize: Int(320 * max(scale, 1)))
        }
    }
}
