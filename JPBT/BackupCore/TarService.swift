import Dependencies
import Foundation
import SWCompression

struct TarService: Sendable {
  var pack: @Sendable (_ entries: [(name: String, data: Data)]) throws -> Data
  var unpack: @Sendable (_ archive: Data) throws -> [(name: String, data: Data)]
}

extension TarService: DependencyKey {
  static let liveValue = TarService(
    pack: { entries in
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      FileManager.default.createFile(atPath: url.path, contents: nil)
      defer { try? FileManager.default.removeItem(at: url) }
      let handle = try FileHandle(forWritingTo: url)
      var writer = TarWriter(fileHandle: handle)
      for (name, data) in entries {
        let info = TarEntryInfo(name: name, type: .regular)
        try writer.append(TarEntry(info: info, data: data))
      }
      try writer.finalize()
      try handle.close()
      return try Data(contentsOf: url)
    },
    unpack: { archive in
      try TarContainer.open(container: archive)
        .compactMap { entry -> (name: String, data: Data)? in
          guard let data = entry.data else { return nil }
          return (name: entry.info.name, data: data)
        }
    }
  )
}

extension DependencyValues {
  var tarService: TarService {
    get { self[TarService.self] }
    set { self[TarService.self] = newValue }
  }
}
