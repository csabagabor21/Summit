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
// - A rendszer QuartzCore részecskemotorja rajzolja (GPU), nem 48 kézzel
//   animált SwiftUI-nézet — iOS-en és Mac Catalysten is ugyanaz.
// - Felülről, teljes szélességben záporozik ~1.8 mp-ig, aztán a szemek
//   kihullanak (lifetime) — nincs kézi eltüntetés.
private struct ConfettiView: UIViewRepresentable {
    let tint: Color
    @Environment(\.displayScale) private var displayScale

    func makeUIView(context: Context) -> NativeConfettiView {
        let view = NativeConfettiView()
        view.start(tint: UIColor(tint), scale: displayScale)
        return view
    }

    func updateUIView(_ uiView: NativeConfettiView, context: Context) {}
}

private final class NativeConfettiView: UIView {
    private let emitter = CAEmitterLayer()
    private var started = false

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
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -10)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
    }

    func start(tint: UIColor, scale: CGFloat) {
        guard !started else { return }
        started = true
        emitter.emitterShape = .line
        emitter.emitterMode = .surface
        emitter.birthRate = 1
        emitter.emitterCells = makeCells(tint: tint, scale: scale)
        layer.addSublayer(emitter)
        setNeedsLayout()
        layoutIfNeeded()
        // Zápor, aztán elapad: az új szemek születése leáll, a meglévők
        // a lifetime végére kihullanak és elhalványulnak.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.emitter.birthRate = 0
        }
    }

    private func makeCells(tint: UIColor, scale: CGFloat) -> [CAEmitterCell] {
        let palette: [UIColor] = [
            tint,
            .white,
            .systemYellow,
            .systemOrange,
            tint.withAlphaComponent(0.65),
        ]
        let rect = particleImage(size: CGSize(width: 9, height: 13), radius: 2.5, scale: scale)
        let dot = particleImage(size: CGSize(width: 9, height: 9), radius: 4.5, scale: scale)
        return palette.enumerated().map { i, color in
            let cell = CAEmitterCell()
            cell.contents = (i % 3 == 2 ? dot : rect)?.cgImage
            cell.color = color.cgColor
            cell.birthRate = 9
            cell.lifetime = 4.5
            cell.lifetimeRange = 1.5
            cell.velocity = 260
            cell.velocityRange = 120
            cell.emissionLongitude = .pi / 2 // lefelé
            cell.emissionRange = .pi / 5
            cell.spin = 4 // pörgés-forgás, ettől lesz konfetti-érzet
            cell.spinRange = 5
            cell.scale = 0.9
            cell.scaleRange = 0.45
            cell.yAcceleration = 140 // gravitáció
            cell.alphaSpeed = -0.2 // a végén elhalványul
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
