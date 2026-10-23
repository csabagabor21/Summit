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
        let colors = theme.colors(for: scheme)
        ZStack(alignment: .topTrailing) {
            Group {
                if let uid = userId, let ui = profileStore.image(for: uid) {
                    Image(uiImage: ui)
                        .resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .skinClip(Circle())
                        // Minecraftban a fej keretezett, négyzetes (mint az inventory-slot).
                        .overlay { if MinecraftTheme.isActive { McSlotFrame() } }
                } else if MinecraftTheme.isActive {
                    // Minecraft: akcent-színű pixel-blokk, Monocraft monogrammal.
                    Text(initials)
                        .font(MinecraftFontLoader.font(size: (size * 0.38).rounded()))
                        .foregroundStyle(.white)
                        .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: MinecraftTheme.px / 1.5, y: MinecraftTheme.px / 1.5)
                        .frame(width: size, height: size)
                        .background(McBlockPanel(face: colors.accent, castsShadow: false))
                } else {
                    Circle()
                        .fill(colors.accent)
                        .frame(width: size, height: size)
                        .overlay {
                            Text(initials)
                                .font(.system(size: size*0.42, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }
            }
            if badge {
                if MinecraftTheme.isActive {
                    Rectangle().fill(Color.red).frame(width: 10, height: 10)
                        .overlay(Rectangle().strokeBorder(.white, lineWidth: MinecraftTheme.px / 2))
                        .offset(x: 2, y: -2)
                } else {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: 2, y: -2)
                }
            }
        }
    }
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }
}
