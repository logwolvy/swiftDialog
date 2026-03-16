//
//  ProceduralGradientView.swift
//  dialog
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 15/03/2026
//
//  Procedurally generated mesh gradient backgrounds from a deterministic seed.
//  Replaces static wallpaper image files with native SwiftUI MeshGradient.
//

import SwiftUI

// MARK: - Gradient Style

enum ProceduralGradientStyle: String, CaseIterable {
    case ethereal   // Soft, dreamy — like FGrad wallpapers
    case vivid      // Saturated, bold
    case subtle     // Muted, professional

    /// Saturation range for palette expansion
    var saturationRange: ClosedRange<Double> {
        switch self {
        case .ethereal: return 0.5...0.85
        case .vivid:    return 0.75...1.0
        case .subtle:   return 0.3...0.6
        }
    }

    /// Brightness range for palette expansion
    var brightnessRange: ClosedRange<Double> {
        switch self {
        case .ethereal: return 0.75...1.0
        case .vivid:    return 0.6...0.95
        case .subtle:   return 0.8...1.0
        }
    }

    /// How much to jitter hue (degrees)
    var hueShift: Double {
        switch self {
        case .ethereal: return 30
        case .vivid:    return 20
        case .subtle:   return 15
        }
    }

    /// How much to jitter grid point positions
    var positionJitter: Float {
        switch self {
        case .ethereal: return 0.15
        case .vivid:    return 0.10
        case .subtle:   return 0.08
        }
    }
}

// MARK: - Seeded Random Number Generator

/// Deterministic pseudo-random generator using a Linear Congruential Generator.
/// Same seed always produces the same sequence of values.
struct SeededRNG {
    private var state: UInt64

    init(seed: String) {
        self.state = Self.djb2Hash(seed)
    }

    /// DJB2 hash — stable across process launches (unlike Swift's Hashable)
    private static func djb2Hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        // Ensure non-zero state
        return hash == 0 ? 1 : hash
    }

    /// Generate next pseudo-random UInt64
    mutating func next() -> UInt64 {
        // LCG with Knuth's constants
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    /// Generate a random Double in [0, 1)
    mutating func nextDouble() -> Double {
        return Double(next() >> 11) / Double(1 << 53)
    }

    /// Generate a random Float in [0, 1)
    mutating func nextFloat() -> Float {
        return Float(nextDouble())
    }

    /// Generate a random Double in a given range
    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        return range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
    }

    /// Generate a random Float in a given range
    mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        return range.lowerBound + nextFloat() * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Procedural Gradient View

/// A SwiftUI view that generates a deterministic mesh gradient from a seed string.
///
/// Usage:
/// ```swift
/// ProceduralGradientView(
///     seed: "outset",
///     palette: [.purple, .pink],
///     style: .ethereal
/// )
/// ```
struct ProceduralGradientView: View {
    let seed: String
    let palette: [Color]
    let style: ProceduralGradientStyle

    init(seed: String, palette: [Color] = [], style: ProceduralGradientStyle = .ethereal) {
        self.seed = seed
        self.palette = palette
        self.style = style
    }

    var body: some View {
        let generated = Self.generateGradientData(seed: seed, palette: palette, style: style)

        MeshGradient(
            width: 3,
            height: 3,
            points: generated.points,
            colors: generated.colors
        )
    }

    // MARK: - Generation

    /// All data needed to render the gradient, computed deterministically from the seed.
    struct GradientData {
        let points: [SIMD2<Float>]
        let colors: [Color]
    }

    /// Generate deterministic gradient data from a seed, palette, and style.
    static func generateGradientData(
        seed: String,
        palette: [Color],
        style: ProceduralGradientStyle
    ) -> GradientData {
        var rng = SeededRNG(seed: seed)
        let colors = expandPalette(base: palette, rng: &rng, style: style)
        let points = generatePoints(rng: &rng, style: style)
        return GradientData(points: points, colors: colors)
    }

    // MARK: - Point Generation

    /// Generate a 3×3 grid of control points with organic jitter from the seed.
    /// Edge and corner points are kept on/near edges to avoid visual holes.
    private static func generatePoints(rng: inout SeededRNG, style: ProceduralGradientStyle) -> [SIMD2<Float>] {
        let jitter = style.positionJitter
        var points: [SIMD2<Float>] = []

        for row in 0..<3 {
            for col in 0..<3 {
                let baseX = Float(col) / 2.0
                let baseY = Float(row) / 2.0

                var x = baseX
                var y = baseY

                // Only jitter interior points freely; edge points jitter along edge only
                let isEdgeX = (col == 0 || col == 2)
                let isEdgeY = (row == 0 || row == 2)

                if !isEdgeX {
                    x += rng.nextFloat(in: -jitter...jitter)
                }
                if !isEdgeY {
                    y += rng.nextFloat(in: -jitter...jitter)
                }

                // Edge points get reduced jitter along the free axis
                if isEdgeX && !isEdgeY {
                    y += rng.nextFloat(in: -(jitter * 0.5)...(jitter * 0.5))
                }
                if isEdgeY && !isEdgeX {
                    x += rng.nextFloat(in: -(jitter * 0.5)...(jitter * 0.5))
                }

                // Clamp to valid range
                x = max(0, min(1, x))
                y = max(0, min(1, y))

                points.append(SIMD2<Float>(x, y))
            }
        }

        return points
    }

    // MARK: - Palette Expansion

    /// Expand 0-3 base colors into 9 mesh gradient colors using HSB manipulation.
    private static func expandPalette(
        base: [Color],
        rng: inout SeededRNG,
        style: ProceduralGradientStyle
    ) -> [Color] {
        // Extract HSB from base colors, or generate from seed
        var baseHSBs: [(h: Double, s: Double, b: Double)] = []

        if base.isEmpty {
            // No palette provided — generate 2 harmonious hues from seed
            let hue1 = rng.nextDouble()
            let hue2 = fmod(hue1 + rng.nextDouble(in: 0.15...0.45), 1.0)
            baseHSBs = [
                (h: hue1, s: 0.7, b: 0.9),
                (h: hue2, s: 0.6, b: 0.95)
            ]
        } else {
            for color in base.prefix(3) {
                let hsb = color.hsb
                baseHSBs.append(hsb)
            }
        }

        // Generate 9 colors by cycling through base colors and applying variations
        var colors: [Color] = []
        for i in 0..<9 {
            let baseIndex = i % baseHSBs.count
            let baseHSB = baseHSBs[baseIndex]

            // Shift hue deterministically
            let hueOffset = rng.nextDouble(in: -style.hueShift...style.hueShift) / 360.0
            let hue = fmod(baseHSB.h + hueOffset + 1.0, 1.0)

            // Vary saturation and brightness within style range
            let saturation = rng.nextDouble(in: style.saturationRange)
            let brightness = rng.nextDouble(in: style.brightnessRange)

            colors.append(Color(hue: hue, saturation: saturation, brightness: brightness))
        }

        return colors
    }
}

// MARK: - Color HSB Extension

private extension Color {
    /// Extract HSB components from a SwiftUI Color
    var hsb: (h: Double, s: Double, b: Double) {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h: Double(h), s: Double(s), b: Double(b))
    }
}

// MARK: - Preview

#if DEBUG
struct ProceduralGradientView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ProceduralGradientView(seed: "outset", palette: [.purple, .pink], style: .ethereal)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            ProceduralGradientView(seed: "sofa", palette: [.blue, .cyan], style: .vivid)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            ProceduralGradientView(seed: "pique", style: .subtle)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
