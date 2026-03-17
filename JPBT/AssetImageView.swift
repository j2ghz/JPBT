import SwiftUI
import Photos
import PhotosUI

struct AssetImageView: View {
    let asset: PHAsset

    @State private var livePhoto: PHLivePhoto?

    var body: some View {
        Group {
            if let livePhoto {
                LivePhotoRepresentable(livePhoto: livePhoto)
            } else {
                ProgressView()
            }
        }
        .task(id: asset.localIdentifier) {
            await loadLivePhoto()
        }
    }

    private func loadLivePhoto() async {
        let manager = PHImageManager.default()
        let options = PHLivePhotoRequestOptions()
        options.isNetworkAccessAllowed = true

        let size = CGSize(
            width: CGFloat(asset.pixelWidth),
            height: CGFloat(asset.pixelHeight)
        )

        livePhoto = await withCheckedContinuation { continuation in
            manager.requestLivePhoto(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: options
            ) { result, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: result)
                }
            }
        }
    }
}

// MARK: - Live Photo View Representable

#if canImport(UIKit)
struct LivePhotoRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
    }
}
#elseif canImport(AppKit)
struct LivePhotoRepresentable: NSViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeNSView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        return view
    }

    func updateNSView(_ nsView: PHLivePhotoView, context: Context) {
        nsView.livePhoto = livePhoto
    }
}
#endif

