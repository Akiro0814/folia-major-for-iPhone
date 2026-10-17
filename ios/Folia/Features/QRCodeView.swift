import SwiftUI
import CoreImage.CIFilterBuiltins

// Folia/Features/QRCodeView.swift — provider image or locally encoded QR, with native image sharing.
struct QRCodeView: View {
    let url: URL
    var imageURL: URL? = nil
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    private var embeddedImage: UIImage? {
        guard let imageURL, imageURL.scheme == "data", imageURL.absoluteString.count < 5_000_000,
              let payload = imageURL.absoluteString.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(payload)) else { return nil }
        return UIImage(data: data)
    }
    var body: some View {
        if let embeddedImage { content(Image(uiImage: embeddedImage)) }
        else if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image): content(image)
                case .failure: Text(localized("二维码加载失败，请重新生成", "QR image failed to load. Generate again."))
                default: ProgressView()
                }
            }
        } else if let image { content(Image(uiImage: image)) }
    }
    private func content(_ image: Image) -> some View {
        VStack(spacing: 16) {
            image.interpolation(.none).resizable().scaledToFit().frame(maxWidth: 240).padding(16).background(.white)
                .accessibilityLabel(localized("登录授权二维码", "Sign-in authorization QR"))
            ShareLink(item: image, preview: SharePreview(localized("登录二维码", "Sign-in QR"), image: image)) {
                Label(localized("分享二维码图片", "Share QR image"), systemImage: "square.and.arrow.up")
            }
            Text(localized("可分享二维码图片后在对应平台识别；能否同机授权取决于平台。", "Share this QR image for recognition in the provider app. Same-device authorization depends on the provider.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

