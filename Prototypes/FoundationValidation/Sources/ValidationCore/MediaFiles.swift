import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

public enum MediaFiles {
    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func syntheticJPEG(seed: Int = 1) throws -> Data {
        let width = 320, height = 240
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8((x * 7 + y * 3 + seed) % 256)
                pixels[i+1] = UInt8((x + y * 11 + seed * 5) % 256)
                pixels[i+2] = UInt8((x * y + seed * 13) % 256)
                pixels[i+3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ValidationFailure.invariant("JPEG encoder unavailable")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05", kCGImagePropertyExifUserComment: "synthetic source-only metadata"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 0.0, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ValidationFailure.invariant("JPEG encoding failed") }
        return data as Data
    }

    public static func preview(_ original: Data, maxPixel: Int = 256) throws -> Data {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary) else {
            throw ValidationFailure.invariant("unreadable image")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ValidationFailure.invariant("preview encoder unavailable")
        }
        // Re-encode oriented pixels without copying source EXIF/GPS dictionaries.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ValidationFailure.invariant("preview encoding failed") }
        return data as Data
    }

    static func write(_ data: Data, to url: URL, recreatable: Bool = false) throws {
        try data.write(to: url, options: .atomic)
        var target = url
        var flags = URLResourceValues(); flags.isExcludedFromBackup = recreatable
        try target.setResourceValues(flags)
    }
}
