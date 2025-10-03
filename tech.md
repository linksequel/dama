# 打码功能技术文档

## 📋 目录
1. [项目概述](#项目概述)
2. [核心架构](#核心架构)
3. [功能模块详解](#功能模块详解)
4. [技术实现原理](#技术实现原理)
5. [关键代码解析](#关键代码解析)
6. [数据流程图](#数据流程图)
7. [调试指南](#调试指南)
8. [扩展建议](#扩展建议)

---

## 项目概述

**dama** 是一个 iOS 离线图片打码应用，支持多张图片的敏感信息保护处理。

### 技术栈
- **开发语言**: Swift 5.0
- **UI框架**: SwiftUI
- **目标系统**: iOS 26.0+
- **核心框架**:
  - Vision: OCR文本识别
  - CoreImage: 图像处理
  - PhotosUI: 图片选择和保存
  - CoreGraphics: 像素级操作

### 主要功能
- ✅ 多图片上传管理（最多5张）
- ✅ 自动检测文本区域并打码（基于Vision OCR）
- ✅ 手动框选区域打码（支持累积打码）
- ✅ 实时预览马赛克效果
- ✅ 清除所有马赛克
- ✅ 删除单张图片
- ✅ 保存到相册

---

## 核心架构

### 文件结构
```
dama/
├── damaApp.swift              # App入口
├── ContentView.swift          # 主界面：图片管理、工具按钮
├── ImageEditorView.swift      # 编辑器：自动/手动打码、实时预览
└── MosaicProcessor.swift      # 核心处理器：马赛克算法、OCR检测
```

### 架构层次
```
┌─────────────────────────────────┐
│        视图层 (View)             │
│  - ContentView                  │
│  - ImageEditorView              │
│  - ManualSelectionOverlay       │
│  - RegionIndicator              │
└─────────────────────────────────┘
              ↓ 调用
┌─────────────────────────────────┐
│      业务逻辑层 (ViewModel)       │
│  - MosaicProcessor              │
│    • 状态管理 (@Published)       │
│    • 区域管理 (增删改查)          │
└─────────────────────────────────┘
              ↓ 依赖
┌─────────────────────────────────┐
│      算法层 (Core)               │
│  - Vision (OCR检测)             │
│  - CoreGraphics (像素处理)       │
│  - PhotosUI (图片I/O)            │
└─────────────────────────────────┘
```

---

## 功能模块详解

### 1. ContentView - 主视图

**职责**：
- 多图片上传与管理
- 图片预览与状态展示
- 工具按钮控制
- 图片删除功能

**核心状态**：
```swift
@State private var selectedImages: [PhotosPickerItem] = []      // 选中的图片项
@State private var loadedImages: [UIImage] = []                 // 原始图片数组
@State private var processedImages: [Int: UIImage] = [:]        // 处理后的图片字典
@State private var selectedImageIndex = 0                       // 当前选中索引
@StateObject private var mosaicProcessor = MosaicProcessor()    // 马赛克处理器
```

**关键方法**：

1. **图片加载**（ContentView.swift:222-235）
```swift
private func loadImages(from items: [PhotosPickerItem]) async {
    var newImages: [UIImage] = []

    for item in items {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            newImages.append(image)
        }
    }

    await MainActor.run {
        self.loadedImages = newImages
    }
}
```

2. **删除图片**（ContentView.swift:257-289）
```swift
private func removeImage(at index: Int) {
    guard index < loadedImages.count else { return }

    // 删除原图
    loadedImages.remove(at: index)

    // 重建processedImages字典，更新索引映射
    var newProcessedImages: [Int: UIImage] = [:]
    for (oldIndex, image) in processedImages {
        if oldIndex < index {
            newProcessedImages[oldIndex] = image  // 索引不变
        } else if oldIndex > index {
            newProcessedImages[oldIndex - 1] = image  // 索引减1
        }
        // oldIndex == index 的图片被删除
    }
    processedImages = newProcessedImages

    // 调整选中索引
    if selectedImageIndex >= loadedImages.count && loadedImages.count > 0 {
        selectedImageIndex = loadedImages.count - 1
    }
}
```

**UI组件**：

1. **图片显示区域**（ContentView.swift:76-161）
   - 空状态：虚线边框 + "点击上传图片" 提示
   - 已加载：横向滚动的图片列表
   - 图片卡片：
     - 删除按钮（右上角红色×）
     - 状态标识（"已处理" / "点击编辑"）
     - 点击编辑功能
   - 添加更多按钮（虚线边框 + 号）

2. **工具按钮区域**（ContentView.swift:163-219）
   - 一键打码：蓝色按钮，打开编辑器（默认选第一张）
   - 取消打码：红色按钮，清除所有马赛克

---

### 2. ImageEditorView - 图片编辑器

**职责**：
- 自动检测敏感区域
- 手动框选打码
- 实时预览效果
- 保存到相册

**初始化设计**（ImageEditorView.swift:28-34）：
```swift
init(originalImage: UIImage, currentImage: UIImage? = nil, onComplete: @escaping (UIImage) -> Void) {
    self.originalImage = originalImage        // 真正的原图（用于清除）
    self.initialImage = currentImage ?? originalImage  // 初始显示（支持累积打码）
    self.onComplete = onComplete             // 完成回调
    _processedImage = State(initialValue: currentImage ?? originalImage)
}
```

**核心状态**：
```swift
@State private var processedImage: UIImage?           // 当前处理后的图片
@State private var isManualMode = false               // 手动框选模式
@State private var currentSelection: CGRect? = nil    // 当前框选区域
@State private var hasAutoDetected = false            // 自动检测执行标记
@State private var showingSaveAlert = false           // 保存结果提示
```

**关键功能**：

1. **自动检测敏感区域**（ImageEditorView.swift:159-170）
```swift
private func autoDetectSensitiveAreas() {
    let imageToDetect = processedImage ?? initialImage
    mosaicProcessor.detectSensitiveInfo(in: imageToDetect) { regions in
        for region in regions {
            mosaicProcessor.addMosaicRegion(region, intensity: mosaicProcessor.currentIntensity)
        }
    }
    hasAutoDetected = true  // 防止重复检测
}
```

2. **实时预览刷新**（ImageEditorView.swift:190-200）
```swift
private func refreshProcessedImage() {
    guard !mosaicProcessor.mosaicRegions.isEmpty else {
        processedImage = initialImage
        return
    }

    // 基于当前图片累积应用马赛克
    let baseImage = processedImage ?? initialImage
    processedImage = mosaicProcessor.applyMosaic(to: baseImage, regions: mosaicProcessor.mosaicRegions)
}
```

3. **保存到相册**（ImageEditorView.swift:202-236）
```swift
private func saveToPhotoLibrary() {
    guard let imageToSave = processedImage else { return }

    PHPhotoLibrary.requestAuthorization { status in
        DispatchQueue.main.async {
            switch status {
            case .authorized, .limited:
                UIImageWriteToSavedPhotosAlbum(imageToSave, nil, nil, nil)
                saveAlertMessage = "图片已保存到相册"
                showingSaveAlert = true
            case .denied, .restricted:
                saveAlertMessage = "没有相册访问权限，请在设置中允许访问相册"
                showingSaveAlert = true
            // ...
            }
        }
    }
}
```

**UI组件**：

1. **工具栏**（ImageEditorView.swift:40-79）
   - 自动检测：蓝色/灰色（已执行），触发OCR
   - 手动框选：切换手动模式
   - 清除全部：红色，清空所有马赛克
   - 保存：绿色，保存到相册

2. **图片显示区域**（ImageEditorView.swift:82-122）
   - GeometryReader获取尺寸
   - ZStack层叠：
     - 底层：处理后的图片
     - 中层：手动框选覆盖层（半透明黑色 + 蓝色框）
     - 顶层：马赛克区域指示器（红色边框，可点击切换）

3. **手动框选覆盖层**（ImageEditorView.swift:240-300）
```swift
struct ManualSelectionOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.3)  // 半透明遮罩

                if let selection = currentSelection {
                    Rectangle()
                        .stroke(Color.blue, lineWidth: 2)
                        .background(Color.blue.opacity(0.1))
                        // ... 位置和大小计算
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // 计算归一化坐标（0-1范围）
                        let rect = CGRect(
                            x: min(startPoint.x, currentPoint.x) / geometry.size.width,
                            y: min(startPoint.y, currentPoint.y) / geometry.size.height,
                            width: abs(currentPoint.x - startPoint.x) / geometry.size.width,
                            height: abs(currentPoint.y - startPoint.y) / geometry.size.height
                        )
                        currentSelection = rect
                    }
                    .onEnded { _ in
                        if let selection = currentSelection,
                           selection.width > 0.02 && selection.height > 0.02 {
                            onSelectionComplete(selection)
                        }
                    }
            )
        }
    }
}
```

---

### 3. MosaicProcessor - 马赛克处理器

**职责**：
- 核心打码算法
- OCR文本检测
- 马赛克区域管理

**数据结构**：

```swift
enum MosaicIntensity: Int {
    case high = 20  // 高强度：20x20像素块
}

struct MosaicRegion {
    let rect: CGRect              // 归一化坐标（0-1）
    let intensity: MosaicIntensity
    var isActive: Bool = true     // 激活状态
}

@Published var mosaicRegions: [MosaicRegion] = []
@Published var currentIntensity: MosaicIntensity = .high
```

**核心算法**：

1. **像素块马赛克**（MosaicProcessor.swift:42-71）
```swift
func applyMosaic(to image: UIImage, regions: [MosaicRegion]) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }

    let width = cgImage.width
    let height = cgImage.height

    // 创建绘图上下文
    guard let context = CGContext(...) else { return nil }

    // 绘制原图
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // 应用马赛克到每个激活区域
    for region in regions where region.isActive {
        applyMosaicToRegion(context: context, region: region, imageSize: CGSize(...))
    }

    // 生成处理后的图像
    guard let processedCGImage = context.makeImage() else { return nil }
    return UIImage(cgImage: processedCGImage)
}
```

2. **区域马赛克处理**（MosaicProcessor.swift:74-108）
```swift
private func applyMosaicToRegion(context: CGContext, region: MosaicRegion, imageSize: CGSize) {
    let blockSize = region.intensity.rawValue  // 20

    // 坐标系转换（UIKit → CoreGraphics）
    let flippedRect = CGRect(
        x: rect.origin.x * imageSize.width,
        y: (1 - rect.origin.y - rect.height) * imageSize.height,
        width: rect.width * imageSize.width,
        height: rect.height * imageSize.height
    )

    // 按块处理
    for y in stride(from: startY, to: endY, by: blockSize) {
        for x in stride(from: startX, to: endX, by: blockSize) {
            let blockRect = CGRect(x: x, y: y, width: blockSize, height: blockSize)

            // 计算块的平均颜色
            if let averageColor = getAverageColor(context: context, rect: blockRect) {
                // 用平均颜色填充整个块
                context.setFillColor(averageColor)
                context.fill(blockRect)
            }
        }
    }
}
```

3. **平均颜色计算**（MosaicProcessor.swift:110-149）
```swift
private func getAverageColor(context: CGContext, rect: CGRect) -> CGColor? {
    let pixelData = context.data  // 直接访问像素数据

    var totalR = 0, totalG = 0, totalB = 0, totalA = 0
    var pixelCount = 0

    // 遍历块内所有像素
    for y in startY..<endY {
        for x in startX..<endX {
            let pixelIndex = y * bytesPerRow + x * bytesPerPixel
            let pixel = pixelData.assumingMemoryBound(to: UInt8.self)

            totalR += Int(pixel[pixelIndex])      // Red
            totalG += Int(pixel[pixelIndex + 1])  // Green
            totalB += Int(pixel[pixelIndex + 2])  // Blue
            totalA += Int(pixel[pixelIndex + 3])  // Alpha
            pixelCount += 1
        }
    }

    // 计算平均值并归一化到0-1
    let avgR = CGFloat(totalR) / CGFloat(pixelCount) / 255.0
    let avgG = CGFloat(totalG) / CGFloat(pixelCount) / 255.0
    let avgB = CGFloat(totalB) / CGFloat(pixelCount) / 255.0
    let avgA = CGFloat(totalA) / CGFloat(pixelCount) / 255.0

    return CGColor(red: avgR, green: avgG, blue: avgB, alpha: avgA)
}
```

4. **Vision OCR检测**（MosaicProcessor.swift:175-219）
```swift
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

        // 坐标系转换（Vision → UIKit）
        let textRegions = observations.compactMap { observation -> CGRect? in
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

    request.recognitionLevel = .fast  // 快速模式
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
```

---

## 技术实现原理

### 1. 坐标系统设计

应用采用**归一化坐标系**（0-1范围）存储马赛克区域：

**优势**：
- 独立于图片分辨率
- 支持缩放和不同尺寸显示
- 简化计算和转换

**坐标系对比**：

```
Vision 坐标系               UIKit 坐标系             CoreGraphics 坐标系
(左下角为原点)              (左上角为原点)            (左下角为原点)

  ↑ y                         → x                      ↑ y
  │                           ↓ y                      │
  │    ┌─────┐                ┌─────┐                  │    ┌─────┐
  │    │     │                │     │                  │    │     │
  │    └─────┘                └─────┘                  │    └─────┘
  └───────→ x                                          └───────→ x
```

**转换公式**：

```swift
// Vision → UIKit
let uikitY = 1 - visionY - visionHeight

// UIKit → CoreGraphics
let cgY = (1 - uikitY - height) * imageHeight

// 归一化坐标 → 像素坐标
let pixelX = normalizedX * imageWidth
let pixelY = normalizedY * imageHeight
```

### 2. 状态管理策略

**ContentView（主视图）**：
- `loadedImages`: 原始图片数组（顺序存储）
- `processedImages`: 字典映射 `[索引: 处理后图片]`
- 字典设计优势：
  - 支持部分处理（不是所有图片都必须处理）
  - 独立管理每张图片的处理状态
  - 删除图片时重建索引映射

**ImageEditorView（编辑器）**：
- `originalImage`: 不可变原图（用于清除操作）
- `initialImage`: 初始显示的图片（可能已打码）
- `processedImage`: 当前处理结果（支持累积打码）

**MosaicProcessor（处理器）**：
- `@Published var mosaicRegions`: 触发SwiftUI自动更新
- `onChange`监听器实现实时预览

### 3. 马赛克算法原理

**像素化本质**：降低图像分辨率，将多个像素块合并为一个颜色。

```
原始图片 (高清)          马赛克图片 (模糊)
┌─┬─┬─┬─┐              ┌───┬───┐
│A│B│C│D│              │ E │ F │
├─┼─┼─┼─┤      →       │   │   │
│E│F│G│H│              ├───┼───┤
│I│J│K│L│              │ G │ H │
└─┴─┴─┴─┘              └───┴───┘

E = avg(A,B,E,F)  # 计算2x2块的平均颜色
```

**算法流程**：
1. 创建CGContext绘图上下文
2. 绘制原始图像
3. 遍历每个马赛克区域：
   - 按块大小（20x20）分割
   - 计算每个块的平均RGBA值
   - 用平均颜色填充整个块
4. 生成处理后的CGImage

### 4. 性能优化

**异步处理**：
- 图片加载：`async/await`
- OCR检测：`DispatchQueue.global(qos: .userInitiated)`
- 主线程更新：`DispatchQueue.main.async`

**内存管理**：
- 使用字典存储处理后图片，避免全量复制
- CGContext直接操作像素数据
- 删除图片时重建索引映射

**UI性能**：
- GeometryReader获取实际尺寸
- `.clipped()`限制绘制区域
- 条件渲染（if/else）避免无效计算

---

## 关键代码解析

### 1. 图片删除与索引重建

```swift
// ContentView.swift:257-289
private func removeImage(at index: Int) {
    guard index < loadedImages.count else { return }

    // 1. 删除原图
    loadedImages.remove(at: index)

    // 2. 删除对应的selectedImages项
    if index < selectedImages.count {
        selectedImages.remove(at: index)
    }

    // 3. 重建processedImages字典，更新索引
    var newProcessedImages: [Int: UIImage] = [:]
    for (oldIndex, image) in processedImages {
        if oldIndex < index {
            // 索引小于删除位置的保持不变
            newProcessedImages[oldIndex] = image
        } else if oldIndex > index {
            // 索引大于删除位置的需要减1
            newProcessedImages[oldIndex - 1] = image
        }
        // oldIndex == index 的图片被删除，不加入新字典
    }
    processedImages = newProcessedImages

    // 4. 调整选中索引
    if selectedImageIndex >= loadedImages.count && loadedImages.count > 0 {
        selectedImageIndex = loadedImages.count - 1
    }

    print("已删除第 \(index + 1) 张图片")
}
```

**关键点**：
- 字典索引映射更新逻辑
- 防止越界的安全检查
- 同步更新多个状态

### 2. 累积打码实现

```swift
// ImageEditorView.swift:190-200
private func refreshProcessedImage() {
    guard !mosaicProcessor.mosaicRegions.isEmpty else {
        processedImage = initialImage
        return
    }

    // 基于当前图片累积应用马赛克
    let baseImage = processedImage ?? initialImage
    processedImage = mosaicProcessor.applyMosaic(to: baseImage, regions: mosaicProcessor.mosaicRegions)
}
```

**关键点**：
- 每次在当前图片基础上应用新的马赛克
- 支持多次打码（不会重复覆盖）
- 清除时回到initialImage

### 3. 手动框选手势识别

```swift
// ImageEditorView.swift:268-297
DragGesture()
    .onChanged { value in
        if !isSelecting {
            isSelecting = true
            startPoint = value.startLocation
        }

        let currentPoint = value.location
        // 计算归一化坐标矩形
        let rect = CGRect(
            x: min(startPoint.x, currentPoint.x) / geometry.size.width,
            y: min(startPoint.y, currentPoint.y) / geometry.size.height,
            width: abs(currentPoint.x - startPoint.x) / geometry.size.width,
            height: abs(currentPoint.y - startPoint.y) / geometry.size.height
        )

        currentSelection = rect
    }
    .onEnded { _ in
        if let selection = currentSelection, isSelecting {
            // 最小尺寸验证（2%）
            if selection.width > 0.02 && selection.height > 0.02 {
                onSelectionComplete(selection)
            }
        }

        currentSelection = nil
        isSelecting = false
    }
```

**关键点**：
- 归一化坐标计算（除以geometry.size）
- 最小区域验证避免误触
- 实时预览反馈

---

## 数据流程图

### 完整工作流程

```
用户选择图片
    ↓
PhotosPicker → selectedImages更新
    ↓
onChange触发 → loadImages(from:)
    ↓
异步加载 → loadedImages更新
    ↓
UI显示图片列表（横向滚动）
    ↓
用户点击"一键打码" / 点击图片
    ↓
打开ImageEditorView (sheet模态)
    ↓
┌───────────────────────────┐
│     编辑器操作             │
│                           │
│ ┌─────────┐ ┌──────────┐ │
│ │自动检测  │ │手动框选   │ │
│ └────┬────┘ └─────┬────┘ │
│      │             │      │
│      ↓             ↓      │
│   OCR检测      DragGesture│
│      │             │      │
│      └─────┬───────┘      │
│            ↓              │
│    addMosaicRegion()      │
│            ↓              │
│  refreshProcessedImage()  │
│            ↓              │
│     实时预览更新           │
└───────────────────────────┘
    ↓
点击"完成" → onComplete(processedImage)
    ↓
更新processedImages[index]
    ↓
ContentView显示"已处理"状态
```

### 自动打码流程

```
点击"自动检测"按钮
    ↓
autoDetectSensitiveAreas()
    ↓
mosaicProcessor.detectSensitiveInfo(in: image)
    ↓
Vision VNRecognizeTextRequest
    ↓
DispatchQueue.global异步执行
    ↓
识别文本边界框
    ↓
坐标转换（Vision → UIKit）
    ↓
批量addMosaicRegion()
    ↓
onChange监听mosaicRegions
    ↓
refreshProcessedImage()
    ↓
applyMosaic()应用像素块算法
    ↓
DispatchQueue.main更新UI
    ↓
显示马赛克效果
```

### 手动打码流程

```
点击"手动框选"按钮
    ↓
isManualMode = true
    ↓
显示ManualSelectionOverlay
    ↓
用户拖拽手势
    ↓
DragGesture.onChanged
    ↓
计算归一化坐标矩形（0-1范围）
    ↓
实时更新currentSelection
    ↓
蓝色框实时显示
    ↓
DragGesture.onEnded
    ↓
验证最小尺寸（>2%）
    ↓
onSelectionComplete(rect)
    ↓
addMosaicRegion(rect)
    ↓
触发refreshProcessedImage()
    ↓
应用马赛克并更新UI
```

---

## 调试指南

### 常见问题排查

#### 1️⃣ 自动打码没有检测到文本

**可能原因**：
- 图片分辨率太低
- 文字太小或模糊
- 光照条件不佳

**调试方法**：
```swift
// 在 MosaicProcessor.swift:181 添加日志
func detectText(in image: UIImage, completion: @escaping ([CGRect]) -> Void) {
    let request = VNRecognizeTextRequest { request, error in
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            print("❌ 未检测到文本")
            completion([])
            return
        }

        print("✅ 检测到 \(observations.count) 个文本区域")
        for (index, obs) in observations.enumerated() {
            print("区域 \(index): \(obs.boundingBox)")
            if let text = obs.topCandidates(1).first?.string {
                print("  内容: \(text)")
            }
        }

        // ... 后续代码
    }
}
```

**解决方案**：
- 调整 `recognitionLevel` 为 `.accurate`（更慢但更准确）
- 增强图片对比度预处理

#### 2️⃣ 手动框选区域不准确

**可能原因**：
- 坐标系转换错误
- 图片缩放导致坐标偏移

**调试方法**：
```swift
// 在 ImageEditorView.swift:286 添加日志
.onEnded { _ in
    if let selection = currentSelection {
        print("框选区域（归一化）: \(selection)")
        print("框选区域（像素）: x=\(selection.x * imageSize.width), y=\(selection.y * imageSize.height)")
    }
}
```

#### 3️⃣ 马赛克效果不明显

**可能原因**：
- `blockSize` 太小
- 区域面积太小

**解决方案**：
```swift
// 调整 MosaicIntensity 的像素块大小
enum MosaicIntensity: Int {
    case high = 30  // 从20增加到30，更模糊
}
```

#### 4️⃣ 处理大图片时卡顿

**优化方案**：
```swift
// 在后台线程处理马赛克
DispatchQueue.global(qos: .userInitiated).async {
    if let processedImage = mosaicProcessor.applyMosaic(to: image, regions: regions) {
        DispatchQueue.main.async {
            self.processedImage = processedImage
        }
    }
}
```

#### 5️⃣ 删除图片后处理状态错乱

**检查点**：
- `processedImages`字典索引是否正确重建
- `selectedImageIndex`是否越界
- `selectedImages`是否同步删除

**调试代码**：
```swift
// ContentView.swift:257 添加日志
private func removeImage(at index: Int) {
    print("删除前 processedImages: \(processedImages.keys.sorted())")

    // ... 删除逻辑

    print("删除后 processedImages: \(processedImages.keys.sorted())")
    print("当前 loadedImages.count: \(loadedImages.count)")
}
```

### 调试工具推荐

| 工具 | 用途 |
|------|------|
| **Xcode Instruments** | 性能分析、内存泄漏检测 |
| **po 命令** | 在断点处打印变量 `po mosaicRegions` |
| **View Hierarchy Debugger** | 检查UI层级和布局 |
| **Simulator Camera** | 模拟相机拍摄测试 |

### 关键断点位置

1. **自动检测回调**：`ImageEditorView.swift:163`
   ```swift
   mosaicProcessor.detectSensitiveInfo(in: imageToDetect) { regions in
       // 断点：检查检测到的区域数量
   }
   ```

2. **马赛克应用**：`MosaicProcessor.swift:42`
   ```swift
   func applyMosaic(to image: UIImage, regions: [MosaicRegion]) -> UIImage? {
       // 断点：检查区域参数
   }
   ```

3. **手动框选完成**：`ImageEditorView.swift:286`
   ```swift
   .onEnded { _ in
       // 断点：检查框选坐标
   }
   ```

4. **图片删除**：`ContentView.swift:258`
   ```swift
   private func removeImage(at index: Int) {
       // 断点：检查索引重建逻辑
   }
   ```

---

## 扩展建议

### 1. 功能增强

- **正则匹配敏感信息**：在`detectSensitiveInfo`中添加电话号码、身份证号等模式识别
  ```swift
  func detectSensitiveInfo(in image: UIImage, completion: @escaping ([CGRect]) -> Void) {
      detectText(in: image) { textRegions in
          // 过滤敏感信息
          let sensitiveRegions = textRegions.filter { region in
              // 正则匹配电话号码、身份证等
              return matchesSensitivePattern(region)
          }
          completion(sensitiveRegions)
      }
  }
  ```

- **马赛克强度可调**：支持低、中、高三档
  ```swift
  enum MosaicIntensity: Int, CaseIterable {
      case low = 10     // 低强度：10x10像素块
      case medium = 20  // 中强度：20x20像素块
      case high = 30    // 高强度：30x30像素块
  }
  ```

- **人脸识别**：使用`VNDetectFaceRectanglesRequest`
  ```swift
  func detectFaces(in image: UIImage, completion: @escaping ([CGRect]) -> Void) {
      let request = VNDetectFaceRectanglesRequest { request, error in
          // 处理人脸检测结果
      }
      // ...
  }
  ```

- **批量处理**：一键处理所有图片
  ```swift
  func processAllImages() {
      for (index, image) in loadedImages.enumerated() {
          // 自动检测并应用马赛克
      }
  }
  ```

- **撤销重做**：操作历史栈
  ```swift
  @State private var operationHistory: [MosaicOperation] = []
  @State private var historyIndex = -1

  func undo() {
      if historyIndex > 0 {
          historyIndex -= 1
          applyOperation(operationHistory[historyIndex])
      }
  }
  ```

### 2. 性能优化

- **图片压缩**：大图自动缩放处理
  ```swift
  func compressImage(_ image: UIImage, maxSize: CGFloat = 1920) -> UIImage {
      let ratio = min(maxSize / image.size.width, maxSize / image.size.height)
      if ratio < 1 {
          let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
          // 缩放处理
      }
      return image
  }
  ```

- **缓存策略**：处理结果本地缓存
  ```swift
  private let imageCache = NSCache<NSString, UIImage>()

  func cacheProcessedImage(_ image: UIImage, for key: String) {
      imageCache.setObject(image, forKey: key as NSString)
  }
  ```

- **增量更新**：仅重新渲染变化区域
  ```swift
  func applyMosaicIncremental(to image: UIImage, newRegion: MosaicRegion) -> UIImage? {
      // 只处理新增区域，避免全图重新计算
  }
  ```

### 3. 用户体验

- **快捷手势**：双指缩放、双击清除
- **预设模板**：常用打码区域模板（身份证、银行卡）
- **导出格式**：支持PNG/JPEG选择
- **分享功能**：直接分享到社交平台

---

## 快速上手 Checklist

- [ ] 理解 `ContentView`、`ImageEditorView`、`MosaicProcessor` 三个文件的职责
- [ ] 掌握 Vision 框架的基本用法（OCR文本识别）
- [ ] 理解归一化坐标系（0-1 范围）
- [ ] 熟悉马赛克算法的像素块平均颜色计算
- [ ] 学会使用 Xcode 调试工具排查问题
- [ ] 了解 SwiftUI 的 `@State`、`@Binding`、`@Published` 状态管理
- [ ] 掌握坐标系转换（Vision、UIKit、CoreGraphics）
- [ ] 理解累积打码的实现原理
- [ ] 熟悉字典索引映射更新逻辑（删除图片）

---

**文档版本：** v2.0
**最后更新：** 2025-10-03
**维护者：** dama 开发团队
