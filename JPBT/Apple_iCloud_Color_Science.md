# Correct HDR false color analysis on macOS

**SDR white maps to exactly 1.0 in Core Image's extended linear working space**, making the SDR/HDR boundary a simple luminance threshold. When you load an iPhone HDR photo with `.expandToHDR: true` and render through a `CIColorKernel`, every pixel arrives as a linear-light, premultiplied float4 in extended linear sRGB — values below 1.0 are SDR, values above are HDR headroom. The critical chain is: fetch raw HEIC bytes via PhotoKit's `requestImageDataAndOrientation`, create a `CIImage` with the `.expandToHDR` option, process through a Metal-based `CIColorKernel` that computes luminance with Rec. 709 coefficients and maps the result to either greyscale (SDR) or a heat-map (HDR), and render to a float16 texture. Getting any link in this chain wrong — using the wrong request API, omitting the expand option, rendering to 8-bit, or computing luminance from gamma-encoded values — silently destroys the HDR data.

## How macOS represents HDR through EDR

Apple's Extended Dynamic Range (EDR) system is a floating-point, SDR-relative representation. **SDR reference white is always 1.0.** Values above 1.0 represent brightness exceeding SDR white — the "headroom." A value of 3.0 means three times as bright as SDR white. The system is display-referred but relative: it tracks the user's brightness setting rather than encoding absolute nits like PQ.

The available headroom is dynamic. `NSScreen.maximumExtendedDynamicRangeColorComponentValue` returns the current renderable maximum, which changes as display brightness changes. When the user dims the screen, macOS keeps the backlight higher than needed for SDR white, creating more headroom for HDR pixels. Typical values: **up to 2× on conventional MacBooks**, **3.2× on Pro Display XDR at 500-nit reference white** (1600/500), and **up to 8× on iPhone XDR displays**. The static property `maximumPotentialExtendedDynamicRangeColorComponentValue` reports the display's peak capability regardless of current brightness.

ImageIO decodes HLG images to **0.0–12.0 EDR range** and PQ images with 100 nits mapped to EDR 1.0. For iPhone gain-map photos loaded with `.expandToHDR`, the resulting pixel values range from 0.0 up to the image's headroom value (typically 2–8 for iPhone captures, queryable via `CIImage.contentHeadroom`).

## iPhone HDR photos use a gain map, not HLG or PQ

iPhone HDR photos (since iPhone 12, iOS 14.1) are **not** encoded in HLG or PQ. They use a dual-layer gain map architecture: a standard 8-bit SDR image in **Display P3 with the sRGB transfer function**, plus a separate half-resolution grayscale gain map stored as auxiliary data. Metadata records the maximum headroom (up to **8×** for iPhone). Since iOS 18/macOS 15, this conforms to **ISO 21496-1** (Apple calls it "Adaptive HDR").

The composition formula documented by Apple is:

```
hdr_rgb = sdr_rgb × (1.0 + (headroom - 1.0) × gainmap)
```

When `gainmap = 0`, the pixel stays at its SDR value. When `gainmap = 1`, the pixel is boosted by the full headroom factor. Both `sdr_rgb` and `gainmap` are linearized before this multiplication. The key insight: **you don't need to understand this formula to build the false color tool**, because `CIImage` with `.expandToHDR: true` performs this composition internally and delivers unified HDR pixel values where 1.0 = SDR white.

When loaded without `.expandToHDR`, `CIImage` returns only the SDR baseline — the gain map is silently ignored. This is the single most common mistake. The `.expandToHDR` option was introduced in iOS 17/macOS 14 and extended to Adaptive HDR in iOS 18/macOS 15.

## Getting pixel values right: color space, linearity, and luminance

### The working color space determines everything

Core Image's default working color space is **extended linear sRGB** (`kCGColorSpaceExtendedLinearSRGB`). This means:

- **Linear transfer function** (gamma = 1.0) — values are proportional to light intensity
- **sRGB/Rec. 709 primaries** with D65 white point
- **Extended range** — values can exceed 1.0 (HDR) or go below 0.0 (out-of-gamut from wider spaces)
- **1.0 = SDR reference white**, exactly

