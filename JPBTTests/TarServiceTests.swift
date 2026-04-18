import Foundation
import Testing

@testable import JPBT

@Suite struct TarServiceTests {
  let service = TarService.liveValue

  @Test func singleFileRoundTrip() throws {
    let entries: [(name: String, data: Data)] = [
      ("photo.heic", Data("fake heic bytes".utf8))
    ]
    let archive = try service.pack(entries)
    let unpacked = try service.unpack(archive)
    #expect(unpacked.count == 1)
    #expect(unpacked[0].name == "photo.heic")
    #expect(unpacked[0].data == entries[0].data)
  }

  @Test func multipleFilesRoundTrip() throws {
    let entries: [(name: String, data: Data)] = [
      ("photo.heic", Data(repeating: 0x01, count: 1024)),
      ("photo.mov", Data(repeating: 0x02, count: 2048)),
      ("adjustments.plist", Data("plist data".utf8)),
    ]
    let archive = try service.pack(entries)
    let unpacked = try service.unpack(archive)
    #expect(unpacked.count == 3)
    for (i, entry) in unpacked.enumerated() {
      #expect(entry.name == entries[i].name)
      #expect(entry.data == entries[i].data)
    }
  }

  @Test func emptyArchive() throws {
    let archive = try service.pack([])
    let unpacked = try service.unpack(archive)
    #expect(unpacked.isEmpty)
  }

  @Test func dataSizeNotMultipleOf512() throws {
    // Test that padding is handled correctly for non-block-aligned sizes
    let entries: [(name: String, data: Data)] = [
      ("a.bin", Data(repeating: 0xAB, count: 513)),
      ("b.bin", Data(repeating: 0xCD, count: 1)),
    ]
    let archive = try service.pack(entries)
    let unpacked = try service.unpack(archive)
    #expect(unpacked.count == 2)
    #expect(unpacked[0].data == entries[0].data)
    #expect(unpacked[1].data == entries[1].data)
  }

  @Test func archiveIsPaddedToBlockBoundary() throws {
    let entries: [(name: String, data: Data)] = [
      ("test.bin", Data(count: 100))
    ]
    let archive = try service.pack(entries)
    // Archive size must be a multiple of 512
    #expect(archive.count % 512 == 0)
  }
}
