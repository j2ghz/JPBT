import Photos
import SwiftUI

struct ContentView: View {
  @State private var photoAssets: [PHAsset] = []
  @State private var selectedAssetID: String?
  @State private var showInspector = true

  private var selectedAsset: PHAsset? {
    photoAssets.first { $0.localIdentifier == selectedAssetID }
  }

  var body: some View {
    NavigationSplitView {
      List(photoAssets, id: \.localIdentifier, selection: $selectedAssetID) { asset in
        Label {
          if let date = asset.creationDate {
            Text(date, format: Date.FormatStyle(date: .numeric, time: .standard))
          } else {
            Text(asset.localIdentifier)
          }
        } icon: {
          Image(systemName: asset.mediaType == .video ? "video" : "photo")
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200)
      .toolbar {
        ToolbarItem {
          Button {
            showInspector.toggle()
          } label: {
            Label("Toggle Inspector", systemImage: "sidebar.trailing")
          }
        }
      }
    } detail: {
      if let asset = selectedAsset {
        Group {
          if asset.mediaType == .image {
            AssetImageView(asset: asset)
          } else if asset.mediaType == .video {
            AssetVideoView(asset: asset)
          } else {
            Text("Unsupported asset type")
          }
        }
        .id(asset.localIdentifier)
        .inspector(isPresented: $showInspector) {
          AssetInfoView(asset: asset)
            .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
      } else {
        Text("Select an item")
      }
    }
    .task {
      await loadAssets()
    }
  }

  private func loadAssets() async {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard status == .authorized || status == .limited else { return }

    let fetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    fetchOptions.fetchLimit = 100
    let results = PHAsset.fetchAssets(with: fetchOptions)

    var assets: [PHAsset] = []
    results.enumerateObjects { asset, _, _ in
      assets.append(asset)
    }
    photoAssets = assets
  }
}

#Preview {
  ContentView()
}
