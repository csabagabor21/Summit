import QuartzCore
import SwiftUI
import UIKit

// MARK: - Új jegy ünneplő kártya (fullscreen)
// - Középen nagyban: liquid glass kör a jeggyel (mint a Jegyek tabon)
// - Alatta nagyban a VALÓS százalék, de csak ha a tanár beleírta a jegy
//   szövegébe (pl. "85%") — a jegyértékből szorzott kamuszám (4-es → 80%)
//   helyett ilyenkor nincs %sor.
// - Alatta balra zárva: tantárgy, mire kapta (téma), típus • tanár • dátum • súly
struct GradeCelebrationView: View {
    let grade: GradeItem
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @State private var appeared = false
    @State private var pulse = false
    @State private var shownPct = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Cyberpunk „breach"-felfedés állapota (a többi skin nem olvassa):
    // 0 = sötét, 1 = fejléc-csík, 2 = panel nyitva (dekódol), 3 = kész.
    @State private var cpPhase = 0
    /// Dekódolás közben villogó álszámjegy; nil = a valódi jegy látszik.
    @State private var cpDigit: Int? = nil
    /// A jegy „lezárt" (dekódolás vége) — ez indítja az egyszeri glitchet.
    @State private var cpLocked = false
    /// Koppintással átugorva: a százalék rögtön a végértéken áll.
    @State private var cpSkipped = false
    private let switchToGrades = Notification.Name("summit.switchToGrades")

