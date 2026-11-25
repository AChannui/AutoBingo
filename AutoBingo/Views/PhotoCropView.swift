import SwiftUI
import UIKit

/// Shown right after a photo is taken or picked: drag the corners (or the box) to keep only the
/// part you need, or leave it as is to use the whole photo. Cropping out the surroundings gives
/// the text reader less noise to trip over.
struct PhotoCropView: View {
    let image: UIImage
    /// Called with the photo and the chosen crop, or nil if the person cancelled.
    let onFinish: (CroppedPhoto?) -> Void

    /// The kept area, as fractions of the photo's width and height (0...1).
    @State private var crop: CGRect
    @State private var dragStart: CGRect?

    private static let full = CroppedPhoto.fullFrame
    private static let minSize: CGFloat = 0.08
    private var isFull: Bool { crop == Self.full }

    /// `initialCrop` reopens the photo with an earlier crop, so it can be nudged instead of redone.
    init(image: UIImage, initialCrop: CGRect = CroppedPhoto.fullFrame, onFinish: @escaping (CroppedPhoto?) -> Void) {
        self.image = image
        self.onFinish = onFinish
        _crop = State(initialValue: initialCrop)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let frame = fittedFrame(in: geo.size)
                let box = CGRect(
                    x: frame.minX + crop.minX * frame.width,
                    y: frame.minY + crop.minY * frame.height,
                    width: crop.width * frame.width,
                    height: crop.height * frame.height
                )

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)

                    // Dim everything outside the kept area.
                    Path { path in
                        path.addRect(frame)
                        path.addRect(box)
                    }
                    .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                    // The box itself: drag inside it to move it.
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .background(gridLines)
                        .contentShape(Rectangle())
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                        .gesture(moveGesture(imageSize: frame.size))
                        .accessibilityLabel("Crop area")

                    ForEach(Corner.allCases, id: \.self) { corner in
                        handle(for: corner)
                            .position(corner.point(in: box))
                            .gesture(resizeGesture(corner, imageSize: frame.size))
                    }
                }
            }
            .padding(24)
            .background(Color.black)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Crop photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(nil) }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Text(isFull
                 ? "Drag the corners to keep just the part you need — or use the whole photo."
                 : "Only the bright area will be read.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { crop = Self.full }
                } label: {
                    Label("Whole photo", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isFull)

                Button {
                    onFinish(CroppedPhoto(original: image, crop: crop))
                } label: {
                    Label(isFull ? "Use photo" : "Use crop", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding()
        .background(Color.black)
        .tint(.white)
        .environment(\.colorScheme, .dark)
    }

    /// Rule-of-thirds lines inside the box, to help line it up.
    private var gridLines: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1...2 {
                    let x = geo.size.width * CGFloat(i) / 3
                    let y = geo.size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private func handle(for corner: Corner) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .shadow(radius: 2)
            .frame(width: 48, height: 48)      // a bigger, invisible touch target
            .contentShape(Rectangle())
            .accessibilityLabel("Resize crop, \(corner.name) corner")
    }

    // MARK: Gestures

    private func moveGesture(imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                var moved = start
                moved.origin.x = clamp(start.minX + value.translation.width / imageSize.width, 0, 1 - start.width)
                moved.origin.y = clamp(start.minY + value.translation.height / imageSize.height, 0, 1 - start.height)
                crop = moved
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ corner: Corner, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                let dx = value.translation.width / imageSize.width
                let dy = value.translation.height / imageSize.height
                var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
                if corner.isLeading { minX = clamp(minX + dx, 0, maxX - Self.minSize) }
                else { maxX = clamp(maxX + dx, minX + Self.minSize, 1) }
                if corner.isTop { minY = clamp(minY + dy, 0, maxY - Self.minSize) }
                else { maxY = clamp(maxY + dy, minY + Self.minSize, 1) }
                crop = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: Geometry

    /// Where the photo sits when scaled to fit `size`.
    private func fittedFrame(in size: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

    private enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var isLeading: Bool { self == .topLeading || self == .bottomLeading }
        var isTop: Bool { self == .topLeading || self == .topTrailing }

        var name: String {
            switch self {
            case .topLeading: "top left"
            case .topTrailing: "top right"
            case .bottomLeading: "bottom left"
            case .bottomTrailing: "bottom right"
            }
        }

        func point(in r: CGRect) -> CGPoint {
            CGPoint(x: isLeading ? r.minX : r.maxX, y: isTop ? r.minY : r.maxY)
        }
    }
}

extension UIImage {
    /// The part of the photo inside `fraction` (0...1 of the upright width and height), upright.
    func cropped(toFraction fraction: CGRect) -> UIImage {
        // Camera photos are stored sideways with a rotation flag; draw upright first so the
        // crop box (picked on the upright photo) lines up with the pixels.
        let upright: UIImage
        if imageOrientation == .up, cgImage != nil {
            upright = self
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let cg = upright.cgImage else { return self }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let pixels = CGRect(x: fraction.minX * w, y: fraction.minY * h,
                            width: fraction.width * w, height: fraction.height * h).integral
        guard let piece = cg.cropping(to: pixels) else { return self }
        return UIImage(cgImage: piece, scale: upright.scale, orientation: .up)
    }
}
