//
//  AssetInfoView.swift
//  JPBT
//

import Accelerate
import CoreImage
import Photos
import SwiftUI

struct AssetInfoView: View {
  let asset: PHAsset

  @State private var peakBrightness: Double?
  @State private var isAnalyzing = false

  var body: some View {
    List {
      Section("Media") {
        LabeledContent("Type", value: mediaTypeName)
        if !mediaSubtypeNames.isEmpty {
          LabeledContent("Subtypes", value: mediaSubtypeNames.joined(separator: ", "))
        }
        LabeledContent("Dimensions", value: "\(asset.pixelWidth) × \(asset.pixelHeight)")
        if asset.duration > 0 {
          LabeledContent("Duration", value: String(format: "%.3f s", asset.duration))
        }
        LabeledContent("Playback Style", value: playbackStyleName)
      }

      let resources = PHAssetResource.assetResources(for: asset)
      if !resources.isEmpty {
        Section("Resources") {
          ForEach(resources, id: \.originalFilename) { resource in
            VStack(alignment: .leading, spacing: 4) {
              LabeledContent("Type", value: resourceTypeName(resource.type))
              LabeledContent("Filename", value: resource.originalFilename)
              LabeledContent("UTI", value: resource.uniformTypeIdentifier)
            }
            .padding(.vertical, 2)
          }
        }
      }

      Section("Metadata") {
        LabeledContent("Identifier", value: asset.localIdentifier)
        LabeledContent("Source", value: sourceTypeName)
        if let date = asset.creationDate {
          LabeledContent("Created", value: date.formatted(date: .abbreviated, time: .standard))
        }
        if let date = asset.modificationDate {
          LabeledContent("Modified", value: date.formatted(date: .abbreviated, time: .standard))
        }
        LabeledContent("Favorite", value: asset.isFavorite ? "Yes" : "No")
        LabeledContent("Hidden", value: asset.isHidden ? "Yes" : "No")
        if asset.representsBurst, let burstId = asset.burstIdentifier {
          LabeledContent("Burst ID", value: burstId)
        }
        if let location = asset.location {
          let coord = location.coordinate
          LabeledContent(
            "Location",
            value: String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
          LabeledContent("Altitude", value: String(format: "%.1f m", location.altitude))
        }
      }

      if asset.mediaType == .image {
        Section("Analysis") {
          if let peakBrightness {
            LabeledContent("Peak Brightness", value: String(format: "%.1f%%", peakBrightness * 100))
          } else if isAnalyzing {
            LabeledContent("Peak Brightness") {
              ProgressView()
                .controlSize(.small)
            }
          }
        }
      }
    }
    .listStyle(.inset)
    .task(id: asset.localIdentifier) {
      peakBrightness = nil
      guard asset.mediaType == .image else { return }
      isAnalyzing = true
      let result = await computePeakBrightness()
      guard !Task.isCancelled else { return }
      peakBrightness = result
      isAnalyzing = false
    }
  }

  private var mediaTypeName: String {
    switch asset.mediaType {
    case .image: return "Image"
    case .video: return "Video"
    case .audio: return "Audio"
    case .unknown: return "Unknown"
    @unknown default: return "Unknown (\(asset.mediaType.rawValue))"
    }
  }

  private var mediaSubtypeNames: [String] {
    var names: [String] = []
    let s = asset.mediaSubtypes
    if s.contains(.photoLive) { names.append("Live Photo") }
    if s.contains(.photoHDR) { names.append("HDR") }
    if s.contains(.photoPanorama) { names.append("Panorama") }
    if s.contains(.photoScreenshot) { names.append("Screenshot") }
    if s.contains(.photoDepthEffect) { names.append("Depth Effect") }
    if s.contains(.videoCinematic) { names.append("Cinematic") }
    if s.contains(.videoHighFrameRate) { names.append("High Frame Rate") }
    if s.contains(.videoTimelapse) { names.append("Timelapse") }
    if s.contains(.videoStreamed) { names.append("Streamed") }
    return names
  }

  private var playbackStyleName: String {
    switch asset.playbackStyle {
    case .unsupported: return "Unsupported"
    case .image: return "Image"
    case .imageAnimated: return "Animated Image"
    case .livePhoto: return "Live Photo"
    case .video: return "Video"
    case .videoLooping: return "Looping Video"
    @unknown default: return "Unknown (\(asset.playbackStyle.rawValue))"
    }
  }

  private var sourceTypeName: String {
    switch asset.sourceType {
    case .typeUserLibrary: return "User Library"
    case .typeCloudShared: return "Cloud Shared"
    case .typeiTunesSynced: return "iTunes Synced"
    default: return "Unknown (\(asset.sourceType.rawValue))"
    }
  }

  private func resourceTypeName(_ type: PHAssetResourceType) -> String {
    switch type {
    case .photo: return "Photo"
    case .video: return "Video"
    case .audio: return "Audio"
    case .alternatePhoto: return "Alternate Photo"
    case .fullSizePhoto: return "Full Size Photo"
    case .fullSizeVideo: return "Full Size Video"
    case .adjustmentData: return "Adjustment Data"
    case .adjustmentBasePhoto: return "Adjustment Base Photo"
    case .pairedVideo: return "Paired Video"
    case .fullSizePairedVideo: return "Full Size Paired Video"
    case .adjustmentBasePairedVideo: return "Adjustment Base Paired Video"
    case .adjustmentBaseVideo: return "Adjustment Base Video"
    case .photoProxy: return "Photo Proxy"
    @unknown default: return "Unknown (\(type.rawValue))"
    }
  }

  // MARK: - Analysis

  private func computePeakBrightness() async -> Double? {
    guard let imageData = await requestImageData() else { return nil }
    guard !Task.isCancelled else { return nil }

    // Use Task.detached to run CPU-heavy work on its own thread, outside the cooperative pool.
    // withTaskCancellationHandler propagates cancellation from the structured parent task.
    let work = Task.detached(priority: .userInitiated) {
      Self.analyzePeakBrightness(imageData: imageData)
    }

    return await withTaskCancellationHandler {
      await work.value
    } onCancel: {
      work.cancel()
    }
  }

  private nonisolated static func analyzePeakBrightness(imageData: Data) -> Double? {
    guard let ciImage = CIImage(data: imageData, options: [.applyOrientationProperty: true])
    else { return nil }

    let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    let context = CIContext(options: [.workingColorSpace: linearSpace])

    let width = Int(ciImage.extent.width)
    let height = Int(ciImage.extent.height)
    let rowBytes = width * 4 * MemoryLayout<Float>.size

    var buffer = [Float](repeating: 0, count: width * height * 4)
    context.render(
      ciImage,
      toBitmap: &buffer,
      rowBytes: rowBytes,
      bounds: ciImage.extent,
      format: .RGBAf,
      colorSpace: linearSpace
    )

    guard !Task.isCancelled else { return nil }

    let pixelCount = width * height

    var rChannel = [Float](repeating: 0, count: pixelCount)
    var gChannel = [Float](repeating: 0, count: pixelCount)
    var bChannel = [Float](repeating: 0, count: pixelCount)
    for i in 0..<pixelCount {
      rChannel[i] = buffer[i * 4]
      gChannel[i] = buffer[i * 4 + 1]
      bChannel[i] = buffer[i * 4 + 2]
    }

    // Rec. 709: Y = 0.2126 R + 0.7152 G + 0.0722 B
    var luminance = [Float](repeating: 0, count: pixelCount)
    var rCoeff: Float = 0.2126
    var gCoeff: Float = 0.7152
    var bCoeff: Float = 0.0722
    vDSP_vsma(rChannel, 1, &rCoeff, luminance, 1, &luminance, 1, vDSP_Length(pixelCount))
    vDSP_vsma(gChannel, 1, &gCoeff, luminance, 1, &luminance, 1, vDSP_Length(pixelCount))
    vDSP_vsma(bChannel, 1, &bCoeff, luminance, 1, &luminance, 1, vDSP_Length(pixelCount))

    guard !Task.isCancelled else { return nil }

    var peak: Float = 0
    vDSP_maxv(luminance, 1, &peak, vDSP_Length(pixelCount))

    return Double(peak)
  }

  private func requestImageData() async -> Data? {
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
}
