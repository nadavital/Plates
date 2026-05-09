import AppKit
import CoreGraphics
import Foundation

struct Shot {
    let input: String
    let output: String
    let title: String
    let accent: NSColor
    let backgroundOffset: CGFloat
}

struct RenderProfile {
    let outputDirectoryName: String
    let canvasSize: CGSize
    let deviceFrame: CGRect
    let titleRect: CGRect
    let titleFontSize: CGFloat
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let screenshotsRoot = root.appendingPathComponent("AppStoreScreenshots")
let inputDir = screenshotsRoot.appendingPathComponent("raw")
let outputDir = screenshotsRoot.appendingPathComponent("framed")
let qaDir = screenshotsRoot.appendingPathComponent("qa")
let defaultBezelPath = "/tmp/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Cosmic Orange - Portrait.png"
let bezelURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TRAI_APPSTORE_BEZEL"] ?? defaultBezelPath)

let shots: [Shot] = [
    Shot(
        input: "01-dashboard.png",
        output: "01-hit-your-daily-targets.png",
        title: "Hit your targets without guessing",
        accent: NSColor(calibratedRed: 1.00, green: 0.29, blue: 0.24, alpha: 1),
        backgroundOffset: 0
    ),
    Shot(
        input: "05-food-capture.png",
        output: "02-log-food-from-a-photo.png",
        title: "Snap food and get macros fast",
        accent: NSColor(calibratedRed: 0.98, green: 0.43, blue: 0.22, alpha: 1),
        backgroundOffset: 1
    ),
    Shot(
        input: "06-food-review.png",
        output: "03-review-before-you-log.png",
        title: "Review macros before logging",
        accent: NSColor(calibratedRed: 0.86, green: 0.18, blue: 0.36, alpha: 1),
        backgroundOffset: 2
    ),
    Shot(
        input: "03-chat.png",
        output: "04-ask-trai-to-plan-the-day.png",
        title: "Ask Trai to adjust your lift",
        accent: NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.38, alpha: 1),
        backgroundOffset: 3
    ),
    Shot(
        input: "07-live-workout.png",
        output: "05-track-every-set-live.png",
        title: "Ask Trai during live workouts",
        accent: NSColor(calibratedRed: 0.97, green: 0.74, blue: 0.20, alpha: 1),
        backgroundOffset: 4
    ),
    Shot(
        input: "02-workouts.png",
        output: "06-follow-a-plan-that-adapts.png",
        title: "See Health data with your workouts",
        accent: NSColor(calibratedRed: 0.19, green: 0.45, blue: 0.88, alpha: 1),
        backgroundOffset: 5
    ),
    Shot(
        input: "08-plan-chat.png",
        output: "07-let-trai-plan-your-week.png",
        title: "Let Trai plan your week",
        accent: NSColor(calibratedRed: 0.95, green: 0.32, blue: 0.52, alpha: 1),
        backgroundOffset: 6
    )
]

let profile = RenderProfile(
    outputDirectoryName: "6.9",
    canvasSize: CGSize(width: 1320, height: 2868),
    deviceFrame: CGRect(x: 145, y: 650, width: 1030, height: 2189),
    titleRect: CGRect(x: 86, y: 245, width: 1148, height: 300),
    titleFontSize: 92
)

let rgbaBitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

func flipped(_ rect: CGRect, canvasSize: CGSize) -> CGRect {
    CGRect(x: rect.origin.x, y: canvasSize.height - rect.origin.y - rect.height, width: rect.width, height: rect.height)
}

