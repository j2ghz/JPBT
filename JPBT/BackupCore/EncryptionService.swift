import CryptoKit
import Dependencies
import Foundation

enum EncryptionError: Error {
  case encryptionFailed
  case decryptionFailed
  case invalidData
}

struct EncryptionService: Sendable {
  // Blob format: nonce (12B) || ciphertext || tag (16B)
  var encrypt: @Sendable (_ data: Data, _ key: SymmetricKey) throws -> Data
  var decrypt: @Sendable (_ data: Data, _ key: SymmetricKey) throws -> Data
}

extension EncryptionService: DependencyKey {
  static let liveValue = EncryptionService(
    encrypt: { data, key in
      let nonce = AES.GCM.Nonce()
      let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
      // combined = nonce (12B) || ciphertext || tag (16B)
      guard let combined = sealedBox.combined else { throw EncryptionError.encryptionFailed }
      return combined
    },
    decrypt: { data, key in
      guard data.count >= 28 else { throw EncryptionError.invalidData }
      let sealedBox = try AES.GCM.SealedBox(combined: data)
      return try AES.GCM.open(sealedBox, using: key)
    }
  )
}

extension DependencyValues {
  var encryptionService: EncryptionService {
    get { self[EncryptionService.self] }
    set { self[EncryptionService.self] = newValue }
  }
}