When a `CIColorKernel` receives a `sample_t`, it is already converted to this working space: linearized, color-space-converted, and premultiplied by alpha. No additional gamma correction or transfer function inversion is needed inside the kernel. This is confirmed by Apple's WWDC20 documentation: "a linear premultiplied RGBA float4, suitable for either SDR or HDR images."

### Correct luminance coefficients

Since the working space uses **sRGB/Rec. 709 primaries**, the correct luminance formula is:

```
Y = 0.2126 × R + 0.7152 × G + 0.0722 × B
```

These coefficients are the Y row of the Rec. 709 RGB-to-XYZ matrix, derived from the chromaticity coordinates of the primaries and the D65 white point. If you instead chose `extendedLinearDisplayP3` as your working space, you would need Display P3 coefficients: **Y = 0.2290R + 0.6917G + 0.0793B**. The luminance result should be identical either way (the color space conversion adjusts the RGB values to compensate), but **you must match coefficients to the primaries of the space you're actually reading**.

Using Rec. 709 coefficients on raw Display P3 values introduces errors of 5–8% for saturated reds and 1–3% for typical photographic content. For a false color visualization this may be tolerable, but getting it right costs nothing — just use the coefficients that match your working space.

### Common mistakes that silently corrupt results

- **Computing luminance from gamma-encoded values**: A mid-gray pixel at sRGB-encoded value 0.5 has linear luminance of approximately 0.214, not 0.5. Using non-linear values overestimates mid-tone luminance by more than 2×. Core Image kernels receive linear values, so this mistake only arises if you extract pixel data outside Core Image (e.g., reading from an NSBitmapImageRep).

- **Using `requestImage` instead of `requestImageDataAndOrientation`**: The `requestImage` API returns a rendered bitmap — the HDR gain map is already baked out (usually tone-mapped to SDR). Only `requestImageDataAndOrientation` returns the raw HEIC bytes containing the gain map.

- **Rendering to 8-bit formats**: `CIContext.createCGImage` with default format produces 8-bit RGBA, clamping all values to [0, 255]. HDR data is destroyed. Always specify `format: .RGBAh` (half-float) or `.RGBAf` (full-float) with an extended color space.

- **Accidentally tone-mapping**: Including `.toneMapHDRtoSDR: true` in the CIImage options, or using an SDR color space (non-extended) as the CIContext working space, silently compresses HDR to SDR range.

## The SDR/HDR boundary is luminance = 1.0

In the extended linear sRGB working space, the boundary between SDR and HDR is **luminance = 1.0**. This is exact, not approximate — it follows directly from EDR's definition where 1.0 is reference white.

Apple's own HDR zebra kernel from WWDC20 uses a simpler per-channel check (`s.r > 1 || s.g > 1 || s.b > 1`), which is a rough proxy. For a correct false color visualization, checking **computed luminance** against 1.0 is more precise, because:

- A highly saturated P3 color converted to sRGB primaries can have an individual channel > 1.0 (out-of-gamut representation) while the actual luminance is still ≤ 1.0
- A pixel where all three channels are slightly above 1.0 would have luminance > 1.0 and should be flagged, even if no single channel stands out dramatically

The `contentHeadroom` property on CIImage reports the image's maximum headroom. For iPhone HDR photos this ranges from **~2 for low-contrast indoor scenes** to **8 for bright specular highlights and sunlight**. A `contentHeadroom` of 1.0 means SDR-only; 0 means unknown.

## Designing the heat map: logarithmic scaling is essential

The HDR luminance range above 1.0 can span a large ratio — up to 8× for iPhone photos. A linear mapping from 1.0 to headroom would compress most of the interesting detail into the bottom of the scale, since human brightness perception is approximately logarithmic. The correct approach uses **logarithmic normalization**:

```metal
float t = log2(lum) / log2(maxHeadroom);  // 0 at SDR white, 1 at max headroom
```

This maps 1 stop above SDR white to `t = 1/3` (for headroom = 8), 2 stops to `t = 2/3`, and 3 stops (full headroom) to `t = 1.0`. Each doubling of brightness gets equal visual space in the heat map, matching perceptual importance.

For the heat-map color scale, a five-point gradient provides clear discrimination:

