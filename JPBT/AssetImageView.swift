import CoreImage
import Photos
import PhotosUI
import SwiftUI

final class PixelSampler: Sendable {
  let ciImage: CIImage
  let context: CIContext

  nonisolated init(imageData: Data) throws {
    guard
      let image = CIImage(
        data: imageData,
        options: [
          .applyOrientationProperty: true,
          .expandToHDR: true,
        ]
      )
    else {
      throw PixelSamplerError.invalidData
    }
    self.ciImage = image
    let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    self.context = CIContext(options: [
      .workingColorSpace: linearSpace,
      .workingFormat: NSNumber(value: CIFormat.RGBAh.rawValue),
    ])
  }

  func sample(atX x: Int, y: Int) -> PixelInfo? {
    let flippedY = Int(ciImage.extent.height) - 1 - y
    let rect = CGRect(x: x, y: flippedY, width: 1, height: 1)
    guard ciImage.extent.contains(rect.origin) else { return nil }

    let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    var pixel = [Float](repeating: 0, count: 4)
    context.render(
      ciImage,
      toBitmap: &pixel,
      rowBytes: 4 * MemoryLayout<Float>.size,
      bounds: rect,
      format: .RGBAf,
      colorSpace: linearSpace
    )

    let a = pixel[3]
    let r: Float
    let g: Float
    let b: Float
    if a > 0 {
      r = pixel[0] / a
      g = pixel[1] / a
      b = pixel[2] / a
    } else {
      r = 0
      g = 0
      b = 0
    }
    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return PixelInfo(r: r, g: g, b: b, luminance: luminance)
  }

  enum PixelSamplerError: Error {
    case invalidData
  }
}

struct AssetImageView: View {
  let asset: PHAsset
  @Binding var showFalseColor: Bool
  @Binding var cursorPixelInfo: PixelInfo?

  @State private var thumbnail: NSImage?
  @State private var fullImage: NSImage?
  @State private var livePhoto: PHLivePhoto?
  @State private var falseColorImage: NSImage?
  @State private var isComputingFalseColor = false
  @State private var pixelSampler: PixelSampler?

  private var isLivePhoto: Bool {
    asset.mediaSubtypes.contains(.photoLive)
  }

  private var displayImage: NSImage? {
    fullImage
  }

  var body: some View {
    GeometryReader { geometry in
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
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          samplePixel(at: location, viewSize: geometry.size)
        case .ended:
          cursorPixelInfo = nil
        }
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
      pixelSampler = nil
      cursorPixelInfo = nil
      await loadThumbnail()
      if isLivePhoto {
        await loadLivePhoto()
      } else {
        await loadFullImage()
      }
      await loadPixelSampler()
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

  private func loadPixelSampler() async {
    let currentAsset = asset
    let sampler = await Task.detached(priority: .utility) {
      guard let data = await Self.requestImageData(for: currentAsset) else {
        return nil as PixelSampler?
      }
      return try? PixelSampler(imageData: data)
    }.value
    guard !Task.isCancelled else { return }
    pixelSampler = sampler
  }

  private func samplePixel(at location: CGPoint, viewSize: CGSize) {
    guard let sampler = pixelSampler else {
      cursorPixelInfo = nil
      return
    }

    let imageWidth = sampler.ciImage.extent.width
    let imageHeight = sampler.ciImage.extent.height

    let imageAspect = imageWidth / imageHeight
    let viewAspect = viewSize.width / viewSize.height

    let renderedWidth: CGFloat
    let renderedHeight: CGFloat
    if imageAspect > viewAspect {
      renderedWidth = viewSize.width
      renderedHeight = viewSize.width / imageAspect
    } else {
      renderedHeight = viewSize.height
      renderedWidth = viewSize.height * imageAspect
    }

    let offsetX = (viewSize.width - renderedWidth) / 2
    let offsetY = (viewSize.height - renderedHeight) / 2

    let relX = (location.x - offsetX) / renderedWidth
    let relY = (location.y - offsetY) / renderedHeight

    guard relX >= 0, relX < 1, relY >= 0, relY < 1 else {
      cursorPixelInfo = nil
      return
    }

    let pixelX = Int(relX * imageWidth)
    let pixelY = Int(relY * imageHeight)
    cursorPixelInfo = sampler.sample(atX: pixelX, y: pixelY)
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
