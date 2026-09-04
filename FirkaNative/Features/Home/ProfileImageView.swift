import SwiftUI

struct ProfileImageView: View {
    let name: String
    var userId: String? = nil
    var size: CGFloat = 38
    var badge: Bool = false
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var profileStore: ProfileImageStore
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let accent = theme.accent
        ZStack(alignment: .topTrailing) {
            Group {
                if let uid = userId, let ui = profileStore.image(for: uid) {
                    Image(uiImage: ui)
                        .resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .glassEffectIfAvailable(in: Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(accent)
                            .frame(width: size, height: size)
                            .glassEffectIfAvailable(in: Circle(), tint: accent)
                        Text(initials)
                            .font(.system(size: size*0.42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
            }
            if badge {
                Circle().fill(Color.red).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: 2, y: -2)
            }
        }
    }
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }
}

/// Toolbar profilgomb natív Apple-elemekből: fotó esetén körbevágott kép,
/// különben SF Symbol — semmi custom glass, mindig szabályos kör.
struct ToolbarAvatar: View {
    var userId: String? = nil
    @EnvironmentObject var profileStore: ProfileImageStore
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        Group {
            if let uid = userId, let ui = profileStore.image(for: uid) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(theme.accent)
            }
        }
    }
}