| Normalized t | Color  | Meaning |
|-------------|--------|---------|
| 0.00 | Blue   | Just above SDR white |
| 0.25 | Cyan   | ~0.75 stops above SDR |
| 0.50 | Green  | ~1.5 stops above SDR |
| 0.75 | Yellow | ~2.25 stops above SDR |
| 1.00 | Red    | Peak HDR (3 stops for 8× headroom) |

Values slightly above 1.0 (barely HDR) map to cool blue, making them easy to distinguish from the greyscale SDR region. Specular highlights and sun appear as hot red. This gradient is implemented as piecewise linear interpolation in the Metal kernel.

## Complete implementation: PhotoKit through Metal kernel

### Step 1: Fetch raw HEIC data from Photos

```swift
let options = PHImageRequestOptions()
options.deliveryMode = .highQualityFormat
options.isNetworkAccessAllowed = true     // Required for iCloud assets
options.version = .unadjusted             // Preserves original gain map

PHImageManager.default().requestImageDataAndOrientation(
    for: asset, options: options
) { data, dataUTI, orientation, info in
    guard let data = data else { return }
    // data contains the full HEIC with embedded gain map
}
```

Use `.unadjusted` or `.original` for the `version` to ensure the gain map is intact. The `.current` version includes user edits that may have modified or removed gain map data.

### Step 2: Create HDR CIImage

```swift
let hdrImage = CIImage(data: data, options: [
    .expandToHDR: true,
    .applyOrientationProperty: true
])!
let headroom = hdrImage.contentHeadroom  // e.g., 7.5
```

The `.expandToHDR` option triggers Core Image to read the gain map auxiliary data, apply the composition formula, and deliver a unified HDR image with values above 1.0. Without this option, you get SDR only.

### Step 3: Configure HDR-preserving CIContext

```swift
let context = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
    .workingFormat: NSNumber(value: CIFormat.RGBAh.rawValue)
])
```

Both settings are critical. The **extended** linear color space permits values outside [0,1]. The **half-float** working format provides sufficient precision for HDR without excessive memory use. Standard sRGB or 8-bit format will clamp HDR values.

### Step 4: Metal kernel for false color

```metal
// FalseColorHDR.ci.metal
#include <CoreImage/CoreImage.h>
using namespace metal;

float3 heatMap(float t) {
    // Blue → Cyan → Green → Yellow → Red
    const float3 c0 = float3(0.0, 0.0, 1.0);   // Blue   (t=0.00)
    const float3 c1 = float3(0.0, 1.0, 1.0);   // Cyan   (t=0.25)
    const float3 c2 = float3(0.0, 1.0, 0.0);   // Green  (t=0.50)
    const float3 c3 = float3(1.0, 1.0, 0.0);   // Yellow (t=0.75)
    const float3 c4 = float3(1.0, 0.0, 0.0);   // Red    (t=1.00)

    t = clamp(t, 0.0, 1.0);
    if (t < 0.25) return mix(c0, c1, t / 0.25);
    if (t < 0.50) return mix(c1, c2, (t - 0.25) / 0.25);
    if (t < 0.75) return mix(c2, c3, (t - 0.50) / 0.25);
    return mix(c3, c4, (t - 0.75) / 0.25);
}

extern "C" float4 falseColorHDR(
    coreimage::sample_t s,       // Linear, premultiplied, extended sRGB
    float maxHeadroom,           // From CIImage.contentHeadroom
    coreimage::destination dest
) {
    // Unpremultiply for correct luminance calculation
    float3 rgb = s.a > 0.0 ? s.rgb / s.a : float3(0.0);

    // Rec. 709 luminance (correct for sRGB primaries)
    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));

    if (lum <= 1.0) {
        // SDR region: greyscale, normalized so SDR white = white
        float grey = clamp(lum, 0.0, 1.0);
        return float4(grey, grey, grey, s.a);
    } else {
        // HDR region: logarithmic false color
        float t = log2(lum) / log2(maxHeadroom);
        float3 color = heatMap(t);
        return float4(color * s.a, s.a);  // Re-premultiply
    }
}
```

