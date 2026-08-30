import SwiftUI
import SideNotchCore

/// Provider marks, drawn as vectors.
///
/// Vectors rather than bundled bitmaps: these render at 16pt inside a ring and again at
/// menu-bar size, and a path stays crisp at both without shipping several raster sizes.
///
/// They are drawn monochrome to match the product's visual reference, where each mark sits
/// white on a dark disc inside its usage ring, rather than in brand colour.
///
/// **Trademarks.** These approximate marks owned by Anthropic, OpenAI, and Anysphere.
/// Shipping them publicly needs a trademark review — see `docs/PROVIDER_MARKS.md`. Exact
/// artwork can be dropped in without a code change; see `ProviderLogo`.
enum ProviderMark {}

// MARK: - Claude

/// Anthropic's radiating asterisk: tapered blades, wider at the hub than the tip.
struct ClaudeMark: Shape {
    var bladeCount: Int = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        // A small hole at the hub keeps the blades reading as separate spokes rather than
        // merging into a blob at ring size.
        let inner = outer * 0.13
        let hubHalfWidth = outer * 0.105
        let tipHalfWidth = outer * 0.030

        for index in 0..<bladeCount {
            let angle = (Double(index) / Double(bladeCount)) * 2 * .pi - .pi / 2
            let along = CGPoint(x: cos(angle), y: sin(angle))
            // Perpendicular, to give each blade its width.
            let across = CGPoint(x: -along.y, y: along.x)

            func point(_ radius: CGFloat, _ offset: CGFloat) -> CGPoint {
                CGPoint(
                    x: center.x + along.x * radius + across.x * offset,
                    y: center.y + along.y * radius + across.y * offset
                )
            }

            path.move(to: point(inner, -hubHalfWidth))
            path.addLine(to: point(outer, -tipHalfWidth))
            path.addLine(to: point(outer, tipHalfWidth))
            path.addLine(to: point(inner, hubHalfWidth))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Codex

/// A scalloped blob carrying a terminal prompt, following the mark on the Codex icon.
struct CodexMark: Shape {
    var lobes: Int = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // A circle modulated by a small sine gives the soft cloud edge without hand-placing
        // each lobe.
        // Gentle: too much and it reads as a gear rather than a soft blob.
        let amplitude = radius * 0.055
        let steps = 240

        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let angle = t * 2 * .pi
            let r = radius - amplitude + amplitude * cos(Double(lobes) * angle)
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * r,
                y: center.y + CGFloat(sin(angle)) * r
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// The `>_` prompt drawn inside `CodexMark`, as strokes so it stays legible when small.
///
/// Laid out in unit coordinates and scaled, so the proportions hold at 13pt in a card title
/// and at 18pt inside a ring.
struct CodexPromptMark: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + size * x, y: rect.minY + size * y)
        }

        var path = Path()
        // Chevron.
        path.move(to: point(0.30, 0.34))
        path.addLine(to: point(0.47, 0.50))
        path.addLine(to: point(0.30, 0.66))
        // Underscore.
        path.move(to: point(0.54, 0.66))
        path.addLine(to: point(0.72, 0.66))
        return path
    }
}

// MARK: - Cursor

/// The isometric cube silhouette, as an outline.
struct CursorCubeOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<6 {
            let point = CursorGeometry.vertex(index, in: rect)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// The wedge inside the cube, which is what gives the mark its arrow reading.
struct CursorCubeWedge: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        var path = Path()
        path.move(to: CursorGeometry.vertex(0, in: rect))          // top
        path.addLine(to: CursorGeometry.vertex(1, in: rect))       // upper right
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.70))
        path.closeSubpath()
        return path
    }
}

enum CursorGeometry {
    /// Hexagon vertices, starting at the top: the silhouette of a cube seen isometrically.
    static func vertex(_ index: Int, in rect: CGRect) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let angle = Double(index) / 6 * 2 * .pi - .pi / 2
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }
}

// MARK: - Rendering

/// A provider's mark, sized to fit `size`.
///
/// Looks first for artwork the user supplied, so exact brand assets can be dropped in
/// without touching the code:
///
/// ```
/// ~/Library/Application Support/Top Notch/Logos/<provider-id>.png
/// ```
///
/// Falling back to the drawn vector, and finally to an SF Symbol for a tool Top Notch has
/// no mark for.
struct ProviderLogo: View {
    let provider: ProviderType
    let size: CGFloat
    var tint: Color = .white

    var body: some View {
        if let image = Self.suppliedImage(for: provider) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            drawnMark
        }
    }

    @ViewBuilder
    private var drawnMark: some View {
        switch provider {
        case .claude:
            ClaudeMark().fill(tint).frame(width: size, height: size)
        case .codex:
            ZStack {
                CodexMark().fill(tint)
                CodexPromptMark()
                    .stroke(
                        Tokens.Palette.ringWell,
                        style: StrokeStyle(lineWidth: max(size * 0.10, 1.2),
                                           lineCap: .round, lineJoin: .round)
                    )
            }
            .frame(width: size, height: size)
        case .cursor:
            ZStack {
                CursorCubeOutline()
                    .stroke(tint, style: StrokeStyle(
                        lineWidth: max(size * 0.09, 1), lineJoin: .round
                    ))
                CursorCubeWedge().fill(tint)
            }
            .frame(width: size, height: size)
        default:
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: size * 0.9, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }

    /// Directory the user can drop exact brand artwork into.
    static var logoDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Top Notch/Logos")
    }

    /// Where the same artwork lived before the product was renamed.
    ///
    /// Read-only, and searched only after the current location. The cache beside it is
    /// disposable and simply moved, but this directory holds files a person put there by
    /// hand — silently ignoring them because the app changed its own name would look
    /// exactly like the feature breaking.
    static var legacyLogoDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Top Notch/Logos")
    }

    /// Cached so a missing file is not re-checked on every render pass.
    private static let cache = SuppliedLogoCache()

    static func suppliedImage(for provider: ProviderType) -> NSImage? {
        cache.image(for: provider)
    }
}

/// Small cache for user-supplied logo files.
private final class SuppliedLogoCache: @unchecked Sendable {
    private let lock = NSLock()
    private var loaded: [String: NSImage?] = [:]

    func image(for provider: ProviderType) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = loaded[provider.rawValue] { return cached }

        var found: NSImage?
        // Current location first, then the pre-rename one, so artwork dropped in by hand
        // survives the product being renamed.
        let directories = [ProviderLogo.logoDirectory, ProviderLogo.legacyLogoDirectory]
        search: for directory in directories {
            for ext in ["png", "pdf", "svg"] {
                let url = directory.appendingPathComponent("\(provider.rawValue).\(ext)")
                if FileManager.default.fileExists(atPath: url.path),
                   let image = NSImage(contentsOf: url) {
                    found = image
                    break search
                }
            }
        }
        loaded[provider.rawValue] = found
        return found
    }
}
