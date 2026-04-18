import Foundation
import Testing

@testable import JPBT

@Suite struct HashingServiceTests {
  let service = HashingService.liveValue

  @Test func deterministicOutput() {
    let data = Data("hello".utf8)
    let h1 = service.hash(data)
    let h2 = service.hash(data)
    #expect(h1 == h2)
  }

  @Test func outputIs16HexChars() {
    let hash = service.hash(Data("test".utf8))
    #expect(hash.count == 16)
    #expect(hash.allSatisfy({ $0.isHexDigit }))
  }

  @Test func differentDataProducesDifferentHash() {
    let h1 = service.hash(Data("foo".utf8))
    let h2 = service.hash(Data("bar".utf8))
    #expect(h1 != h2)
  }

  @Test func emptyData() {
    let hash = service.hash(Data())
    #expect(hash.count == 16)
  }

  @Test func knownVector() {
    // XXH64("") with seed 0 = ef46db3751d8e999
    let hash = service.hash(Data())
    #expect(hash == "ef46db3751d8e999")
  }
}
