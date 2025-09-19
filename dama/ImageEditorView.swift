//
//  ImageEditorView.swift
//  dama
//
//  Created by sequel on 2025/9/19.
//

import SwiftUI

// 图像编辑视图 - 支持手动框选和实时预览
struct ImageEditorView: View {
    let originalImage: UIImage
    @StateObject private var mosaicProcessor = MosaicProcessor()
    @State private var processedImage: UIImage?
    @State private var isManualMode = false
    @State private var currentSelection: CGRect? = nil
    @State private var isSelecting = false
    @State private var startPoint: CGPoint = .zero
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                // 工具栏
                HStack {
                    Button("自动检测") {
                        autoDetectSensitiveAreas()
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button(isManualMode ? "完成框选" : "手动框选") {
                        isManualMode.toggle()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("清除全部") {
                        clearAllMosaics()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                .padding()

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

                // 马赛克强度选择
                VStack {
                    Text("马赛克强度")
                        .font(.headline)

                    Picker("强度", selection: $mosaicProcessor.currentIntensity) {
                        ForEach(MosaicProcessor.MosaicIntensity.allCases, id: \.self) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: mosaicProcessor.currentIntensity) { _, _ in
                        refreshProcessedImage()
                    }
                }
                .padding()

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
                        // TODO: 保存处理后的图像
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            processedImage = originalImage
        }
        .onChange(of: mosaicProcessor.mosaicRegions) { _, _ in
            refreshProcessedImage()
        }
    }

    // 自动检测敏感区域
    private func autoDetectSensitiveAreas() {
        mosaicProcessor.detectSensitiveInfo(in: originalImage) { regions in
            for region in regions {
                mosaicProcessor.addMosaicRegion(region, intensity: mosaicProcessor.currentIntensity)
            }
        }
    }

    // 添加马赛克区域
    private func addMosaicRegion(_ rect: CGRect) {
        mosaicProcessor.addMosaicRegion(rect, intensity: mosaicProcessor.currentIntensity)
    }

    // 清除所有马赛克
    private func clearAllMosaics() {
        mosaicProcessor.clearAllRegions()
        processedImage = originalImage
    }

    // 切换区域状态
    private func toggleRegion(at index: Int) {
        mosaicProcessor.toggleRegion(at: index)
    }

    // 刷新处理后的图像
    private func refreshProcessedImage() {
        guard !mosaicProcessor.mosaicRegions.isEmpty else {
            processedImage = originalImage
            return
        }

        processedImage = mosaicProcessor.applyMosaic(to: originalImage, regions: mosaicProcessor.mosaicRegions)
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
    ImageEditorView(originalImage: UIImage(systemName: "photo")!)
}