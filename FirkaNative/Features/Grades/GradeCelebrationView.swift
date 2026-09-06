import SwiftUI
import UIKit

// MARK: - Új jegy ünneplő kártya (fullscreen)
// - Középen nagyban: liquid glass kör a jeggyel (mint a Jegyek tabon)
// - Alatta menő helyen a százalék (5 → 100%)
// - Alatta balra zárva: tantárgy, mire kapta (téma), típus • tanár • dátum • súly
struct GradeCelebrationView: View {
    let grade: GradeItem
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @State private var appeared = false
    @State private var pulse = false
    @State private var shownPct = 0
    private let switchToGrades = Notification.Name("flint.switchToGrades")

    var colors: AppColors { theme.colors(for: scheme) }
    private var gradeColor: Color { colors.gradeColor(for: grade.value) }
    private var percent: Int { grade.value * 20 }
    private var topicLine: String { grade.topic.isEmpty ? grade.type : grade.topic }
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
                        .scaleEffect(pulse ? 1.14 : 1.0)
                        .opacity(pulse ? 1 : 0.75)
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

                // Százalék nagyban a szám alatt — 0-ról pörög fel
                Text("\(shownPct)%")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(gradeColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.top, 10)
                    .opacity(appeared ? 1 : 0)

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
                .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.15), value: appeared)

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
                .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.3), value: appeared)
            }
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
        .task {
            // Százalék felpörgetése 0-ról a célra
            try? await Task.sleep(nanoseconds: 400_000_000)
            let steps = 24
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: 1_300_000_000 / UInt64(steps))
                if Task.isCancelled { return }
                shownPct = percent * i / steps
            }
        }
    }
}

// MARK: - Könnyű konfetti (függőség nélkül)
private struct ConfettiView: View {
    let tint: Color
    @State private var fall = false
    @State private var gone = false
    private struct Piece: Identifiable {
        let id = UUID()
        let x: Double // 0...1 relatív
        let delay: Double
        let duration: Double
        let w: Double
        let h: Double
        let colorIdx: Int
        let round: Bool
    }
    private var pieces: [Piece] {
        (0..<90).map { i in
            let r1 = Double((i * 37 + 11) % 100) / 100.0
            let r2 = Double((i * 53 + 29) % 100) / 100.0
            let r3 = Double((i * 71 + 47) % 100) / 100.0
            return Piece(
                x: r1,
                delay: 0.15 + r2 * 1.3,
                duration: 2.6 + r3 * 1.6,
                w: 7 + r2 * 8,
                h: 10 + r3 * 10,
                colorIdx: i % 5,
                round: i % 3 == 0
            )
        }
    }
    private func color(_ idx: Int) -> Color {
        switch idx {
        case 0: return tint
        case 1: return .white
        case 2: return .yellow
        case 3: return tint.opacity(0.65)
        default: return .orange
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    Group {
                        if p.round {
                            Circle().fill(color(p.colorIdx))
                        } else {
                            RoundedRectangle(cornerRadius: 2.5).fill(color(p.colorIdx))
                        }
                    }
                    .frame(width: p.w, height: p.h)
                    .position(
                        x: p.x * geo.size.width,
                        y: fall ? geo.size.height + 40 : -40
                    )
                    .rotationEffect(.degrees(fall ? 540 : 0))
                    .animation(
                        .linear(duration: p.duration).delay(p.delay),
                        value: fall
                    )
                }
            }
            .opacity(gone ? 0 : 1)
            .onAppear { fall = true }
            .task {
                // A konfetti végighullik (~4.5s), csak utána halványul el.
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.8)) { gone = true }
            }
        }
        .allowsHitTesting(false)
    }
}
