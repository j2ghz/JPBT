import SwiftUI
import Photos
import AVKit

struct AssetVideoView: View {
    let asset: PHAsset

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        }
        .task(id: asset.localIdentifier) {
            await loadVideo()
        }
    }

    private func loadVideo() async {
        let manager = PHImageManager.default()
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true

        let playerItem = await withCheckedContinuation { (continuation: CheckedContinuation<AVPlayerItem?, Never>) in
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
