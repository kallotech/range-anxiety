import AppKit
import Foundation

// Format conversion only: preserve the supplied artwork and transparent canvas.
// Usage: swift scripts/generate-app-icon.swift source.svg output.iconset
guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift scripts/generate-app-icon.swift source.svg output.iconset\n", stderr)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard outputURL.pathExtension == "iconset",
      let artwork = NSImage(contentsOf: sourceURL),
      artwork.size.width > 0,
      artwork.size.width == artwork.size.height else {
    fputs("Provide a readable square image and an output directory ending in .iconset.\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "RangeAnxiety.Icon", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not create image context."])
            }

            bitmap.size = NSSize(width: pixels, height: pixels)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            artwork.draw(
                in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()

            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "RangeAnxiety.Icon", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG."])
            }
            let suffix = scale == 2 ? "@2x" : ""
            let filename = "icon_\(points)x\(points)\(suffix).png"
            try data.write(to: outputURL.appendingPathComponent(filename), options: .atomic)
            print("Created \(filename) (\(pixels)×\(pixels))")
        }
    }
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