func drawText(
    _ text: String,
    rect: CGRect,
    font: NSFont,
    color: NSColor,
    context: CGContext,
    canvasSize: CGSize,
    alignment: NSTextAlignment = .center,
    lineHeight: CGFloat? = nil
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSString(string: text).draw(in: flipped(rect, canvasSize: canvasSize), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}

func drawBackground(shot: Shot, context: CGContext, canvasSize: CGSize) {
    let base = [
        NSColor(calibratedRed: 1.00, green: 0.10, blue: 0.14, alpha: 1).cgColor,
        NSColor(calibratedRed: 1.00, green: 0.19, blue: 0.14, alpha: 1).cgColor,
        NSColor(calibratedRed: 1.00, green: 0.46, blue: 0.24, alpha: 1).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: base, locations: [0, 0.48, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height),
        end: CGPoint(x: canvasSize.width * 0.5, y: 0),
        options: []
    )
}

struct BezelAssets {
    let overlay: CGImage
    let screenMask: CGImage
    let screenBounds: CGRect
    let visibleBounds: CGRect
}

func makeBezelAssets(from image: CGImage) throws -> BezelAssets {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    var maskPixels = [UInt8](repeating: 0, count: width * height)

    guard let bitmap = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo
    ) else {
        throw NSError(domain: "trai-renderer", code: 1)
    }
    bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    func isScreenCutout(_ x: Int, _ y: Int) -> Bool {
        pixels[y * bytesPerRow + x * bytesPerPixel + 3] < 10
    }

    var startPoint: (x: Int, y: Int)?
    var bestDistance = Int.max
    let centerX = width / 2
    let centerY = height / 2
    for y in 0..<height {
        for x in 0..<width where isScreenCutout(x, y) {
            let distance = abs(x - centerX) + abs(y - centerY)
            if distance < bestDistance {
                bestDistance = distance
                startPoint = (x, y)
            }
        }
    }
    guard let startPoint else {
        throw NSError(domain: "trai-renderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not find transparent screen area in bezel"])
    }

    var visibleMinX = width
    var visibleMinY = height
    var visibleMaxX = 0
    var visibleMaxY = 0
    for y in 0..<height {
        for x in 0..<width {
            let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
            guard alpha > 10 else { continue }
            visibleMinX = min(visibleMinX, x)
            visibleMinY = min(visibleMinY, y)
            visibleMaxX = max(visibleMaxX, x)
            visibleMaxY = max(visibleMaxY, y)
        }
    }

    var visited = [Bool](repeating: false, count: width * height)
    var stack = [startPoint]
    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0
    while let point = stack.popLast() {
        guard point.x >= 0, point.x < width, point.y >= 0, point.y < height else { continue }
        let index = point.y * width + point.x
        guard !visited[index] else { continue }
        visited[index] = true
        guard isScreenCutout(point.x, point.y) else { continue }
        maskPixels[index] = 255
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
        stack.append((point.x + 1, point.y))
        stack.append((point.x - 1, point.y))
        stack.append((point.x, point.y + 1))
        stack.append((point.x, point.y - 1))
    }

    guard let overlay = bitmap.makeImage(),
          let provider = CGDataProvider(data: Data(maskPixels) as CFData),
          let mask = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          ) else {
        throw NSError(domain: "trai-renderer", code: 3)
    }

    return BezelAssets(
        overlay: overlay,
        screenMask: mask,
        screenBounds: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1),
        visibleBounds: CGRect(x: visibleMinX, y: visibleMinY, width: visibleMaxX - visibleMinX + 1, height: visibleMaxY - visibleMinY + 1)
    )
}

