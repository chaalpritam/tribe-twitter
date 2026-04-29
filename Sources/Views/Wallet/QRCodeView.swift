import SwiftUI
import CoreImage.CIFilterBuiltins

/// Renders a QR encoding `value`. Uses Core Image's CIQRCodeGenerator
/// so we don't need a third-party dependency.
struct QRCodeView: View {
    let value: String
    var size: CGFloat = 240

    private static let context = CIContext()
    private static let generator = CIFilter.qrCodeGenerator()

    var body: some View {
        if let image = makeImage() {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(TribeColor.chipBackground)
                .frame(width: size, height: size)
                .overlay(
                    Text("QR unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(TribeColor.textSecondary)
                )
        }
    }

    private func makeImage() -> UIImage? {
        Self.generator.message = Data(value.utf8)
        Self.generator.correctionLevel = "M"
        guard let output = Self.generator.outputImage else { return nil }
        // Scale up so the QR is crisp at the requested point size.
        let scale = (size * UIScreen.main.scale) / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = Self.context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
