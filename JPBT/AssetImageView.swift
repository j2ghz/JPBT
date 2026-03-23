import Photos
import PhotosUI
import SwiftUI

struct AssetImageView: View {
  let asset: PHAsset

  @State private var thumbnail: NSImage?
  @State private var fullImage: NSImage?
  @State private var livePhoto: PHLivePhoto?

  private var isLivePhoto: Bool {
    asset.mediaSubtypes.contains(.photoLive)
  }

  var body: some View {
    ZStack {
      if isLivePhoto, let livePhoto {
        LivePhotoRepresentable(livePhoto: livePhoto)
          .transition(.opacity)
      } else if let fullImage {
        Image(nsImage: fullImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .transition(.opacity)
      } else if let thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .overlay {
            ProgressView()
              .controlSize(.large)
          }
          .transition(.opacity)
      } else {
        ProgressView()
          .controlSize(.large)
      }
    }
    .animation(.easeInOut(duration: 0.25), value: thumbnail != nil)
    .animation(.easeInOut(duration: 0.25), value: fullImage != nil)
    .animation(.easeInOut(duration: 0.25), value: livePhoto != nil)
    .task(id: asset.localIdentifier) {
      thumbnail = nil
      fullImage = nil
      livePhoto = nil
      await loadThumbnail()
      if isLivePhoto {
        await loadLivePhoto()
      } else {
        await loadFullImage()
      }
    }
  }

  private func loadThumbnail() async {
    let manager = PHImageManager.default()
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .fastFormat
    options.resizeMode = .fast

    let size = CGSize(width: 400, height: 400)

    thumbnail = await withCheckedContinuation { continuation in
      manager.requestImage(
        for: asset,
        targetSize: size,
        contentMode: .aspectFit,
        options: options
      ) { result, _ in
        continuation.resume(returning: result)
      }
    }
  }

  private func loadFullImage() async {
    let manager = PHImageManager.default()
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat

    let size = CGSize(
      width: CGFloat(asset.pixelWidth),
      height: CGFloat(asset.pixelHeight)
    )

    fullImage = await withCheckedContinuation { continuation in
      manager.requestImage(
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

struct LivePhotoRepresentable: NSViewRepresentable {
  let livePhoto: PHLivePhoto

  func makeNSView(context: Context) -> PHLivePhotoView {
    PHLivePhotoView()
  }

  func updateNSView(_ nsView: PHLivePhotoView, context: Context) {
    nsView.livePhoto = livePhoto
  }
}

