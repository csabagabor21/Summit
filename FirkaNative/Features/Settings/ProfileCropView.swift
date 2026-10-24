import SwiftUI

// MARK: - Profilkép kivágó — rendszer-fotós feeling, natív gesztusokkal
// Négyzetre vág: húzással mozgatható, csippentéssel nagyítható,
// harmadolós ráccsal + sötétítéssel a kivágáson kívül.
struct ProfileCropView: View {
    let image: UIImage
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width - 32
            let square = CGRect(
                x: (geo.size.width - side) / 2,
                y: (geo.size.height - side) / 2,
                width: side, height: side
            )
            // Befedő alapméret (scale = 1) — a kép mindenképp kitölti a négyzetet
            let aspect = image.size.width / image.size.height
            let baseW = aspect >= 1 ? side * aspect : side
            let baseH = aspect >= 1 ? side : side / aspect
            let dispW = baseW * scale
            let dispH = baseH * scale

            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: dispW, height: dispH)
                    .position(x: geo.size.width / 2 + offset.width, y: geo.size.height / 2 + offset.height)
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { v in
                                offset = clamped(
                                    CGSize(width: lastOffset.width + v.translation.width,
                                           height: lastOffset.height + v.translation.height),
                                    dispW: dispW, dispH: dispH, side: side
                                )
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { v in
                                scale = min(4, max(1, lastScale * v.magnification))
                                offset = clamped(offset, dispW: baseW * scale, dispH: baseH * scale, side: side)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                lastOffset = clamped(lastOffset, dispW: dispW, dispH: dispH, side: side)
                                offset = lastOffset
                            }
                    )

                // Sötétítés a négyzeten kívül + harmadolós rács
                Color.black.opacity(0.62)
                    .mask {
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: geo.size))
                            p.addRect(square)
                        }
                        .fill(style: FillStyle(eoFill: true))
                    }
                    .allowsHitTesting(false)
                Path { p in
                    for i in 1..<3 {
                        let x = square.minX + square.width * CGFloat(i) / 3
                        p.move(to: CGPoint(x: x, y: square.minY))
                        p.addLine(to: CGPoint(x: x, y: square.maxY))
                        let y = square.minY + square.height * CGFloat(i) / 3
                        p.move(to: CGPoint(x: square.minX, y: y))
                        p.addLine(to: CGPoint(x: square.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
                .allowsHitTesting(false)
                Rectangle()
                    .path(in: square)
                    .stroke(Color.white, lineWidth: 2)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        Button("Mégse") { onCancel() }
                            .skinFont(.body, weight: .medium)
                            .foregroundStyle(.white)
                            .mcInlineButton()
                        Spacer()
                        Text("Kivágás")
                            .skinFont(.headline, weight: .semibold)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Kész") {
                            if let out = cropped(side: side, dispW: dispW, dispH: dispH) {
                                onDone(out)
                            } else {
                                onCancel()
                            }
                        }
                        .skinFont(.body, weight: .bold)
                        .foregroundStyle(.white)
                        .mcInlineButton()
                    }
                    .padding(.horizontal, 20)
                    // fullScreenCover a notch / óra alá is benyúlik —
                    // enélkül a Mégse/Kész gombok a státuszsáv alá szorulnak.
                    .padding(.top, geo.safeAreaInsets.top + 12)
                    Spacer()
                    Text("Húzd és csippentsd a megfelelő részlethez")
                        .skinFont(.caption, weight: .medium)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.bottom, geo.safeAreaInsets.bottom + 24)
                }
            }
        }
    }

    /// A kivágóba menő kép előkészítése: álló (`.up`) tájolásra rajzolva,
    /// 1x skálán, a hosszabb oldal max. 2048 pont. A `cropped` a CGImage
    /// nyers pixeleiből vág — elforgatott fotón (a kamera álló képei
    /// `.right` tájolásúak) e nélkül rossz részletet adna.
    static func prepared(_ image: UIImage, maxSide: CGFloat = 2048) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return image }
        let k = min(1, maxSide / longest)
        if image.imageOrientation == .up, image.scale == 1, k == 1 { return image }
        let size = CGSize(width: (image.size.width * k).rounded(), height: (image.size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func clamped(_ o: CGSize, dispW: CGFloat, dispH: CGFloat, side: CGFloat) -> CGSize {
        let mx = max(0, (dispW - side) / 2)
        let my = max(0, (dispH - side) / 2)
        return CGSize(
            width: min(mx, max(-mx, o.width)),
            height: min(my, max(-my, o.height))
        )
    }

    private func cropped(side: CGFloat, dispW: CGFloat, dispH: CGFloat) -> UIImage? {
        // A négyzet bal-felső sarka a megjelenített képen belül (pontban),
        // átváltva képpontra — a clamp miatt mindig a képen belül van.
        let ox = (dispW - side) / 2 - offset.width
        let oy = (dispH - side) / 2 - offset.height
        let r = image.size.width / dispW
        let rect = CGRect(x: ox * r, y: oy * r, width: side * r, height: side * r)
            .intersection(CGRect(origin: .zero, size: image.size))
        guard !rect.isNull, rect.width > 10, rect.height > 10,
              let cg = image.cgImage?.cropping(to: rect.integral) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}
