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
                        // Voxelben a fej keretezett, négyzetes (mint az inventory-slot).
                        // Neonban levágott sarkú, sárga 1 px-es neon kerettel.
                        .overlay {
                            if VoxelTheme.isActive {
                                VoxelSlotFrame()
                            } else if NeonTheme.isActive {
                                NeonChamferShape(cut: 8).strokeBorder(NeonTheme.yellow, lineWidth: 1)
                            }
                        }
                } else if NeonTheme.isActive {
                    // Neon: majdnem fekete HUD-lap, sárga monogram és keret
                    // (a sárga kitöltés fehér betűvel olvashatatlan lenne).
                    Text(initials)
                        .font(NeonTheme.display(size: (size * 0.46).rounded(), weight: .bold, relativeTo: .caption))
                        .tracking(0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(NeonTheme.yellow)
                        .frame(width: size, height: size)
                        .background(NeonChamferShape(cut: 8).fill(NeonTheme.panel))
                        .overlay(NeonChamferShape(cut: 8).strokeBorder(NeonTheme.yellow, lineWidth: 1))
                } else if VoxelTheme.isActive {
                    // Voxel: akcent-színű pixel-blokk, Monocraft monogrammal.
                    Text(initials)
                        .font(VoxelFontLoader.font(size: (size * 0.38).rounded()))
                        .foregroundStyle(.white)
                        .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: VoxelTheme.px / 1.5, y: VoxelTheme.px / 1.5)
                        .frame(width: size, height: size)
                        .background(VoxelBlockPanel(face: colors.accent, castsShadow: false))
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
                if NeonTheme.isActive {
                    // HUD-jelvény: levágott sarkú vörös négyzet, sötét kerettel.
                    NeonChamferShape(cut: 3).fill(NeonTheme.red).frame(width: 10, height: 10)
                        .overlay(NeonChamferShape(cut: 3).strokeBorder(NeonTheme.bg, lineWidth: 1.5))
                        .offset(x: 2, y: -2)
                } else if VoxelTheme.isActive {
                    Rectangle().fill(Color.red).frame(width: 10, height: 10)
                        .overlay(Rectangle().strokeBorder(.white, lineWidth: VoxelTheme.px / 2))
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
