import QuickLook
import SwiftUI

// MARK: - Csatolmány-letöltés + QuickLook-megnyitás (PDF, kép, dokumentum)
//
// Használat: házi / dolgozat / üzenet expanded-sorában egy AttachmentRow,
// ami koppintásra letölti (KRÉTA) vagy helyben generálja (demo) a fájlt,
// és QuickLook-ban nyitja meg. Hibát nem nyel el: sikertelen letöltéskor
// a sor alatt megjelenik az ok.

@MainActor
final class AttachmentStore: ObservableObject {
    @Published var previewURL: URL?
    @Published var loadingId: String?
    @Published var errorText: String?

    /// Letöltés + megnyitás. `ownerId`: házi-uid (a KRÉTA útvonalhoz kellhet).
    func open(_ att: AttachmentItem, ownerId: String? = nil, kreta: KretaClient) async {
        if loadingId != nil { return }
        loadingId = att.id
        errorText = nil
        defer { loadingId = nil }
        guard let res = await kreta.downloadAttachment(att, ownerId: ownerId) else {
            errorText = "Nem sikerült letölteni: \(att.name)"
            return
        }
        let safe = res.fileName.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(att.id)-\(safe)")
        do {
            try res.data.write(to: url, options: .atomic)
            previewURL = url
        } catch {
            errorText = "Mentési hiba: \(error.localizedDescription)"
        }
    }
}

struct AttachmentRow: View {
    let att: AttachmentItem
    var ownerId: String? = nil
    @ObservedObject var store: AttachmentStore
    @EnvironmentObject var kreta: KretaClient
    @Environment(\.colorScheme) var scheme

    var body: some View {
        Button {
            Task { await store.open(att, ownerId: ownerId, kreta: kreta) }
        } label: {
            HStack(spacing: 8) {
                if store.loadingId == att.id {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: att.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                Text(att.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let s = att.sizeText {
                    Text(s).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Csatolmány-blokk expanded-sorokba (házi / dolgozat): a sorok maguk csak
/// beágyazzák, a store + QuickLook-sheet helyben él.
struct AttachmentsBlock: View {
    let attachments: [AttachmentItem]
    var ownerId: String? = nil
    @StateObject private var store = AttachmentStore()
    @State private var showPreview = false

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(attachments.count == 1 ? "Csatolmány" : "\(attachments.count) csatolmány")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                ForEach(attachments) { att in
                    AttachmentRow(att: att, ownerId: ownerId, store: store)
                }
                if let err = store.errorText {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .sheet(isPresented: $showPreview) {
                if let url = store.previewURL {
                    QuickLookPreview(url: url)
                        .ignoresSafeArea()
                }
            }
            .onChange(of: store.previewURL) { _, new in
                showPreview = new != nil
            }
        }
    }
}
/// QuickLook-előnézet egyetlen helyi fájlra (+ rendszer-Megosztás gomb).
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        return UINavigationController(rootViewController: ql)
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coord { Coord(url: url) }

    final class Coord: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
