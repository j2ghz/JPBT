import Accelerate
import AppKit
import CoreImage

enum FalseColorFilter {

  nonisolated static func apply(to imageData: Data) -> NSImage? {
    guard
      let ciImage = CIImage(
        data: imageData,
        options: [
          .applyOrientationProperty: true,
          .expandToHDR: true,
        ]
      )
    else { return nil }

    let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    let context = CIContext(options: [
      .workingColorSpace: linearSpace,
      .workingFormat: NSNumber(value: CIFormat.RGBAh.rawValue),
    ])

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

    // Map pixels to false color RGBA8
    // SDR (lum ≤ 1.0): grayscale
    // HDR bands by stops above SDR white:
    //   0–1 stops (lum 1–2):  Blue
    //   1–2 stops (lum 2–4):  Cyan
    //   2–3 stops (lum 4–8):  Green
    //   3–4 stops (lum 8–16): Yellow
    //   4+ stops  (lum > 16): Red
    var outputBytes = [UInt8](repeating: 255, count: pixelCount * 4)
    for i in 0..<pixelCount {
      let r = buffer[i * 4]
      let g = buffer[i * 4 + 1]
      let b = buffer[i * 4 + 2]
      let a = buffer[i * 4 + 3]

      // Unpremultiply
      let ur: Float
      let ug: Float
      let ub: Float
      if a > 0 {
        ur = r / a
        ug = g / a
        ub = b / a
      } else {
        ur = 0
        ug = 0
        ub = 0
      }

      let lum = 0.2126 * ur + 0.7152 * ug + 0.0722 * ub
      let stops = lum > 0 ? log2(lum) : -Float.infinity

      let outR: Float
      let outG: Float
      let outB: Float
      if lum <= 1.0 {
        let v = max(lum, 0)
        outR = v
        outG = v
        outB = v
      } else if stops <= 1 {
        outR = 0.66; outG = 1; outB = 1
      } else if stops <= 2 {
        outR = 0.4; outG = 0.6; outB = 1
      } else if stops <= 3 {
        outR = 0.5; outG = 0.1; outB = 1
      } else {
        outR = 0.8; outG = 0.2; outB = 1
      }

      outputBytes[i * 4] = UInt8(outR * 255)
      outputBytes[i * 4 + 1] = UInt8(outG * 255)
      outputBytes[i * 4 + 2] = UInt8(outB * 255)
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
