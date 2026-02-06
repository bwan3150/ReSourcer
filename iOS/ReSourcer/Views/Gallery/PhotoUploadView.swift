//
//  PhotoUploadView.swift
//  ReSourcer
//
//  从手机相册选择照片/视频上传到服务器，支持上传后删除本地照片
//  Photos 框架操作通过 ObjC PhotoExporter 执行，避免 Swift 6 的线程断言崩溃
//

import SwiftUI
import PhotosUI
import Photos

// MARK: - PHPicker SwiftUI 包装器

/// 包装 PHPickerViewController，以获取 assetIdentifier 用于上传后删除本地照片
struct PHPickerWrapper: UIViewControllerRepresentable {

    @Binding var isPresented: Bool
    let maxSelection: Int
    let onPicked: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = maxSelection
        config.filter = .any(of: [.images, .videos])
        config.selection = .ordered

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerWrapper

        init(parent: PHPickerWrapper) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            if !results.isEmpty {
                parent.onPicked(results)
            }
        }
    }
}

// MARK: - 上传确认面板

/// 照片上传确认视图 — 显示在 GlassBottomSheet 内
struct PhotoUploadConfirmView: View {

    let apiService: APIService
    let pickerResults: [PHPickerResult]
    let targetFolder: String
    let onUploadStarted: () -> Void
    let onCancel: () -> Void

    @State private var deleteAfterUpload = true
    @State private var isUploading = false
    @State private var currentProgress: Int = 0

    /// 目标文件夹显示名
    private var targetFolderDisplayName: String {
        targetFolder.components(separatedBy: "/").last ?? "源文件夹"
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // 上传描述
            Text("将上传 \(pickerResults.count) 个文件至 \(targetFolderDisplayName)")
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 上传进度
            if isUploading {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView(value: Double(currentProgress), total: Double(pickerResults.count))
                        .tint(.primary)
                    Text("\(currentProgress)/\(pickerResults.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // 删除选项
            Button {
                deleteAfterUpload.toggle()
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: deleteAfterUpload ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                    Text("上传后删除本地照片")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // 操作按钮
            HStack(spacing: AppTheme.Spacing.md) {
                GlassButton("取消", style: .secondary, size: .medium) {
                    onCancel()
                }
                .frame(maxWidth: .infinity)

                GlassButton("上传", icon: "arrow.up", style: .primary, size: .medium,
                            isLoading: isUploading) {
                    Task { await startUpload() }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer().frame(height: 60)
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: - 上传逻辑

    private func startUpload() async {
        isUploading = true
        currentProgress = 0

        // 收集所有 assetIdentifier
        let assetIds = pickerResults.compactMap(\.assetIdentifier)
        let folder = targetFolder

        guard !assetIds.isEmpty else {
            isUploading = false
            GlassAlertManager.shared.showError("上传失败", message: "无法访问所选照片")
            return
        }

        var uploadedAssetIds: [String] = []
        var totalUploaded = 0

        // 逐个处理
        for (i, assetId) in assetIds.enumerated() {
            do {
                // 通过 ObjC PhotoExporter 导出文件（避免 Swift 6 线程断言）
                let pendingFile = try await exportViaObjC(assetId: assetId)

                // 上传
                _ = try await apiService.upload.uploadFiles([pendingFile], to: folder)
                totalUploaded += 1
                uploadedAssetIds.append(assetId)
            } catch {
                print("文件上传失败[\(i)]: \(error.localizedDescription)")
            }

            currentProgress = i + 1
        }

        guard totalUploaded > 0 else {
            isUploading = false
            GlassAlertManager.shared.showError("上传失败", message: "没有文件上传成功")
            return
        }

        // 可选删除本地照片
        if deleteAfterUpload {
            await deleteLocalPhotos(assetIds: uploadedAssetIds)
        }

        isUploading = false
        GlassAlertManager.shared.showSuccess("已添加 \(totalUploaded) 个上传任务")
        onUploadStarted()
    }

    // MARK: - ObjC 桥接导出

    /// 通过 Objective-C PhotoExporter 导出 asset（绕过 Swift 6 线程限制）
    private func exportViaObjC(assetId: String) async throws -> PendingUploadFile {
        try await withCheckedThrowingContinuation { continuation in
            PhotoExporter.exportAsset(withIdentifier: assetId) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result = result else {
                    continuation.resume(throwing: NSError(
                        domain: "PhotoUpload", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "导出结果为空"]
                    ))
                    return
                }

                let file = PendingUploadFile(
                    fileName: result.fileName,
                    data: result.data,
                    mimeType: result.mimeType
                )
                continuation.resume(returning: file)
            }
        }
    }

    // MARK: - 删除本地照片

    private func deleteLocalPhotos(assetIds: [String]) async {
        guard !assetIds.isEmpty else { return }

        await withCheckedContinuation { continuation in
            PhotoExporter.deleteAssets(withIdentifiers: assetIds) { _, _ in
                continuation.resume()
            }
        }
    }
}
