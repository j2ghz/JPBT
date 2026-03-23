//
//  AssetInfoView.swift
//  JPBT
//

import Photos
import SwiftUI

struct AssetInfoView: View {
  let asset: PHAsset

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
    }
    .listStyle(.inset)
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
}