    var colors: AppColors { theme.colors(for: scheme) }
    private var gradeColor: Color { colors.gradeColor(for: grade.value) }
    private var percent: Int? {
        GradePercent.parse(valueText: grade.valueText, topic: grade.plainTopic, type: grade.type)
    }
    private var topicLine: String { grade.plainTopic.isEmpty ? grade.type : grade.plainTopic }
    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "yyyy. MMM d."
        return f.string(from: grade.date)
    }

    var body: some View {
        Group {
            if theme.isCyberpunk {
                cpContent
            } else if theme.isMinecraft {
                mcContent
            } else {
                summitContent
            }
        }
        .onAppear {
            // Új jegy = ünnepelt kimenet: egyetlen success a konfettival együtt.
            SummitHaptics.success()
            withAnimation(SummitMotion.gentle) { appeared = true }
            if theme.isMinecraft {
                // Minecraft: a 5-ös „Kihívás teljesítve", a többi level-up hang
                // (egyszer; a kihívás-fanfár hosszú, ezért zárásnál leállítjuk).
                McSound.play(grade.value == 5 ? .challengeComplete : .levelUp)
            } else if theme.isCyberpunk {
                // Cyberpunk: a hangok a breach-szekvenciából szólnak (cpRunBreach).
            } else {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
        .onDisappear {
            McSound.stop(.challengeComplete)
            McSound.stop(.levelUp)
        }
        .task {
            // Cyberpunk breach-felfedés (más skinben azonnal kilép).
            guard theme.isCyberpunk else { return }
            await cpRunBreach()
        }
        .task {
            // Százalék felpörgetése 0-ról a célra (ha nincs valós %, nincs animáció sem)
            guard let target = percent else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            let steps = 24
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: 1_300_000_000 / UInt64(steps))
                if Task.isCancelled { return }
                shownPct = target * i / steps
            }
        }
    }

    // MARK: Summit (Liquid Glass) ág — változatlan

    private var summitContent: some View {
        ZStack {
            // Ünnepi háttér: jegy-szín fény felül, alatta az app-háttér
            LinearGradient(
                colors: [gradeColor.opacity(scheme == .dark ? 0.38 : 0.28), colors.background],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            ConfettiView(tint: gradeColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        NotificationManager.shared.celebrationGrade = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.skinPlain)
                    .accessibilityLabel("Bezárás")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Text("ÚJ JEGY")
                    .font(.caption.weight(.bold))
                    .tracking(3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Text(dateText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)

                Spacer(minLength: 12)

                // Hős: liquid glass szám nagyban (Jegyek tab stílus)
                ZStack {
                    Circle()
                        .fill(gradeColor.opacity(0.25))
                        .blur(radius: 34)
                        .frame(width: 190, height: 190)
                        .scaleEffect(pulse ? 1.08 : 1.0)
                        .opacity(pulse ? 1 : 0.8)
                    ZStack {
                        Circle().fill(Color.clear)
                            .glassEffect(.clear, in: .circle)
                            .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1.6))
                            .frame(width: 168, height: 168)
                        Text("\(grade.value)")
                            .mcDisplay(76)
                            .foregroundStyle(gradeColor)
                            .monospacedDigit()
                    }
                    .shadow(color: gradeColor.opacity(0.35), radius: 24, y: 8)
                }
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)

                // Valós százalék nagyban a szám alatt — 0-ról pörög fel.
                // Ha a jegyhez nincs beírva % (a gyakori eset), nincs sor.
                if percent != nil {
                    Text("\(shownPct)%")
                        .mcDisplay(52)
                        .foregroundStyle(gradeColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .padding(.top, 10)
                        .opacity(appeared ? 1 : 0)
                }

                Spacer(minLength: 16)

                // Balra zárt infóblokk: tantárgy + mire kapta
                VStack(alignment: .leading, spacing: 6) {
                    Text(grade.subject)
                        .mcDisplay(26)
                        .foregroundStyle(.primary)
                    Text(topicLine)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(friendlyGradeType(grade.type)) • \(grade.teacher)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .opacity(appeared ? 1 : 0)
                .animation(SummitMotion.entrance(delay: 0.15), value: appeared)

                Spacer(minLength: 20)

                VStack(spacing: 10) {
                    Button {
                        NotificationManager.shared.celebrationGrade = nil
                        NotificationCenter.default.post(name: switchToGrades, object: nil)
                    } label: {
                        Text("Megnézem a jegyeim")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(colors.accent))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.skinPlain)
                    Button("Szuper!") {
                        NotificationManager.shared.celebrationGrade = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(colors.accent)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
                .opacity(appeared ? 1 : 0)
                .animation(SummitMotion.entrance(delay: 0.3), value: appeared)
            }
        }
    }

    // MARK: Minecraft ág — „Előrelépés elérve!" / „Kihívás teljesítve!"

    /// A jegyhez tartozó item (toast-ikon): 5 = nether-csillag, 4 = gyémánt,
    /// 3 = smaragd, 2 = aranyrúd, 1 = szén.
    private var mcItem: String {
        switch grade.value {
        case 5: return "mc_item_nether_star"
        case 4: return "mc_item_diamond"
        case 3: return "mc_item_emerald"
        case 2: return "mc_item_gold_ingot"
        default: return "mc_item_coal"
        }
    }

    /// A játék szöveg-árnyéka: a szín negyed fényereje (fehér → #3F3F3F).
    private func mcShadow(_ hex: UInt) -> Color {
        Color(hex: ((hex >> 16 & 0xFF) / 4) << 16 | ((hex >> 8 & 0xFF) / 4) << 8 | (hex & 0xFF) / 4)
    }

    private var mcContent: some View {
        let px = MinecraftTheme.px
        // A %-sor és az XP-sáv ugyanazt a számot követi (pörgő százalék);
        // % nélkül a jegy az 5-ös skálán töltött sáv.
        let xp = percent != nil ? Double(shownPct) / 100 : Double(grade.value) / 5
        return ZStack {
            McMenuBackground()
            // A játék menü-sötétítése a háttér fölött.
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        NotificationManager.shared.celebrationGrade = nil
                    } label: {
                        SkinIcon("xmark", size: 24)
                    }
                    .buttonStyle(McButtonStyle(compact: true))
                    .accessibilityLabel("Bezárás")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // A toast jobbról csúszik be, lineárisan (nincs rugó).
                McAdvancementToast(icon: mcItem,
                                   title: grade.value == 5 ? "Kihívás teljesítve!" : "Előrelépés elérve!",
                                   message: "Új jegy: \(grade.subject)",
                                   challenge: grade.value == 5)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .offset(x: appeared ? 0 : 420)
                    .animation(.easeOut(duration: 0.35), value: appeared)

                Text(dateText)
                    .font(MinecraftTheme.font(.caption))
                    .foregroundStyle(Color(hex: 0xAAAAAA))
                    .shadow(color: mcShadow(0xAAAAAA), radius: 0, x: px / 1.5, y: px / 1.5)
                    .padding(.top, 10)

                Spacer(minLength: 12)

                // Hős: a jegy tömör concrete-blokkon, mint a Jegyek tabon.
                Text("\(grade.value)")
                    .mcDisplay(76)
                    .foregroundStyle(.white)
                    .frame(width: 168, height: 168)
                    .background(
                        McBlockPanel(face: gradeColor, outline: Color(hex: 0x1E1A16),
                                     highlight: .white.opacity(0.38), shade: .black.opacity(0.28))
                    )
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.2).delay(0.25), value: appeared)

                // XP-sáv + (ha a tanár beleírta) a valós százalék.
                VStack(spacing: 8) {
                    if percent != nil {
                        Text("\(shownPct)%")
                            .mcDisplay(40)
                            .foregroundStyle(Color(hex: 0x80FF20))
                            .shadow(color: mcShadow(0x80FF20), radius: 0, x: px / 1.5, y: px / 1.5)
                    }
                    McProgressBar(value: xp)
                        .frame(width: 280)
                }
                .padding(.top, 16)
                .opacity(appeared ? 1 : 0)

                Spacer(minLength: 16)

                // Balra zárt infóblokk: tantárgy + mire kapta
                VStack(alignment: .leading, spacing: 6) {
                    Text(grade.subject)
                        .mcDisplay(26)
                        .foregroundStyle(.white)
                    Text(topicLine)
                        .font(MinecraftTheme.font(.headline))
                        .foregroundStyle(Color(hex: 0xAAAAAA))
                        .shadow(color: mcShadow(0xAAAAAA), radius: 0, x: px / 1.5, y: px / 1.5)
                    Text("\(friendlyGradeType(grade.type)) • \(grade.teacher)")
                        .font(MinecraftTheme.font(.subheadline))
                        .foregroundStyle(Color(hex: 0xAAAAAA))
                        .shadow(color: mcShadow(0xAAAAAA), radius: 0, x: px / 1.5, y: px / 1.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .opacity(appeared ? 1 : 0)

                Spacer(minLength: 20)

                VStack(spacing: 10) {
                    Button {
                        NotificationManager.shared.celebrationGrade = nil
                        NotificationCenter.default.post(name: switchToGrades, object: nil)
                    } label: {
                        Text("Megnézem a jegyeim").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(McButtonStyle(prominent: true))
                    Button {
                        NotificationManager.shared.celebrationGrade = nil
                    } label: {
                        Text("Szuper!").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(McButtonStyle())
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
                .opacity(appeared ? 1 : 0)
            }
        }
    }
}

// MARK: - Cyberpunk ág — „breach protocol" felfedés
//
// ~1,2 mp, koppintással átugorható: sárga fejléc-csík besöpör → a HUD-panel
// függőlegesen kinyílik, a jegy 6 álszámjegyen át „dekódolódik" → lezár egy
// rövid kromatikus rándulással + megerősítő blippel → a street-cred-szerű
// sáv és az infó beúszik. Reduce Motion mellett nincs dekódolás/söprés,
// csak a kész állapot (a hang marad). Rajzolás statikus, nincs per-frame.

extension GradeCelebrationView {
    /// A jegy szintje a HUD nyelvén (felirat + szín).
    fileprivate var cpTier: (label: String, color: Color) {
        switch grade.value {
        case 5: return ("KIVÁLÓ // 5", CyberpunkTheme.cyanBright)
        case 4: return ("JÓ // 4", CyberpunkTheme.green)
        case 3: return ("KÖZEPES // 3", CyberpunkTheme.yellow)
        case 2: return ("ELÉGSÉGES // 2", CyberpunkTheme.orange)
        case 1: return ("RIASZTÁS // 1", CyberpunkTheme.red)
        default: return ("JEGY", CyberpunkTheme.dim)
        }
    }

    /// Stabil, determinisztikus „memóriacím" a jegyhez (csak díszítés).
    fileprivate var cpCode: String {
        let sum = grade.id.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return String(format: "0x%04X", sum & 0xFFFF)
    }

    /// A kijelzett százalék: átugrásnál / Reduce Motionnél rögtön a végérték.
    fileprivate var cpPct: Int {
        (cpSkipped || reduceMotion) ? (percent ?? 0) : shownPct
    }

    @MainActor
    fileprivate func cpRunBreach() async {
        if reduceMotion {
            cpLocked = true
            cpPhase = 3
            CPSound.play(.confirm)
            return
        }
        /// Alvás; false, ha közben átugrották / bezárták.
        func nap(_ ms: UInt64) async -> Bool {
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
            return !Task.isCancelled && cpPhase < 3
        }
        guard await nap(60) else { return }
        withAnimation(.easeOut(duration: 0.2)) { cpPhase = 1 }
        guard await nap(200) else { return }
        CPSound.play(.glitch, volume: 0.6)
        cpDigit = Int.random(in: 1...5)
        withAnimation(.easeOut(duration: 0.18)) { cpPhase = 2 }
        for _ in 0..<6 {
            guard await nap(45) else { return }
            let cur = cpDigit
            cpDigit = (1...5).filter { $0 != cur }.randomElement()
        }
        guard await nap(45) else { return }
        cpLock()
        guard await nap(220) else { return }
        withAnimation(.easeOut(duration: 0.25)) { cpPhase = 3 }
    }

    fileprivate func cpLock() {
        guard !cpLocked else { return }
        cpDigit = nil
        cpLocked = true
        CPSound.play(.confirm)
    }

    /// Koppintás a háttérre: azonnal a kész állapot.
    fileprivate func cpSkip() {
        guard cpPhase < 3 else { return }
        cpSkipped = true
        cpLock()
        withAnimation(.easeOut(duration: 0.15)) { cpPhase = 3 }
    }

    fileprivate var cpContent: some View {
        let tint = gradeColor
        let tier = cpTier
        let xp = percent != nil ? Double(cpPct) / 100 : Double(grade.value) / 5
        return ZStack {
            CPBackdrop()
            // Halvány jegyszínű derengés felül (statikus).
            LinearGradient(colors: [tint.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    CPLabel("SUMMIT // KRÉTA.NET", bracketed: false)
                    Spacer()
                    Button {
                        NotificationManager.shared.celebrationGrade = nil
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(CPButtonStyle(kind: .secondary, compact: true))
                    .accessibilityLabel("Bezárás")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Fejléc-csík: balról besöpör (a játék breach-fejléce).
                HStack(spacing: 8) {
                    Text("ÚJ JEGY")
                        .font(CyberpunkTheme.font(.headline, weight: .bold))
                        .tracking(2)
                    Spacer(minLength: 8)
                    Text("BREACH // \(cpCode)")
                        .font(CyberpunkTheme.mono(size: 11, relativeTo: .caption2))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(CPChamferShape(cut: 10, corners: [.topLeft, .bottomRight]).fill(CyberpunkTheme.yellow))
                .scaleEffect(x: cpPhase >= 1 ? 1 : 0.02, y: 1, anchor: .leading)
                .opacity(cpPhase >= 1 ? 1 : 0)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .accessibilityElement(children: .combine)

                Text("KRÉTA › \(grade.subject.uppercased()) › \(dateText.uppercased())")
                    .font(CyberpunkTheme.mono(size: 11, relativeTo: .caption2))
                    .foregroundStyle(CyberpunkTheme.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                    .opacity(cpPhase >= 1 ? 1 : 0)

                Spacer(minLength: 12)

                // Hős-panel: függőlegesen nyílik, benne a dekódolódó jegy.
                VStack(spacing: 10) {
                    CPLabel(tier.label, color: tier.color, size: 11)
                    Text("\(cpDigit ?? grade.value)")
                        .font(CyberpunkTheme.display(size: 104, weight: .bold, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(cpDigit == nil ? tint : CyberpunkTheme.text.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .cpChromatic(cpLocked ? 1.2 : 0)
                        .cpGlitch(trigger: cpLocked)
                        .contentTransition(.identity)
                        .accessibilityLabel("\(grade.value)-es jegy")
                    if percent != nil {
                        Text("\(cpPct)%")
                            .font(CyberpunkTheme.display(size: 34, weight: .semibold, relativeTo: .title))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .contentTransition(.numericText())
                    }
                    CPProgressBar(value: cpLocked ? xp : 0, tint: tint, segments: 20, height: 8)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: cpLocked)
                    HStack {
                        CPLabel("SÚLY \(grade.weight)%", bracketed: false)
                        Spacer()
                        CPLabel(percent != nil ? "PONTSZÁM" : "SZINT \(grade.value)/5", bracketed: false)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(minWidth: 240, maxWidth: 300)
                .background(CPPanelBackground(accent: tint, fill: CyberpunkTheme.panel, corners: .diagonal, cut: 18))
                .scaleEffect(x: 1, y: cpPhase >= 2 ? 1 : 0.04, anchor: .center)
                .opacity(cpPhase >= 2 ? 1 : 0)

                Spacer(minLength: 16)

                // Infóblokk: tantárgy + téma, alatta kód-címkék.
                VStack(alignment: .leading, spacing: 6) {
                    Text(grade.subject)
                        .font(CyberpunkTheme.display(size: 26, weight: .bold, relativeTo: .title2))
                        .foregroundStyle(CyberpunkTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(topicLine)
                        .font(CyberpunkTheme.font(.headline, weight: .semibold))
                        .foregroundStyle(CyberpunkTheme.dim)
                        .lineLimit(3)
                    CPDivider(color: tint)
                        .padding(.vertical, 4)
                    Text("\(friendlyGradeType(grade.type)) · \(grade.teacher)".uppercased())
                        .font(CyberpunkTheme.mono(size: 11, relativeTo: .caption))
                        .tracking(0.6)
                        .foregroundStyle(CyberpunkTheme.dim)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .opacity(cpPhase >= 3 ? 1 : 0)
                .offset(y: cpPhase >= 3 || reduceMotion ? 0 : 10)

                Spacer(minLength: 20)

                VStack(spacing: 10) {
                    Button {
                        NotificationManager.shared.celebrationGrade = nil
                        NotificationCenter.default.post(name: switchToGrades, object: nil)
                    } label: {
                        Text("Megnézem a jegyeim")
                    }
                    .buttonStyle(CPButtonStyle(kind: .primary, fullWidth: true))
                    Button {
                        NotificationManager.shared.celebrationGrade = nil
                    } label: {
                        Text("Szuper!")
                    }
                    .buttonStyle(CPButtonStyle(kind: .secondary, fullWidth: true))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
                .opacity(cpPhase >= 2 ? 1 : 0)
            }
        }
        // Koppintás bárhová (a gombokon kívül) = átugrás a kész állapotra;
        // a gombok saját koppintása elsőbbséget élvez.
        .contentShape(Rectangle())
        .onTapGesture { cpSkip() }
    }
}

// MARK: - Natív konfetti (Apple CAEmitterLayer, függőség nélkül)
// - A rendszer QuartzCore részecskemotorja rajzolja (GPU), nem kézzel
//   animált SwiftUI-nézetek — iOS-en és Mac Catalysten is ugyanaz.
// - Ünnepi recept: fentről zápor + két oldalsó ágyú lő befelé-felfelé,
//   ~2.5 mp születés, aztán a szemek kihullanak és a layerek
//   eltűnnek (nincs ottfelejtett emitter).
// - Mozgásérzékenység (Reduce Motion) mellett néma: csak a kártya animál.
private struct ConfettiView: UIViewRepresentable {
    let tint: Color
    @Environment(\.displayScale) private var displayScale

    func makeUIView(context: Context) -> CelebrationConfettiView {
        CelebrationConfettiView()
    }

    func updateUIView(_ uiView: CelebrationConfettiView, context: Context) {
        uiView.startIfNeeded(tint: UIColor(tint), scale: displayScale)
    }
}

private final class CelebrationConfettiView: UIView {
    private var emitters: [CAEmitterLayer] = []
    private var started = false
    /// Születés-hossz: eddig jönnek új szemek, utána elapad.
    private let burstSeconds: TimeInterval = 2.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutEmitters()
    }

    func startIfNeeded(tint: UIColor, scale: CGFloat) {
        guard !started else { return }
        // Valós méret kell (a makeUIView-kor még .zero) — a következő
        // layoutra újra próbáljuk; a Reduce Motion-nál indulunk sem.
        guard bounds.width > 10, bounds.height > 10 else {
            setNeedsLayout()
            return
        }
        started = true
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let s = scale > 0 ? scale : 2
        emitters = [topRain(tint: tint, scale: s),
                    sideCannon(tint: tint, scale: s, left: true),
                    sideCannon(tint: tint, scale: s, left: false)]
        emitters.forEach { layer.addSublayer($0) }
        layoutEmitters()
        // Elapadás + takarítás: a születés leáll, a kihullott szemek
        // után a layerek sem maradnak ott.
        DispatchQueue.main.asyncAfter(deadline: .now() + burstSeconds) { [weak self] in
            self?.emitters.forEach { $0.birthRate = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + burstSeconds + 6) { [weak self] in
            self?.emitters.forEach { $0.removeFromSuperlayer() }
            self?.emitters = []
        }
    }

    /// Emitter-pozíciók a mindenkori mérethez (forgatásra is jó).
    private func layoutEmitters() {
        guard emitters.count == 3 else { return }
        let w = bounds.width, h = bounds.height
        let rain = emitters[0]
        rain.frame = bounds
        rain.emitterPosition = CGPoint(x: w / 2, y: -12)
        rain.emitterSize = CGSize(width: w, height: 1)
        let left = emitters[1], right = emitters[2]
        left.frame = bounds
        left.emitterPosition = CGPoint(x: -8, y: h * 0.72)
        right.frame = bounds
        right.emitterPosition = CGPoint(x: w + 8, y: h * 0.72)
    }

    /// Fentről, teljes szélességben záporozó eső.
    private func topRain(tint: UIColor, scale: CGFloat) -> CAEmitterLayer {
        let e = CAEmitterLayer()
        e.emitterShape = .line
        e.emitterMode = .surface
        e.birthRate = 1
        e.emitterCells = rainCells(tint: tint, scale: scale)
        return e
    }

    /// Oldalsó ágyú: pontról, befelé-felfelé lő (klasszikus partiágyú).
    private func sideCannon(tint: UIColor, scale: CGFloat, left: Bool) -> CAEmitterLayer {
        let e = CAEmitterLayer()
        e.emitterShape = .point
        e.emitterMode = .surface
        e.birthRate = 1
        e.emitterCells = cannonCells(tint: tint, scale: scale, left: left)
        return e
    }

    private func palette(tint: UIColor) -> [UIColor] {
        [tint, .white, .systemYellow, .systemOrange, .systemPink,
         tint.withAlphaComponent(0.7)]
    }

    private func rainCells(tint: UIColor, scale: CGFloat) -> [CAEmitterCell] {
        let rect = particleImage(size: CGSize(width: 12, height: 16), radius: 3, scale: scale)
        let dot = particleImage(size: CGSize(width: 11, height: 11), radius: 5.5, scale: scale)
        return palette(tint: tint).enumerated().map { i, color in
            let cell = CAEmitterCell()
            cell.contents = (i % 3 == 2 ? dot : rect)?.cgImage
            cell.color = color.cgColor
            cell.birthRate = 7
            cell.lifetime = 5.0
            cell.lifetimeRange = 1.5
            cell.velocity = 300
            cell.velocityRange = 140
            cell.emissionLongitude = .pi / 2 // lefelé
            cell.emissionRange = .pi / 6
            cell.spin = 5 // pörgés-forgás, ettől lesz konfetti-érzet
            cell.spinRange = 6
            cell.scale = 1.0
            cell.scaleRange = 0.5
            cell.yAcceleration = 220 // gravitáció
            cell.alphaSpeed = -0.18 // a végén elhalványul
            return cell
        }
    }

    private func cannonCells(tint: UIColor, scale: CGFloat, left: Bool) -> [CAEmitterCell] {
        let rect = particleImage(size: CGSize(width: 12, height: 16), radius: 3, scale: scale)
        let dot = particleImage(size: CGSize(width: 11, height: 11), radius: 5.5, scale: scale)
        // Balról jobbra-fel, jobbról balra-fel (radián, +x-től, +y lefelé).
        let direction: CGFloat = left ? -.pi / 3 : -.pi + .pi / 3
        return palette(tint: tint).enumerated().map { i, color in
            let cell = CAEmitterCell()
            cell.contents = (i % 3 == 2 ? dot : rect)?.cgImage
            cell.color = color.cgColor
            cell.birthRate = 12
            cell.lifetime = 3.6
            cell.lifetimeRange = 1.0
            cell.velocity = 620
            cell.velocityRange = 180
            cell.emissionLongitude = direction
            cell.emissionRange = .pi / 7
            cell.spin = 7
            cell.spinRange = 8
            cell.scale = 1.0
            cell.scaleRange = 0.5
            cell.yAcceleration = 420
            cell.alphaSpeed = -0.25
            return cell
        }
    }

    private func particleImage(size: CGSize, radius: CGFloat, scale: CGFloat) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale > 0 ? scale : 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius).fill()
        }
    }
}
