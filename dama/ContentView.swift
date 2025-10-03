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
    @State private var processedImages: [Int: UIImage] = [:]  // 处理后的图像，使用字典存储索引->图像映射
    @State private var showingImagePicker = false
    @State private var showingImageEditor = false
    @State private var selectedImageIndex = 0
    @StateObject private var mosaicProcessor = MosaicProcessor()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 标题区域
                Text("打码APP")
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
                // 原图
                let originalImage = loadedImages[selectedImageIndex]
                // 当前处理后的图片（如果有）
                let currentProcessedImage = processedImages[selectedImageIndex]

                ImageEditorView(
                    originalImage: originalImage,
                    currentImage: currentProcessedImage
                ) { processedImage in
                    // 更新处理后的图片
                    processedImages[selectedImageIndex] = processedImage
                }
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
                                let displayImage = processedImages[index] ?? image

                                ZStack(alignment: .topTrailing) {
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

                                    // 删除按钮
                                    Button(action: {
                                        removeImage(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.red))
                                    }
                                    .padding(8)
                                }

                                // 图片状态指示
                                Text(processedImages[index] != nil ? "已处理" : "点击编辑")
                                    .font(.caption2)
                                    .foregroundColor(processedImages[index] != nil ? .green : .blue)
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
        HStack(spacing: 20) {
            // 一键打码按钮
            Button(action: {
                guard !loadedImages.isEmpty else {
                    print("请先上传图片")
                    return
                }
                // 打开编辑页面让用户选择自动或手动打码
                selectedImageIndex = 0
                showingImageEditor = true
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "mosaic")
                        .font(.title2)

                    Text("一键打码")
                        .font(.headline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(loadedImages.isEmpty ? Color.gray : Color.blue)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(loadedImages.isEmpty)

            // 取消打码按钮
            Button(action: {
                clearAllMosaics()
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "eraser")
                        .font(.title2)

                    Text("取消打码")
                        .font(.headline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(processedImages.count == 0 ? Color.gray : Color.red)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(processedImages.count == 0)
        }
        .padding(.horizontal)
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

    // 清除所有马赛克
    private func clearAllMosaics() {
        mosaicProcessor.clearAllRegions()
        processedImages = [:]
        print("清除所有马赛克区域")
    }

    // 删除指定索引的图片
    private func removeImage(at index: Int) {
        guard index < loadedImages.count else { return }

        // 删除原图
        loadedImages.remove(at: index)

        // 删除对应的selectedImages项
        if index < selectedImages.count {
            selectedImages.remove(at: index)
        }

        // 重建processedImages字典，更新索引
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

        // 如果删除的是当前选中的图片，调整选中索引
        if selectedImageIndex >= loadedImages.count && loadedImages.count > 0 {
            selectedImageIndex = loadedImages.count - 1
        }

        print("已删除第 \(index + 1) 张图片")
    }
}

#Preview {
    ContentView()
}
