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
                    .buttonStyle(.plain)
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
                            .font(.system(size: 76, weight: .bold, design: .rounded))
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
                        .font(.system(size: 52, weight: .bold, design: .rounded))
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
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(topicLine)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(grade.type.isEmpty ? "Értékelés" : grade.type) • \(grade.teacher)")
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
                    .buttonStyle(.plain)
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
        .onAppear {
            // Új jegy = ünnepelt kimenet: egyetlen success a konfettival együtt.
            SummitHaptics.success()
            withAnimation(SummitMotion.gentle) { appeared = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
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