**Key details in this kernel**: The `sample_t` arrives premultiplied, so we unpremultiply before computing luminance to avoid alpha-scaled values skewing the calculation. The luminance uses **Rec. 709 coefficients** because the working space is extended linear sRGB. The log2 mapping gives perceptually uniform stops in the heat map. The output is re-premultiplied for correct compositing.

### Step 5: Build rules and Swift wrapper

Add two custom build rules to your Xcode target for `.ci.metal` → `.ci.air` and `.ci.air` → `.ci.metallib`:

```
# .ci.metal → .ci.air
xcrun metal -c -fcikernel "${INPUT_FILE_PATH}" -o "${SCRIPT_OUTPUT_FILE_0}"

# .ci.air → .ci.metallib  
xcrun metallib -cikernel "${INPUT_FILE_PATH}" -o "${SCRIPT_OUTPUT_FILE_0}"
```

The Swift CIFilter wrapper:

```swift
class FalseColorHDRFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    var maxHeadroom: Float = 8.0

    static let kernel: CIColorKernel = {
        let url = Bundle.main.url(forResource: "FalseColorHDR",
                                  withExtension: "ci.metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIColorKernel(functionName: "falseColorHDR",
                                   fromMetalLibraryData: data)
    }()

    override var outputImage: CIImage? {
        guard let input = inputImage else { return nil }
        return Self.kernel.apply(
            extent: input.extent,
            roiCallback: { _, rect in rect },
            arguments: [input, maxHeadroom]
        )
    }
}
```

### Step 6: Render for display or analysis

For on-screen display in an EDR-capable view:

```swift
let metalView: MTKView = ...
metalView.colorPixelFormat = .rgba16Float
metalView.layer?.wantsExtendedDynamicRangeContent = true
(metalView.layer as? CAMetalLayer)?.colorspace =
    CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
```

For reading raw pixel values into a float buffer:

```swift
var bitmap = [Float](repeating: 0, count: width * height * 4)
context.render(hdrImage, toBitmap: &bitmap,
    rowBytes: width * 16,
    bounds: hdrImage.extent,
    format: .RGBAf,
    colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
// bitmap[i] can now exceed 1.0 for HDR pixels
```

## Essential WWDC sessions and references

The most important Apple resources for this work, in priority order:

- **WWDC 2021, session 10161 "Explore HDR rendering with EDR"** — the foundational EDR session explaining the 1.0 = SDR white model, headroom, and the four-step CAMetalLayer setup
- **WWDC 2023, session 10181 "Support HDR images in your app"** — introduces `.expandToHDR`, `.toneMapHDRtoSDR`, `contentHeadroom`, and gain map APIs
- **WWDC 2024, session 10177 "Use HDR for dynamic image experiences"** — Adaptive HDR, `CIFilter.toneMapHeadroom()`, gain map editing strategies, `CGBitmapContext` EDR support
- **WWDC 2022, session 10114 "Display EDR content with Core Image, Metal, and SwiftUI"** — CIFilter EDR pipeline, 150+ HDR-compatible built-in filters, sample project
- **WWDC 2020, session 10021 "Build Metal-based Core Image kernels"** — the HDRZebra kernel example, `.ci.metal` build rules, `extern "C"` kernel syntax

Open-source references include the Apple sample project "SupportingHDRImagesInYourApp" (WWDC23), the `tev` HDR image viewer (github.com/Tom94/tev) which supports gain maps and false-color comparison, and `CoreImageExtensions` by DigitalMasterpieces for convenient pixel-reading utilities.

## Conclusion

The false color pipeline is simpler than it first appears once you understand Apple's EDR model. The entire color science reduces to three facts: **1.0 equals SDR white in extended linear sRGB**, **luminance = 0.2126R + 0.7152G + 0.0722B in that space**, and **`CIColorKernel` receives pre-linearized values requiring no transfer function work**. The complexity hides in the pipeline plumbing — using `requestImageDataAndOrientation` instead of `requestImage`, remembering `.expandToHDR: true`, choosing a float pixel format, and specifying an extended color space at every stage. A logarithmic mapping from the 1.0 boundary up to `contentHeadroom` produces a perceptually meaningful heat map where each stop of HDR headroom gets equal visual weight. The gain map composition math, transfer function inversions, and color space conversions all happen automatically inside Core Image — you never touch them directly.