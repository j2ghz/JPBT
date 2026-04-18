import Foundation
import Testing

@testable import JPBT

@Suite struct CompressionServiceTests {
  let service = CompressionService.liveValue

  @Test func roundTrip() throws {
    let original = Data("Hello, world! This is test data for compression.".utf8)
    let compressed = try service.compress(original)
    let decompressed = try service.decompress(compressed)
    #expect(decompressed == original)
  }

  @Test func compressedSmallerForRepetitiveData() throws {
    let repetitive = Data(repeating: 0x42, count: 10_000)
    let compressed = try service.compress(repetitive)
    #expect(compressed.count < repetitive.count)
  }

  @Test func emptyDataRoundTrip() throws {
    let original = Data()
    let compressed = try service.compress(original)
    let decompressed = try service.decompress(compressed)
    #expect(decompressed == original)
  }

  @Test func largeDataRoundTrip() throws {
    var original = Data()
    for i in 0..<1000 {
      original.append(contentsOf: "line \(i): some content here\n".utf8)
    }
    let compressed = try service.compress(original)
    let decompressed = try service.decompress(compressed)
    #expect(decompressed == original)
  }
}
