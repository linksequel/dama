//
//  ContentView.swift
//  dama
//
//  Created by sequel on 2025/9/19.
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    // 状态管理
    @State private var selectedImages: [PhotosPickerItem] = []
    @State private var loadedImages: [UIImage] = []
    @State private var processedImages: [UIImage] = []  // 处理后的图像
    @State private var isAutoMosaicActive = true  // 默认激活自动打码
    @State private var isManualModeActive = false
    @State private var showingImagePicker = false
    @State private var showingImageEditor = false
    @State private var selectedImageIndex = 0
    @StateObject private var mosaicProcessor = MosaicProcessor()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 标题区域
                Text("打码页")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .padding(.top)

                Spacer()

                // 图片显示/上传区域
                imageDisplayArea

                Spacer()

                // 主要工具按钮区域
                toolButtonsArea

                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
        .photosPicker(
            isPresented: $showingImagePicker,
            selection: $selectedImages,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: selectedImages) { _, newItems in
            Task {
                await loadImages(from: newItems)
            }
        }
        .sheet(isPresented: $showingImageEditor) {
            if selectedImageIndex < loadedImages.count {
                ImageEditorView(originalImage: loadedImages[selectedImageIndex])
            }
        }
    }

    // 图片显示区域
    private var imageDisplayArea: some View {
        VStack {
            if loadedImages.isEmpty {
                // 空状态 - 显示上传提示
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)

                    Text("点击上传图片")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("支持多张图片，最多5张")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    showingImagePicker = true
                }
            } else {
                // 显示已选择的图片
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(loadedImages.enumerated()), id: \.offset) { index, image in
                            VStack {
                                // 显示处理后的图像或原始图像
                                let displayImage = index < processedImages.count ? processedImages[index] : image

                                Image(uiImage: displayImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 150, height: 180)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .onTapGesture {
                                        selectedImageIndex = index
                                        showingImageEditor = true
                                    }

                                // 图片状态指示
                                Text(index < processedImages.count ? "已处理" : "点击编辑")
                                    .font(.caption2)
                                    .foregroundColor(index < processedImages.count ? .green : .blue)
                                    .padding(.top, 4)
                            }
                        }

                        // 添加更多图片按钮
                        if loadedImages.count < 5 {
                            Button(action: {
                                showingImagePicker = true
                            }) {
                                VStack {
                                    Image(systemName: "plus")
                                        .font(.title)
                                        .foregroundColor(.blue)
                                    Text("添加")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .frame(width: 150, height: 200)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // 工具按钮区域
    private var toolButtonsArea: some View {
        VStack(spacing: 16) {
            Text("工具选择")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                // 自动打码按钮
                ToolButton(
                    title: "自动打码",
                    icon: "doc.text.viewfinder",
                    isActive: isAutoMosaicActive,
                    color: .blue
                ) {
                    activateAutoMosaic()
                }

                // 取消打码按钮
                ToolButton(
                    title: "取消打码",
                    icon: "eraser",
                    isActive: false,
                    color: .red
                ) {
                    clearAllMosaics()
                }

                // 手动打码按钮
                ToolButton(
                    title: "手动打码",
                    icon: "hand.draw",
                    isActive: isManualModeActive,
                    color: .green
                ) {
                    activateManualMode()
                }
            }
        }
    }

    // 加载选中的图片
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

    // 激活自动打码
    private func activateAutoMosaic() {
        isAutoMosaicActive = true
        isManualModeActive = false

        // 对所有图片执行自动检测和打码
        guard !loadedImages.isEmpty else {
            print("请先上传图片")
            return
        }

        processedImages = []

        for (index, image) in loadedImages.enumerated() {
            mosaicProcessor.detectSensitiveInfo(in: image) { regions in
                // 清除之前的区域
                mosaicProcessor.clearAllRegions()

                // 添加检测到的敏感区域
                for region in regions {
                    mosaicProcessor.addMosaicRegion(region, intensity: .medium)
                }

                // 应用马赛克处理
                if let processedImage = mosaicProcessor.applyMosaic(to: image, regions: mosaicProcessor.mosaicRegions) {
                    DispatchQueue.main.async {
                        // 确保数组有足够的容量
                        while self.processedImages.count <= index {
                            self.processedImages.append(image)
                        }
                        self.processedImages[index] = processedImage
                    }
                }
            }
        }

        print("激活自动打码模式 - 开始处理 \(loadedImages.count) 张图片")
    }

    // 清除所有马赛克
    private func clearAllMosaics() {
        mosaicProcessor.clearAllRegions()
        processedImages = []
        print("清除所有马赛克区域")
    }

    // 激活手动模式
    private func activateManualMode() {
        isAutoMosaicActive = false
        isManualModeActive = true

        guard !loadedImages.isEmpty else {
            print("请先上传图片后再使用手动模式")
            return
        }

        // 打开第一张图片进行编辑
        selectedImageIndex = 0
        showingImageEditor = true
        print("激活手动打码模式")
    }
}

// 工具按钮组件
struct ToolButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isActive ? .white : color)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isActive ? .white : color)
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? color : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ContentView()
}
