//
//  MosaicProcessor.swift
//  dama
//
//  Created by sequel on 2025/9/19.
//

import UIKit
import CoreImage
import Vision
import Combine

// 马赛克处理器 - 负责图像打码处理
class MosaicProcessor: ObservableObject {

    // 马赛克强度枚举
    enum MosaicIntensity: Int, CaseIterable {
        case high = 20    // 高强度 - 20x20像素块

        var displayName: String {
            return "模糊"
        }
    }

    // 马赛克区域结构
    struct MosaicRegion: Equatable {
        let rect: CGRect
        let intensity: MosaicIntensity
        var isActive: Bool = true

        static func == (lhs: MosaicRegion, rhs: MosaicRegion) -> Bool {
            return lhs.rect == rhs.rect &&
                   lhs.intensity == rhs.intensity &&
                   lhs.isActive == rhs.isActive
        }
    }

    @Published var mosaicRegions: [MosaicRegion] = []
    @Published var currentIntensity: MosaicIntensity = .high

    // 对指定区域应用马赛克效果
    func applyMosaic(to image: UIImage, regions: [MosaicRegion]) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        // 创建颜色空间和上下文
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        // 绘制原始图像
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 应用马赛克到每个区域
        for region in regions where region.isActive {
            applyMosaicToRegion(context: context, region: region, imageSize: CGSize(width: width, height: height))
        }

        // 创建处理后的图像
        guard let processedCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: processedCGImage)
    }

    // 对单个区域应用马赛克
    private func applyMosaicToRegion(context: CGContext, region: MosaicRegion, imageSize: CGSize) {
        let blockSize = region.intensity.rawValue
        let rect = region.rect

        // 转换坐标系（UIKit坐标系到CoreGraphics坐标系）
        let flippedRect = CGRect(
            x: rect.origin.x * imageSize.width,
            y: (1 - rect.origin.y - rect.height) * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        )

        let startX = Int(flippedRect.origin.x)
        let startY = Int(flippedRect.origin.y)
        let endX = Int(flippedRect.origin.x + flippedRect.width)
        let endY = Int(flippedRect.origin.y + flippedRect.height)

        // 按块处理马赛克
        for y in stride(from: startY, to: endY, by: blockSize) {
            for x in stride(from: startX, to: endX, by: blockSize) {
                let blockRect = CGRect(
                    x: x,
                    y: y,
                    width: min(blockSize, endX - x),
                    height: min(blockSize, endY - y)
                )

                // 获取块的平均颜色
                if let averageColor = getAverageColor(context: context, rect: blockRect) {
                    context.setFillColor(averageColor)
                    context.fill(blockRect)
                }
            }
        }
    }

    // 获取指定区域的平均颜色
    private func getAverageColor(context: CGContext, rect: CGRect) -> CGColor? {
        let data = context.data
        let bytesPerPixel = 4
        let bytesPerRow = context.bytesPerRow
        let width = context.width
        let height = context.height

        guard let pixelData = data else { return nil }

        let startX = max(0, Int(rect.origin.x))
        let startY = max(0, Int(rect.origin.y))
        let endX = min(width, Int(rect.origin.x + rect.width))
        let endY = min(height, Int(rect.origin.y + rect.height))

        var totalR: Int = 0, totalG: Int = 0, totalB: Int = 0, totalA: Int = 0
        var pixelCount = 0

        for y in startY..<endY {
            for x in startX..<endX {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel
                let pixel = pixelData.assumingMemoryBound(to: UInt8.self)

                totalR += Int(pixel[pixelIndex])
                totalG += Int(pixel[pixelIndex + 1])
                totalB += Int(pixel[pixelIndex + 2])
                totalA += Int(pixel[pixelIndex + 3])
                pixelCount += 1
            }
        }

        guard pixelCount > 0 else { return nil }

        let avgR = CGFloat(totalR) / CGFloat(pixelCount) / 255.0
        let avgG = CGFloat(totalG) / CGFloat(pixelCount) / 255.0
        let avgB = CGFloat(totalB) / CGFloat(pixelCount) / 255.0
        let avgA = CGFloat(totalA) / CGFloat(pixelCount) / 255.0

        return CGColor(red: avgR, green: avgG, blue: avgB, alpha: avgA)
    }

    // 添加马赛克区域
    func addMosaicRegion(_ region: CGRect, intensity: MosaicIntensity = .high) {
        let mosaicRegion = MosaicRegion(rect: region, intensity: intensity)
        mosaicRegions.append(mosaicRegion)
    }

    // 清除所有马赛克区域
    func clearAllRegions() {
        mosaicRegions.removeAll()
    }

    // 切换区域的激活状态
    func toggleRegion(at index: Int) {
        guard index < mosaicRegions.count else { return }
        mosaicRegions[index].isActive.toggle()
    }

    // 删除指定区域
    func removeRegion(at index: Int) {
        guard index < mosaicRegions.count else { return }
        mosaicRegions.remove(at: index)
    }

    // 使用Vision框架进行文本检测（自动打码的基础）
    func detectText(in image: UIImage, completion: @escaping ([CGRect]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }

            let textRegions = observations.compactMap { observation -> CGRect? in
                // 转换坐标系
                let boundingBox = observation.boundingBox
                return CGRect(
                    x: boundingBox.origin.x,
                    y: 1 - boundingBox.origin.y - boundingBox.height,
                    width: boundingBox.width,
                    height: boundingBox.height
                )
            }

            DispatchQueue.main.async {
                completion(textRegions)
            }
        }

        // 配置文本识别
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("文本检测失败: \(error)")
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }

    // 检测可能的敏感信息区域（电话号码、身份证号等）
    func detectSensitiveInfo(in image: UIImage, completion: @escaping ([CGRect]) -> Void) {
        detectText(in: image) { textRegions in
            // 这里可以进一步筛选包含敏感信息的区域
            // 例如：匹配电话号码、身份证号、银行卡号等模式
            completion(textRegions)
        }
    }
}