import SwiftUI

// MARK: - Fejlesztői mód képernyő
// Feloldás: Beállítások alján a "Summit • Gábor Csaba" sor 10x tap.
// Minden tesztelőeszköz itt él (nem demo-felhasználóhoz kötve):
// idő-eltolás csúszka, értesítés-tesztek, Live Activity teszt.
// Háttér: DevPeak fotó, Beállítások-stílusú liquid glass szigetekkel.
struct DeveloperView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    @AppStorage("developer.enabled") private var devEnabled = true
    @AppStorage("home.demoPreviewActive") private var isPreviewActive = false
    @AppStorage("home.demoPreviewMinutes") private var previewMinutes: Double = 540
    @ObservedObject private var liveManager = SummitLiveActivityManager.shared
    @State private var notifStatus = NotificationManager.shared.permissionStatus
    @State private var simMessage: String?
    @State private var showSimAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                island(header: "Fejlesztői mód") {
                    row {
                        Toggle(isOn: $devEnabled) {
                            Label("Fejlesztői mód", systemImage: "hammer.fill")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(colors.accent)
                    }
                } footer: {
                    "Kikapcsolva a Fejlesztő menü és minden tesztelőeszköz eltűnik."
                }

                island(header: "Idő-eltolás") {
                    row {
                        Toggle(isOn: $isPreviewActive) {
                            Label("Idő előnézet", systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(colors.accent)
                    }
                    if isPreviewActive {
                        settingsDivider
                        row {
                            VStack(spacing: 8) {
                                Slider(value: $previewMinutes, in: 420...960, step: 5)
                                    .tint(colors.accent)
                                HStack {
                                    Text("07:00").font(.caption2).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(previewTimeText).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(colors.accent)
                                    Spacer()
                                    Text("16:00").font(.caption2).foregroundStyle(.tertiary)
                                }
                                Button("Vissza élő időre") { withAnimation { isPreviewActive = false } }
                                    .font(.caption.weight(.semibold)).tint(colors.accent)
                                Label("A csúszka a Főoldalt, az Órarendet és a Live Activity-t is mozgatja", systemImage: "livephoto")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } footer: {
                    "A Főoldal és az Órarend az eltolt idő szerint rajzol — valós és demo fiókkal is."
                }

                island(header: "Értesítések") {
                    row {
                        HStack {
                            Text("Rendszerengedély").font(.subheadline)
                            Spacer()
                            Text(notifStatus).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Button("Kérés") { Task {
                                await NotificationManager.shared.requestPermission()
                                notifStatus = NotificationManager.shared.permissionStatus
                            } }
                            .font(.caption.weight(.semibold)).tint(colors.accent)
                        }
                    }
                    settingsDivider
                    row {
                        Button("Teszt értesítés küldése") { Task {
                            await NotificationManager.shared.sendTest(userId: session.selectedUser?.id ?? "dev")
                            notifStatus = NotificationManager.shared.permissionStatus
                        } }
                        .tint(colors.accent)
                    }
                    settingsDivider
                    row {
                        Button("Új jegy szimulálása (5-ös Matek + kártya)") { Task {
                            _ = await NotificationManager.shared.simulateDemoGrade()
                            // A fullscreen ünneplő kártya magától felpattan — ez a tesztje.
                        } }
                        .tint(colors.accent)
                    }
                    settingsDivider
                    row {
                        Button("Értesítési előzmény törlése (újrateszteléshez)") {
                            NotificationManager.shared.resetDemoSeen()
                            simMessage = "Előzmény törölve — a következő frissítés csendben magot vet."
                            showSimAlert = true
                        }
                        .tint(.red)
                    }
                }

                island(header: "Live Activity") {
                    row {
                        HStack(spacing: 6) {
                            Circle().fill(liveManager.isSystemEnabled ? Color.green : Color.red).frame(width: 7, height: 7)
                            Text(liveManager.isSystemEnabled ? "Rendszer OK" : "Rendszer tiltva")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(liveManager.isSystemEnabled ? Color.secondary : Color.red)
                            Spacer()
                            Text("\(liveManager.activeCount) aktív • \(liveManager.lastAction)")
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    if let err = liveManager.lastError {
                        settingsDivider
                        row { Text(err).font(.caption2).foregroundStyle(.orange).lineLimit(2) }
                    }
                    settingsDivider
                    row {
                        HStack(spacing: 12) {
                            Button("Teszt indítása most") {
                                Task { await liveManager.startDemoTestNow(accentHex: theme.accentHex) }
                            }
                            .font(.caption.weight(.semibold)).tint(colors.accent)
                            Button("Leállítás") {
                                Task { await liveManager.endAll(dismissalPolicy: .immediate) }
                            }
                            .font(.caption.weight(.semibold)).tint(.red)
                        }
                    }
                    settingsDivider
                    row {
                        // Widget extension telepítve? Enélkül a pill felmegy, de az expanded fekete.
                        if isWidgetExtensionInstalled {
                            Label("Widget extension telepítve", systemImage: "checkmark.circle.fill")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Label("Widget extension HIÁNYZIK — töröld az appot és telepítsd újra Xcode-ból, ez okozza a fekete Islandet", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.red)
                        }
                    }
                } footer: {
                    "Órarend-független teszt — este is működik."
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 800, mac: 920) : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background { SummitBackdrop(imageName: "DevPeak") }
        .scrollContentBackground(.hidden)
        .navigationTitle("Fejlesztő")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Fejlesztői eszközök", isPresented: $showSimAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(simMessage ?? "")
        }
        .task {
            // Első indításkor a csúszka a mostani időre álljon (ne fix 09:00-ra).
            if UserDefaults.standard.object(forKey: "home.demoPreviewMinutes") == nil {
                let c = Calendar.current
                let h = c.component(.hour, from: Date())
                let m = c.component(.minute, from: Date())
                previewMinutes = Double(max(420, min(960, h * 60 + m)))
            }
        }
    }

    private var previewTimeText: String { previewDate.formatted(date: .omitted, time: .shortened) }
    private var previewDate: Date {
        let base = Calendar.current.startOfDay(for: Date())
        return base.addingTimeInterval(previewMinutes * 60)
    }

    /// A widget appex tényleg az app része? Régi telepítésnél hiányozhat → fekete expanded Island.
    private var isWidgetExtensionInstalled: Bool {
        let url = Bundle.main.bundleURL.appendingPathComponent("PlugIns/SummitWidgets.appex", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Beállítások-stílusú glass szigetek (helyi másolat, DevPeak-háttérhez)
    private func island<Content: View>(header: String? = nil, @ViewBuilder content: () -> Content, footer: () -> String? = { nil }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .summitGlassRow(cornerRadius: 20)
            if let footer = footer() {
                Text(footer).font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsDivider: some View {
        Divider().padding(.leading, 16)
    }
}
