import Photos
import PhotosUI
import SwiftUI

struct AssetImageView: View {
  let asset: PHAsset
  @Binding var showFalseColor: Bool

  @State private var thumbnail: NSImage?
  @State private var fullImage: NSImage?
  @State private var livePhoto: PHLivePhoto?
  @State private var falseColorImage: NSImage?
  @State private var isComputingFalseColor = false

  private var isLivePhoto: Bool {
    asset.mediaSubtypes.contains(.photoLive)
  }

  private var displayImage: NSImage? {
    fullImage
  }

  var body: some View {
    ZStack {
      if showFalseColor, let falseColorImage {
        Image(nsImage: falseColorImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .transition(.opacity)
      } else if isLivePhoto, let livePhoto {
        LivePhotoRepresentable(livePhoto: livePhoto)
          .transition(.opacity)
      } else if let displayImage {
        Image(nsImage: displayImage)
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

      if isComputingFalseColor {
        ProgressView()
          .controlSize(.large)
      }
    }
    .animation(.easeInOut(duration: 0.25), value: thumbnail != nil)
    .animation(.easeInOut(duration: 0.25), value: fullImage != nil)
    .animation(.easeInOut(duration: 0.25), value: livePhoto != nil)
    .animation(.easeInOut(duration: 0.25), value: falseColorImage != nil)
    .task(id: asset.localIdentifier) {
      thumbnail = nil
      fullImage = nil
      livePhoto = nil
      falseColorImage = nil
      await loadThumbnail()
      if isLivePhoto {
        await loadLivePhoto()
      } else {
        await loadFullImage()
      }
    }
    .task(id: showFalseColor) {
      guard showFalseColor else {
        falseColorImage = nil
        return
      }
      if falseColorImage == nil {
        await loadFalseColorImage()
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

  private func loadFalseColorImage() async {
    isComputingFalseColor = true
    defer { isComputingFalseColor = false }

    let currentAsset = asset
    let work = Task.detached(priority: .userInitiated) {
      guard let data = await Self.requestImageData(for: currentAsset) else {
        return nil as NSImage?
      }
      guard !Task.isCancelled else { return nil as NSImage? }
      return FalseColorFilter.apply(to: data)
    }

    let result = await withTaskCancellationHandler {
      await work.value
    } onCancel: {
      work.cancel()
    }

    guard !Task.isCancelled else { return }
    falseColorImage = result
  }

  private nonisolated static func requestImageData(for asset: PHAsset) async -> Data? {
    let manager = PHImageManager.default()
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat

    return await withCheckedContinuation { continuation in
      manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
        continuation.resume(returning: data)
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
