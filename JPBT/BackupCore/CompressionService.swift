import Dependencies
import Foundation
import libzstd

enum CompressionError: Error {
  case compressionFailed
  case decompressionFailed
  case unknownOriginalSize
}

struct CompressionService: Sendable {
  var compress: @Sendable (_ data: Data) throws -> Data
  var decompress: @Sendable (_ data: Data) throws -> Data
}

extension CompressionService: DependencyKey {
  static let liveValue = CompressionService(
    compress: { data in
      let bound = ZSTD_compressBound(data.count)
      var output = Data(count: bound)
      let written = output.withUnsafeMutableBytes { dst in
        data.withUnsafeBytes { src in
          ZSTD_compress(dst.baseAddress, dst.count, src.baseAddress, src.count, 3)
        }
      }
      guard ZSTD_isError(written) == 0 else { throw CompressionError.compressionFailed }
      return Data(output.prefix(written))
    },
    decompress: { data in
      let originalSize = data.withUnsafeBytes { src in
        ZSTD_getFrameContentSize(src.baseAddress, src.count)
      }
      guard originalSize != ZSTD_CONTENTSIZE_ERROR,
        originalSize != ZSTD_CONTENTSIZE_UNKNOWN
      else { throw CompressionError.unknownOriginalSize }
      var output = Data(count: Int(originalSize))
      let written = output.withUnsafeMutableBytes { dst in
        data.withUnsafeBytes { src in
          ZSTD_decompress(dst.baseAddress, dst.count, src.baseAddress, src.count)
        }
      }
      guard ZSTD_isError(written) == 0 else { throw CompressionError.decompressionFailed }
      return output
    }
  )
}

extension DependencyValues {
  var compressionService: CompressionService {
    get { self[CompressionService.self] }
    set { self[CompressionService.self] = newValue }
  }
}
