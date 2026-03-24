import Accelerate
import AppKit
import CoreImage

enum FalseColorFilter {

  nonisolated static func apply(to imageData: Data) -> NSImage? {
    guard
      let ciImage = CIImage(
        data: imageData,
        options: [.applyOrientationProperty: true]
      )
    else { return nil }

    let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    let context = CIContext(options: [.workingColorSpace: linearSpace])

    let width = Int(ciImage.extent.width)
    let height = Int(ciImage.extent.height)
    let pixelCount = width * height
    let rowBytes = width * 4 * MemoryLayout<Float>.size

    var buffer = [Float](repeating: 0, count: pixelCount * 4)
    context.render(
      ciImage,
      toBitmap: &buffer,
      rowBytes: rowBytes,
      bounds: ciImage.extent,
      format: .RGBAf,
      colorSpace: linearSpace
    )

    guard !Task.isCancelled else { return nil }

    // Compute luminance per pixel: Rec. 709
    var rChannel = [Float](repeating: 0, count: pixelCount)
    var gChannel = [Float](repeating: 0, count: pixelCount)
    var bChannel = [Float](repeating: 0, count: pixelCount)
    for i in 0..<pixelCount {
      rChannel[i] = buffer[i * 4]
      gChannel[i] = buffer[i * 4 + 1]
      bChannel[i] = buffer[i * 4 + 2]
    }

    var luminance = [Float](repeating: 0, count: pixelCount)
    var rCoeff: Float = 0.2126
    var gCoeff: Float = 0.7152
    var bCoeff: Float = 0.0722
    vDSP_vsma(rChannel, 1, &rCoeff, luminance, 1, &luminance, 1, vDSP_Length(pixelCount))
    vDSP_vsma(gChannel, 1, &gCoeff, luminance, 1, &luminance, 1, vDSP_Length(pixelCount))
    vDSP_vsma(bChannel, 1, &bCoeff, luminance, 1, &luminance, 1, vDSP_Length(pixelCount))

    guard !Task.isCancelled else { return nil }

    // Map luminance to false color RGBA8
    var outputBytes = [UInt8](repeating: 255, count: pixelCount * 4)
    for i in 0..<pixelCount {
      let lum = luminance[i]
      let r: Float
      let g: Float
      let b: Float

      if lum <= 1.0 {
        let v = max(lum, 0)
        r = v
        g = v
        b = v
      } else if lum <= 2.0 {
        let t = lum - 1.0
        r = 0
        g = t
        b = 1
      } else if lum <= 4.0 {
        let t = (lum - 2.0) / 2.0
        r = t
        g = 1
        b = 1 - t
      } else {
        r = 1
        g = 1
        b = 0
      }

      outputBytes[i * 4] = UInt8(min(r * 255, 255))
      outputBytes[i * 4 + 1] = UInt8(min(g * 255, 255))
      outputBytes[i * 4 + 2] = UInt8(min(b * 255, 255))
    }

    guard !Task.isCancelled else { return nil }

    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let providerRef = CGDataProvider(data: Data(outputBytes) as CFData),
      let cgImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: srgb,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: providerRef,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    else { return nil }

    return NSImage(
      cgImage: cgImage,
      size: NSSize(width: width, height: height)
    )
  }
}
