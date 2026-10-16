import SwiftUI
import CoreImage.CIFilterBuiltins

// Folia/Features/QRCodeView.swift — locally generated authorization QR with system sharing.
struct QRCodeView: View {
    let url: URL
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    var body: some View {
        if let image {
            VStack(spacing: 16) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 240).padding(16).background(.white)
                    .accessibilityLabel(localized("登录授权二维码", "Sign-in authorization QR"))
                ShareLink(item: Image(uiImage: image), preview: SharePreview(localized("登录二维码", "Sign-in QR"), image: Image(uiImage: image))) {
                    Label(localized("分享二维码图片", "Share QR image"), systemImage: "square.and.arrow.up")
                }
                Text(localized("可分享二维码图片后在对应平台识别；能否同机授权取决于平台。", "Share this QR image for recognition in the provider app. Same-device authorization depends on the provider.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
