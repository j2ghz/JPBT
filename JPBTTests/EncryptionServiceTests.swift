import CryptoKit
import Foundation
import Testing

@testable import JPBT

@Suite struct EncryptionServiceTests {
  let service = EncryptionService.liveValue
  let key = SymmetricKey(size: .bits256)

  @Test func roundTrip() throws {
    let original = Data("Secret message for testing encryption.".utf8)
    let encrypted = try service.encrypt(original, key)
    let decrypted = try service.decrypt(encrypted, key)
    #expect(decrypted == original)
  }

  @Test func encryptedDiffersFromPlaintext() throws {
    let original = Data("hello world".utf8)
    let encrypted = try service.encrypt(original, key)
    #expect(encrypted != original)
  }

  @Test func encryptedHasNonceAndTag() throws {
    let original = Data("hello".utf8)
    let encrypted = try service.encrypt(original, key)
    // nonce (12) + data + tag (16) = at least 28 bytes more than data
    #expect(encrypted.count == original.count + 12 + 16)
  }

  @Test func wrongKeyFails() throws {
    let original = Data("hello world".utf8)
    let encrypted = try service.encrypt(original, key)
    let wrongKey = SymmetricKey(size: .bits256)
    #expect(throws: (any Error).self) {
      try service.decrypt(encrypted, wrongKey)
    }
  }

  @Test func emptyDataRoundTrip() throws {
    let original = Data()
    let encrypted = try service.encrypt(original, key)
    let decrypted = try service.decrypt(encrypted, key)
    #expect(decrypted == original)
  }

  @Test func nonceIsRandomEachEncrypt() throws {
    let original = Data("same data".utf8)
    let e1 = try service.encrypt(original, key)
    let e2 = try service.encrypt(original, key)
    #expect(e1 != e2)
  }
}