func makeDeviceComposite(screenshot: CGImage, bezel: CGImage, assets: BezelAssets) throws -> CGImage {
    let bezelSize = CGSize(width: bezel.width, height: bezel.height)
    guard let screenContext = CGContext(
        data: nil,
        width: Int(bezelSize.width),
        height: Int(bezelSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo
    ) else {
        throw NSError(domain: "trai-renderer", code: 4)
    }
    screenContext.saveGState()
    screenContext.clip(to: CGRect(x: 0, y: 0, width: bezelSize.width, height: bezelSize.height), mask: assets.screenMask)
    screenContext.draw(screenshot, in: assets.screenBounds)
    screenContext.restoreGState()

    guard let screenLayer = screenContext.makeImage(),
          let deviceContext = CGContext(
            data: nil,
            width: Int(bezelSize.width),
            height: Int(bezelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: rgbaBitmapInfo
          ) else {
        throw NSError(domain: "trai-renderer", code: 5)
    }
    deviceContext.draw(screenLayer, in: CGRect(origin: .zero, size: bezelSize))
    deviceContext.draw(assets.overlay, in: CGRect(origin: .zero, size: bezelSize))

    guard let fullDevice = deviceContext.makeImage(),
          let cropped = fullDevice.cropping(to: assets.visibleBounds) else {
        throw NSError(domain: "trai-renderer", code: 6)
    }
    return cropped
}

func render(_ shot: Shot, profile: RenderProfile, bezel: CGImage, assets: BezelAssets, destination: URL) throws {
    guard let context = CGContext(
        data: nil,
        width: Int(profile.canvasSize.width),
        height: Int(profile.canvasSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo
    ) else {
        throw NSError(domain: "trai-renderer", code: 7)
    }

    drawBackground(shot: shot, context: context, canvasSize: profile.canvasSize)
    drawText(
        shot.title,
        rect: profile.titleRect,
        font: NSFont.systemFont(ofSize: profile.titleFontSize, weight: .black),
        color: .white,
        context: context,
        canvasSize: profile.canvasSize,
        lineHeight: 98
    )

    let inputURL = inputDir.appendingPathComponent(shot.input)
    guard let source = NSImage(contentsOf: inputURL),
          let screenshot = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "trai-renderer", code: 8, userInfo: [NSLocalizedDescriptionKey: "Missing input \(inputURL.path)"])
    }
    let device = try makeDeviceComposite(screenshot: screenshot, bezel: bezel, assets: assets)
    context.draw(device, in: flipped(profile.deviceFrame, canvasSize: profile.canvasSize))

    guard let image = context.makeImage() else {
        throw NSError(domain: "trai-renderer", code: 9)
    }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = profile.canvasSize
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "trai-renderer", code: 10)
    }
    try data.write(to: destination.appendingPathComponent(shot.output), options: .atomic)
}

func writeContactSheet(from directory: URL, to output: URL) throws {
    let files = shots.map { directory.appendingPathComponent($0.output) }
    let scale: CGFloat = 0.18
    let thumbSize = CGSize(width: profile.canvasSize.width * scale, height: profile.canvasSize.height * scale)
    let sheetSize = CGSize(width: thumbSize.width * CGFloat(files.count), height: thumbSize.height)
    guard let context = CGContext(
        data: nil,
        width: Int(sheetSize.width),
        height: Int(sheetSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo
    ) else {
        throw NSError(domain: "trai-renderer", code: 11)
    }
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(origin: .zero, size: sheetSize))
    for (index, file) in files.enumerated() {
        guard let source = NSImage(contentsOf: file),
              let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        let rect = CGRect(x: CGFloat(index) * thumbSize.width, y: 0, width: thumbSize.width, height: thumbSize.height)
        context.draw(image, in: rect)
    }
    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "trai-renderer", code: 12)
    }
    try data.write(to: output, options: .atomic)
}

let destination = outputDir.appendingPathComponent(profile.outputDirectoryName)
if FileManager.default.fileExists(atPath: destination.path) {
    try FileManager.default.removeItem(at: destination)
}
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: qaDir, withIntermediateDirectories: true)

guard let bezelImage = NSImage(contentsOf: bezelURL),
      let bezel = bezelImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    throw NSError(domain: "trai-renderer", code: 13, userInfo: [NSLocalizedDescriptionKey: "Missing bezel at \(bezelURL.path)"])
}
let assets = try makeBezelAssets(from: bezel)
for shot in shots {
    try render(shot, profile: profile, bezel: bezel, assets: assets, destination: destination)
}
try writeContactSheet(from: destination, to: qaDir.appendingPathComponent("framed_contact_sheet.png"))
print("Wrote \(shots.count) framed screenshots to \(destination.path)")
