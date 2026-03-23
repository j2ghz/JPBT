import AVKit
import Photos
import SwiftUI

struct AssetVideoView: View {
  let asset: PHAsset

  @State private var thumbnail: NSImage?
  @State private var player: AVPlayer?

  var body: some View {
    ZStack {
      if let player {
        VideoPlayer(player: player)
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
    .animation(.easeInOut(duration: 0.25), value: player != nil)
    .task(id: asset.localIdentifier) {
      thumbnail = nil
      player = nil
      await loadThumbnail()
      await loadVideo()
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

  private func loadVideo() async {
    let manager = PHImageManager.default()
    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = true

    let playerItem = await withCheckedContinuation {
      (continuation: CheckedContinuation<AVPlayerItem?, Never>) in
      manager.requestPlayerItem(
        forVideo: asset,
        options: options
      ) { item, _ in
        continuation.resume(returning: item)
      }
    }

    if let playerItem {
      player = AVPlayer(playerItem: playerItem)
    }
  }
}
