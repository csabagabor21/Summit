import SwiftUI

struct ProfileImageView: View {
    let name: String
    var userId: String? = nil
    var size: CGFloat = 38
    var badge: Bool = false
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var profileStore: ProfileImageStore

    var body: some View {
        let colors = AppColors.current(for: scheme)
        ZStack(alignment: .topTrailing) {
            Group {
                if let uid = userId, let ui = profileStore.image(for: uid) {
                    Image(uiImage: ui)
                        .resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(hex: 0x2B4C7E))
                        .frame(width: size, height: size)
                        .overlay {
                            Text(initials)
                                .font(.system(size: size*0.42, weight: .bold))
                                .foregroundStyle(.white)
                        }
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
