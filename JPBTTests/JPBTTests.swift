import Testing

@testable import JPBT

struct FalseColorTests {

  @Test func blackIsBlack() {
    let (r, g, b) = FalseColorFilter.falseColor(r: 0, g: 0, b: 0)
    #expect(r == 0)
    #expect(g == 0)
    #expect(b == 0)
  }

  @Test func sdrWhiteIsWhite() {
    let (r, g, b) = FalseColorFilter.falseColor(r: 1, g: 1, b: 1)
    #expect(r == 1)
    #expect(g == 1)
    #expect(b == 1)
  }

  @Test func midGrayIsGrayscale() {
    let (r, g, b) = FalseColorFilter.falseColor(r: 0.5, g: 0.5, b: 0.5)
    #expect(r == g)
    #expect(g == b)
    #expect(r > 0 && r < 1)
  }

  @Test func aboveSdrIsNotGrayscale() {
    // 1.5x SDR white — within first stop above SDR
    let (r, g, b) = FalseColorFilter.falseColor(r: 1.5, g: 1.5, b: 1.5)
    let isGrayscale = (r == g && g == b)
    #expect(!isGrayscale)
  }

  @Test func firstStopBand() {
    // luminance = 1.5 → ~0.58 stops
    let (r, g, b) = FalseColorFilter.falseColor(r: 1.5, g: 1.5, b: 1.5)
    #expect(r == Float(0.66))
    #expect(g == Float(1))
    #expect(b == Float(1))
  }

  @Test func secondStopBand() {
    // luminance = 3.0 → ~1.58 stops
    let (r, g, b) = FalseColorFilter.falseColor(r: 3, g: 3, b: 3)
    #expect(r == Float(0.4))
    #expect(g == Float(0.6))
    #expect(b == Float(1))
  }

  @Test func thirdStopBand() {
    // luminance = 5.0 → ~2.32 stops
    let (r, g, b) = FalseColorFilter.falseColor(r: 5, g: 5, b: 5)
    #expect(r == Float(0.5))
    #expect(g == Float(0.1))
    #expect(b == Float(1))
  }

  @Test func fourthStopBand() {
    // luminance = 10.0 → ~3.32 stops
    let (r, g, b) = FalseColorFilter.falseColor(r: 10, g: 10, b: 10)
    #expect(r == Float(0.8))
    #expect(g == Float(0.2))
    #expect(b == Float(1))
  }
}
