//
//  ImageEditorView.swift
//  dama
//
//  Created by sequel on 2025/9/19.
//

import SwiftUI
import Photos

// 图像编辑视图 - 支持手动框选和实时预览
struct ImageEditorView: View {
    let originalImage: UIImage  // 真正的原图（未打码）
    let initialImage: UIImage   // 初始显示的图片（可能已打码）
    let onComplete: (UIImage) -> Void  // 完成后的回调
    @StateObject private var mosaicProcessor = MosaicProcessor()
    @State private var processedImage: UIImage?
    @State private var isManualMode = false
    @State private var currentSelection: CGRect? = nil
    @State private var isSelecting = false
    @State private var startPoint: CGPoint = .zero
    @State private var hasAutoDetected = false  // 跟踪是否已执行自动检测
    @State private var showingSaveAlert = false  // 显示保存结果提示
    @State private var saveAlertMessage = ""  // 保存结果消息
    @Environment(\.presentationMode) var presentationMode

    // 初始化器
    init(originalImage: UIImage, currentImage: UIImage? = nil, onComplete: @escaping (UIImage) -> Void) {
        self.originalImage = originalImage
        self.initialImage = currentImage ?? originalImage
        self.onComplete = onComplete
        // 设置初始的processedImage
        _processedImage = State(initialValue: currentImage ?? originalImage)
    }

    var body: some View {
        NavigationView {
            VStack {
                // 工具栏
                HStack(spacing: 8) {
                    Button("自动检测") {
                        autoDetectSensitiveAreas()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(hasAutoDetected ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(hasAutoDetected)

                    Button(isManualMode ? "完成框选" : "手动框选") {
                        isManualMode.toggle()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(isManualMode ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(isManualMode ? .white : .primary)
                    .cornerRadius(10)

                    Button("清除全部") {
                        clearAllMosaics()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(10)

                    Button("保存") {
                        saveToPhotoLibrary()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // 图像显示区域
                GeometryReader { geometry in
                    ZStack {
                        // 显示处理后的图像或原始图像
                        if let processedImage = processedImage {
                            Image(uiImage: processedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Image(uiImage: originalImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        // 手动框选覆盖层
                        if isManualMode {
                            ManualSelectionOverlay(
                                currentSelection: $currentSelection,
                                isSelecting: $isSelecting,
                                startPoint: $startPoint,
                                onSelectionComplete: { rect in
                                    addMosaicRegion(rect)
                                }
                            )
                        }

                        // 显示现有的马赛克区域边框
                        ForEach(Array(mosaicProcessor.mosaicRegions.enumerated()), id: \.offset) { index, region in
                            if region.isActive {
                                RegionIndicator(
                                    region: region.rect,
                                    geometry: geometry,
                                    onTap: {
                                        toggleRegion(at: index)
                                    }
                                )
                            }
                        }
                    }
                }
                .clipped()

                Spacer()
            }
            .navigationTitle("图片编辑")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        // 将处理后的图像传回
                        if let finalImage = processedImage {
                            onComplete(finalImage)
                        }
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: mosaicProcessor.mosaicRegions) { _, _ in
            refreshProcessedImage()
        }
        .alert("提示", isPresented: $showingSaveAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(saveAlertMessage)
        }
    }

    // 自动检测敏感区域
    private func autoDetectSensitiveAreas() {
        // 基于当前显示的图片进行检测
        let imageToDetect = processedImage ?? initialImage
        mosaicProcessor.detectSensitiveInfo(in: imageToDetect) { regions in
            for region in regions {
                mosaicProcessor.addMosaicRegion(region, intensity: mosaicProcessor.currentIntensity)
            }
        }
        // 标记已执行过自动检测
        hasAutoDetected = true
    }

    // 添加马赛克区域
    private func addMosaicRegion(_ rect: CGRect) {
        mosaicProcessor.addMosaicRegion(rect, intensity: mosaicProcessor.currentIntensity)
    }

    // 清除所有马赛克
    private func clearAllMosaics() {
        mosaicProcessor.clearAllRegions()
        processedImage = originalImage
        // 重置自动检测状态，允许再次执行
        hasAutoDetected = false
    }

    // 切换区域状态
    private func toggleRegion(at index: Int) {
        mosaicProcessor.toggleRegion(at: index)
    }

    // 刷新处理后的图像
    private func refreshProcessedImage() {
        guard !mosaicProcessor.mosaicRegions.isEmpty else {
            processedImage = initialImage
            return
        }

        // 基于当前显示的图片应用新的马赛克
        let baseImage = processedImage ?? initialImage
        processedImage = mosaicProcessor.applyMosaic(to: baseImage, regions: mosaicProcessor.mosaicRegions)
    }

    // 保存到相册
    private func saveToPhotoLibrary() {
        guard let imageToSave = processedImage else {
            saveAlertMessage = "没有可保存的图片"
            showingSaveAlert = true
            return
        }

        // 检查相册权限
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    // 有权限，保存图片
                    UIImageWriteToSavedPhotosAlbum(imageToSave, nil, nil, nil)
                    saveAlertMessage = "图片已保存到相册"
                    showingSaveAlert = true
                    print("图片已成功保存到相册")

                case .denied, .restricted:
                    saveAlertMessage = "没有相册访问权限，请在设置中允许访问相册"
                    showingSaveAlert = true
                    print("相册访问权限被拒绝")

                case .notDetermined:
                    saveAlertMessage = "请允许访问相册"
                    showingSaveAlert = true

                @unknown default:
                    saveAlertMessage = "保存失败"
                    showingSaveAlert = true
                }
            }
        }
    }
}

// 手动选择覆盖层
struct ManualSelectionOverlay: View {
    @Binding var currentSelection: CGRect?
    @Binding var isSelecting: Bool
    @Binding var startPoint: CGPoint
    let onSelectionComplete: (CGRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 半透明覆盖层
                Color.black.opacity(0.3)

                // 当前选择区域
                if let selection = currentSelection {
                    Rectangle()
                        .stroke(Color.blue, lineWidth: 2)
                        .background(Color.blue.opacity(0.1))
                        .frame(
                            width: selection.width * geometry.size.width,
                            height: selection.height * geometry.size.height
                        )
                        .position(
                            x: (selection.midX) * geometry.size.width,
                            y: (selection.midY) * geometry.size.height
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isSelecting {
                            isSelecting = true
                            startPoint = value.startLocation
                        }

                        let currentPoint = value.location
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
                            // 确保选择区域有最小尺寸
                            if selection.width > 0.02 && selection.height > 0.02 {
                                onSelectionComplete(selection)
                            }
                        }

                        currentSelection = nil
                        isSelecting = false
                    }
            )
        }
    }
}

// 区域指示器
struct RegionIndicator: View {
    let region: CGRect
    let geometry: GeometryProxy
    let onTap: () -> Void

    var body: some View {
        Rectangle()
            .stroke(Color.red, lineWidth: 2)
            .background(Color.red.opacity(0.1))
            .frame(
                width: region.width * geometry.size.width,
                height: region.height * geometry.size.height
            )
            .position(
                x: (region.midX) * geometry.size.width,
                y: (region.midY) * geometry.size.height
            )
            .onTapGesture {
                onTap()
            }
    }
}

#Preview {
    ImageEditorView(originalImage: UIImage(systemName: "photo")!) { _ in }
}