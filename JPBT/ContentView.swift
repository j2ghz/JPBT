//
//  ContentView.swift
//  JPBT
//
//  Created by Jozef Hollý on 17/03/2026.
//

import SwiftUI
import SwiftData
import Photos
import PhotosUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
//    @Query private var items: [Item]
    @State private var photoAssets: [PHAsset] = []

    var body: some View {
        NavigationSplitView {
            List {
//                if !photoAssets.isEmpty {
                    ForEach(photoAssets, id: \.localIdentifier) { asset in
                        NavigationLink {
                            if asset.mediaType == .image {
                                AssetImageView(asset: asset)
                            } else if asset.mediaType == .video {
                                AssetVideoView(asset: asset)
                            } else {
                                Text("Unsupported asset type")
                            }
                        } label: {
                            if let date = asset.creationDate {
                                Text(date, format: Date.FormatStyle(date: .numeric, time: .standard))
                            } else {
                                Text(asset.localIdentifier)
                            }
                        }
                    }
//                } else {
//                    ForEach(items) { item in
//                        NavigationLink {
//                            Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
//                        } label: {
//                            Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
//                        }
//                    }
//                    .onDelete(perform: deleteItems)
//                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
//                    Button(action: addItem) {
//                        Label("Add Item", systemImage: "plus")
//                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
        .task {
            requestPhotoAuthorization()
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
//            for index in offsets {
////                modelContext.delete(items[index])
//            }
        }
    }

    private func requestPhotoAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            print("Status \(status)")
            switch status {
            case .limited, .authorized:
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
//                fetchOptions.fetchLimit = 10
                let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
//                var infos: [PhotoAssetInfo] = []
                for index in 0..<assets.count {
                    let asset = assets.object(at: index)
//                    infos.append(PhotoAssetInfo(id: asset.localIdentifier, creationDate: asset.creationDate, mediaType: asset.mediaType))
                    
                    DispatchQueue.main.async {
                    
                        self.photoAssets.append(asset)
                    }
                }
            case .notDetermined, .denied, .restricted:
                return
            @unknown default:
                return
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}

