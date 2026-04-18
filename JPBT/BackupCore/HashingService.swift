import Dependencies
import Foundation
import xxHash_Swift

struct HashingService: Sendable {
  var hash: @Sendable (_ data: Data) -> String
}

extension HashingService: DependencyKey {
  static let liveValue = HashingService(
    hash: { data in XXH64.digestHex(data) }
  )
}

extension DependencyValues {
  var hashingService: HashingService {
    get { self[HashingService.self] }
    set { self[HashingService.self] = newValue }
  }
}
