import SwiftUI

/// Slim banner shown in Photo Mode when the folder of the opened file cannot be browsed
/// because of the App Sandbox.
struct FolderAccessBanner: View {
    let ui: ViewerUIState
    let session: BrowsingSession
    let state: WindowState
    weak var controller: MainWindowController?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark").foregroundStyle(.secondary)
            Text("Allow access to this folder to browse its images", tableName: "Viewer").lineLimit(1)
            Spacer(minLength: 8)
            Button(String(localized: "Allow…", table: "Viewer")) { controller?.grantFolderAccess(nil) }
                .controlSize(.small)
            Button { ui.bannerDismissed = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Dismiss", tableName: "Viewer"))
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }
}
