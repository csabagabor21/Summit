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

    /// A QuickLook-lap kötése. Csukáskor a `previewURL` is nil lesz — így
    /// ugyanarra a csatolmányra újra koppintva a lap ismét felnyílik (a
    /// korábbi `onChange(of: previewURL)`-es kötés azonos URL-nél nem
    /// váltott, a második koppintás némán letöltött, de nem nyitott semmit).
    var isPreviewing: Bool {
        get { previewURL != nil }
        set { if !newValue { previewURL = nil } }
    }

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
    private var cp: Bool { CyberpunkTheme.isActive }

    /// Fájltípus-kód a kiterjesztésből (`PDF`, `IMG`, `DOC`…) a Cyberpunk-sorhoz.
    static func cpTypeCode(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "": return "FILE"
        case "png", "jpg", "jpeg", "heic", "gif", "webp": return "IMG"
        case "doc", "docx", "odt", "rtf": return "DOC"
        case "xls", "xlsx", "ods", "csv": return "XLS"
        case "ppt", "pptx", "odp": return "PPT"
        default: return String(ext.prefix(4)).uppercased()
        }
    }

    var body: some View {
        if MinecraftTheme.isActive {
            // Kő-gomb a kapszula helyett (a felirat fehér, árnyékkal).
            Button {
                Task { await store.open(att, ownerId: ownerId, kreta: kreta) }
            } label: {
                HStack(spacing: 8) {
                    if store.loadingId == att.id {
                        SkinProgress(color: .white).frame(width: 20)
                    } else {
                        SkinIcon(att.symbol, size: 20)
                    }
                    Text(att.name).lineLimit(1)
                    if let s = att.sizeText {
                        Text(s).skinFont(.caption2).monospacedDigit().opacity(0.7)
                    }
                    Spacer(minLength: 4)
                    McGlyph(kind: .chevronRight, size: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(McButtonStyle(compact: true))
        } else {
            Button {
                Task { await store.open(att, ownerId: ownerId, kreta: kreta) }
            } label: {
                HStack(spacing: 8) {
                    if store.loadingId == att.id {
                        SkinProgress().scaleEffect(0.8)
                    } else {
                        SkinIcon(att.symbol)
                            .skinFont(.caption, weight: .semibold)
                            .foregroundStyle(cp ? AnyShapeStyle(CyberpunkTheme.cyan) : AnyShapeStyle(.secondary))
                            .frame(width: 20)
                    }
                    Text(att.name)
                        .skinFont(.caption, weight: .medium)
                        .foregroundStyle(cp ? AnyShapeStyle(CyberpunkTheme.text) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if cp {
                        CPLabel(Self.cpTypeCode(att.name), color: CyberpunkTheme.cyan)
                    }
                    if let s = att.sizeText {
                        Text(s).cpgSizeFont().foregroundStyle(.tertiary).monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    SkinIcon("chevron.right")
                        .skinFont(.caption2, weight: .semibold)
                        .foregroundStyle(cp ? AnyShapeStyle(CyberpunkTheme.cyan) : AnyShapeStyle(.tertiary))
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background {
                    if cp {
                        // Cyberpunk: levágott sarkú adat-csík, 1 px-es cián kerettel.
                        CPChamferShape(cut: 8, corners: [.topLeft, .bottomRight])
                            .fill(CyberpunkTheme.cyan.opacity(0.06))
                            .overlay(CPChamferShape(cut: 8, corners: [.topLeft, .bottomRight])
                                .strokeBorder(CyberpunkTheme.cyan.opacity(0.55), lineWidth: 1))
                    } else {
                        Capsule()
                            .fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
            }
            .buttonStyle(.skinPlain)
        }
    }
}

private extension View {
    /// Méret-felirat: Cyberpunkban egyenközű HUD-betű, máshol a korábbi
    /// `skinFont(.caption2)`.
    @ViewBuilder
    func cpgSizeFont() -> some View {
        if CyberpunkTheme.isActive {
            self.font(CyberpunkTheme.mono(size: 10, relativeTo: .caption2))
        } else {
            self.skinFont(.caption2)
        }
    }
}

/// Csatolmány-blokk expanded-sorokba (házi / dolgozat): a sorok maguk csak
/// beágyazzák, a store + QuickLook-sheet helyben él.
struct AttachmentsBlock: View {
    let attachments: [AttachmentItem]
    var ownerId: String? = nil
    @StateObject private var store = AttachmentStore()

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(attachments.count == 1 ? "Csatolmány" : "\(attachments.count) csatolmány")
                    .mcSectionHeader()
                ForEach(attachments) { att in
                    AttachmentRow(att: att, ownerId: ownerId, store: store)
                }
                if let err = store.errorText {
                    SkinLabel(err, systemImage: "exclamationmark.triangle.fill")
                        .skinFont(.caption).foregroundStyle(CyberpunkTheme.isActive ? CyberpunkTheme.red : Color.orange)
                }
            }
            .sheet(isPresented: $store.isPreviewing) {
                if let url = store.previewURL {
                    QuickLookPreview(url: url)
                        .ignoresSafeArea()
                }
            }
        }
    }
}
/// QuickLook-előnézet egyetlen helyi fájlra (+ rendszer-Megosztás gomb
/// és X a csukáshoz — enélkül csak bizonytalan lehúzással lehet kilépni).
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        ql.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coord.doneTapped))
        ql.navigationItem.leftBarButtonItem?.accessibilityLabel = "Bezárás"
        return UINavigationController(rootViewController: ql)
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coord {
        let c = Coord(url: url)
        c.onDone = { dismiss() }
        return c
    }

    final class Coord: NSObject, QLPreviewControllerDataSource {
        let url: URL
        var onDone: () -> Void = {}
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
        @objc func doneTapped() { onDone() }
    }
}
