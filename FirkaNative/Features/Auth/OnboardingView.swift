import SwiftUI

/// Bejelentkezés előtti interaktív bemutató: mi / hogy / merre / meddig.
/// Első indításkor jön fel, utána az `onboarding.seen.v1` őrzi.
/// Minden oldal egy koppintható mini-demót tartalmaz — nem csak olvasni,
/// ki is lehet próbálni a fő mechanikákat belépés előtt.
struct OnboardingView: View {
    @AppStorage("onboarding.seen.v1") private var seen = false
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    private var lastPage: Bool { page == OnboardingPage.pages.count - 1 }

    var body: some View {
        ZStack {
            Image("Glacier")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            LinearGradient(
                colors: [.black.opacity(0.62), .black.opacity(0.3), .black.opacity(0.78)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !lastPage {
                        Button("Kihagyás") { finish() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .frame(height: 44)

                TabView(selection: $page) {
                    ForEach(Array(OnboardingPage.pages.enumerated()), id: \.element.id) { idx, p in
                        OnboardingPageView(page: p, reduceMotion: reduceMotion)
                            .tag(idx)
                            .padding(.horizontal, 28)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : SummitMotion.page, value: page)

                HStack(spacing: 8) {
                    ForEach(0..<OnboardingPage.pages.count, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? .white : .white.opacity(0.35))
                            .frame(width: i == page ? 22 : 7, height: 7)
                            .animation(reduceMotion ? nil : SummitMotion.snappy, value: page)
                            .onTapGesture { page = i }
                    }
                }
                .padding(.top, 12)
                Text("\(page + 1) / \(OnboardingPage.pages.count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)

                Button {
                    if lastPage { finish() }
                    else { page += 1 }
                } label: {
                    Text(lastPage ? "Bejelentkezés" : "Tovább")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .functionalGlass(cornerRadius: 14)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: isPad ? 320 : .infinity)
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .tint(.white)
    }

    private func finish() {
        seen = true
    }
}

private struct OnboardingPage: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let body: String
    let demo: DemoKind

    enum DemoKind { case grades, timetable, tasks, notify, login }

    static let pages: [OnboardingPage] = [
        OnboardingPage(
            id: "jegyek", symbol: "chart.line.uptrend.xyaxis",
            title: "Mi történik a suliban?",
            body: "Jegyek valós időben, súlyozott átlaggal és tanári kerekítéssel. Koppints a jegyekre!",
            demo: .grades
        ),
        OnboardingPage(
            id: "orarend", symbol: "calendar.day.timeline.left",
            title: "Merre kell menned?",
            body: "Mai órarend élő MOST-kártyával. Az iskolai események 0. óraként jelennek meg. Pipáld ki a termet!",
            demo: .timetable
        ),
        OnboardingPage(
            id: "feladat", symbol: "checklist",
            title: "Hogy ne felejts el semmit?",
            body: "Házi és dolgozat egy listában, kipipálhatóan. Próbáld ki a pipát!",
            demo: .tasks
        ),
        OnboardingPage(
            id: "ertesites", symbol: "bell.badge.fill",
            title: "Meddig kell figyelned?",
            body: "Semennyit. Új jegynél, házinál és hiányzásnál az app magától jelez — kapcsold be a csengőt!",
            demo: .notify
        ),
        OnboardingPage(
            id: "belepes", symbol: "person.crop.circle.badge.checkmark",
            title: "Egy perc, és bent vagy",
            body: "e-KRÉTA belépés böngészővel, semmi jelszó-tárolás trükk. Demo módban belépés nélkül is körbenézhetsz.",
            demo: .login
        ),
    ]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let reduceMotion: Bool
    @State private var appeared = false
    @State private var pickedGrade = 5
    @State private var roomDone = false
    @State private var taskDone = false
    @State private var bellOn = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 128, height: 128)
                Image(systemName: page.symbol)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .speed(0.7), value: appeared)
            }
            .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.85))
            .opacity(appeared ? 1 : 0)
            .onAppear {
                if reduceMotion { appeared = true }
                else { withAnimation(SummitMotion.gentle) { appeared = true } }
            }
            Text(page.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(page.body)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            demoCard
                .padding(.top, 4)
            Spacer(minLength: 8)
        }
        .summitEntrance(delay: 0.05)
    }

    @ViewBuilder
    private var demoCard: some View {
        switch page.demo {
        case .grades:
            HStack(spacing: 10) {
                ForEach([5, 4, 3], id: \.self) { g in
                    Text("\(g)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(pickedGrade == g ? .black : .white)
                        .frame(width: 52, height: 52)
                        .background(pickedGrade == g ? .white : .white.opacity(0.16), in: Circle())
                        .onTapGesture {
                            if !reduceMotion {
                                withAnimation(SummitMotion.snappy) { pickedGrade = g }
                            } else { pickedGrade = g }
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("átlag")
                        .font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Text(String(format: "%.2f", Double(pickedGrade) - 0.15))
                        .font(.title3.weight(.bold).monospaced()).foregroundStyle(.white)
                }
                .padding(.leading, 6)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        case .timetable:
            HStack(spacing: 12) {
                Text("MOST")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white, in: Capsule())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Matematika • 204").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(roomDone ? "Terem megjegyezve ✓" : "Koppints a pipához").font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: roomDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(.white)
                    .onTapGesture {
                        if !reduceMotion { withAnimation(SummitMotion.snappy) { roomDone.toggle() } }
                        else { roomDone.toggle() }
                    }
            }
            .padding(14)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        case .tasks:
            HStack(spacing: 12) {
                Image(systemName: taskDone ? "checkmark.square.fill" : "square")
                    .font(.title2).foregroundStyle(.white)
                    .onTapGesture {
                        if !reduceMotion { withAnimation(SummitMotion.snappy) { taskDone.toggle() } }
                        else { taskDone.toggle() }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Házi: 12. lecke").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .strikethrough(taskDone)
                    Text(taskDone ? "Kész — szép munka" : "Holnapra").font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
            .padding(14)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        case .notify:
            HStack(spacing: 12) {
                Image(systemName: bellOn ? "bell.fill" : "bell.slash.fill")
                    .font(.title2).foregroundStyle(.white)
                    .symbolEffect(.bounce, value: bellOn)
                    .onTapGesture {
                        if !reduceMotion { withAnimation(SummitMotion.snappy) { bellOn.toggle() } }
                        else { bellOn.toggle() }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(bellOn ? "Értesítések bekapcsolva" : "Értesítések kikapcsolva")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("Új jegy • házi • hiányzás").font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
            .padding(14)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        case .login:
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.white.opacity(0.85))
                Text("KRÉTA-belépés • Demo móddal kipróbálható")
                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
