import CoreGraphics
import Foundation

/// BlurHash encoder (https://blurha.sh), ported from the reference Swift
/// implementation to plain CGImage so it runs on iOS and macOS alike.
/// Required: the Matrix SDK's image info demands a blurhash on send.
enum BlurHash {
    static func encode(image: CGImage, componentsX: Int = 4, componentsY: Int = 3) -> String? {
        guard componentsX >= 1, componentsX <= 9, componentsY >= 1, componentsY <= 9,
              let pixels = rgbaPixels(of: image) else { return nil }

        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4

        var factors: [(Float, Float, Float)] = []
        for y in 0..<componentsY {
            for x in 0..<componentsX {
                let normalisation: Float = (x == 0 && y == 0) ? 1 : 2
                var r: Float = 0, g: Float = 0, b: Float = 0
                for py in 0..<height {
                    for px in 0..<width {
                        let basis = normalisation
                            * cos(Float.pi * Float(x) * Float(px) / Float(width))
                            * cos(Float.pi * Float(y) * Float(py) / Float(height))
                        let offset = py * bytesPerRow + px * 4
                        r += basis * sRGBToLinear(pixels[offset])
                        g += basis * sRGBToLinear(pixels[offset + 1])
                        b += basis * sRGBToLinear(pixels[offset + 2])
                    }
                }
                let scale = 1 / Float(width * height)
                factors.append((r * scale, g * scale, b * scale))
            }
        }

        let dc = factors.removeFirst()
        let ac = factors

        var hash = ""
        let sizeFlag = (componentsX - 1) + (componentsY - 1) * 9
        hash += encode83(sizeFlag, length: 1)

        let maximumValue: Float
        if !ac.isEmpty {
            let actualMax = ac.map { max(abs($0.0), abs($0.1), abs($0.2)) }.max() ?? 0
            let quantisedMax = max(0, min(82, Int(floor(actualMax * 166 - 0.5))))
            maximumValue = Float(quantisedMax + 1) / 166
            hash += encode83(quantisedMax, length: 1)
        } else {
            maximumValue = 1
            hash += encode83(0, length: 1)
        }

        hash += encode83(encodeDC(dc), length: 4)
        for factor in ac {
            hash += encode83(encodeAC(factor, maximumValue: maximumValue), length: 2)
        }
        return hash
    }

    // MARK: - Pixel access

    private static func rgbaPixels(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    // MARK: - Math

    private static func sRGBToLinear(_ value: UInt8) -> Float {
        let v = Float(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func linearTosRGB(_ value: Float) -> Int {
        let v = max(0, min(1, value))
        let scaled = v <= 0.0031308 ? v * 12.92 : (1.055 * pow(v, 1 / 2.4) - 0.055)
        return Int(scaled * 255 + 0.5)
    }

    private static func signPow(_ value: Float, _ exp: Float) -> Float {
        copysign(pow(abs(value), exp), value)
    }

    private static func encodeDC(_ value: (Float, Float, Float)) -> Int {
        (linearTosRGB(value.0) << 16) + (linearTosRGB(value.1) << 8) + linearTosRGB(value.2)
    }

    private static func encodeAC(_ value: (Float, Float, Float), maximumValue: Float) -> Int {
        func quantise(_ component: Float) -> Int {
            max(0, min(18, Int(floor(signPow(component / maximumValue, 0.5) * 9 + 9.5))))
        }
        return quantise(value.0) * 19 * 19 + quantise(value.1) * 19 + quantise(value.2)
    }

    // MARK: - Base 83

    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

    private static func encode83(_ value: Int, length: Int) -> String {
        var result = ""
        for digit in 1...length {
            let index = (value / Int(pow(83, Float(length - digit)))) % 83
            result.append(alphabet[index])
        }
        return result
    }
}
