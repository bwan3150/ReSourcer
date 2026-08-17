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

// MARK: - 上传悬浮弹窗

/// 照片上传悬浮弹窗
/// - 悬浮居中弹窗（非底部抽屉）
/// - 上传中禁止收起弹窗、禁止改动「上传后删除」开关，仅允许取消上传
/// - 上传后删除仅在上传前决定；取消 / 部分失败结束时若曾勾选删除，则弹窗询问是否删除已上传的文件
struct PhotoUploadFloatingView: View {

    let apiService: APIService
    let pickerResults: [PHPickerResult]
    let targetFolder: String
    /// 弹窗关闭回调（负责清理选择结果并刷新列表）
    let onClose: () -> Void

    /// 上传流程阶段
    private enum Phase {
        case idle       // 上传前（可编辑开关、可取消/开始）
        case uploading  // 上传中（锁定开关、仅允许取消上传、禁止收起）
        case finished   // 已结束（可关闭）
    }

    @State private var phase: Phase = .idle
    @State private var deleteAfterUpload = true
    @State private var currentProgress = 0
    /// 已成功上传的 assetId（用于结束后按需删除本地）
    @State private var uploadedAssetIds: [String] = []
    @State private var failedCount = 0
    @State private var cancelRequested = false
    @State private var resultText = ""
    @State private var isVisible = false
    @State private var uploadTask: Task<Void, Never>?

    /// 目标文件夹显示名
    private var targetFolderDisplayName: String {
        targetFolder.components(separatedBy: "/").last ?? "源文件夹"
    }

    private var totalCount: Int { pickerResults.count }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 背景遮罩：上传中禁止点击收起
            Color.black.opacity(isVisible ? 0.5 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    if phase != .uploading {
                        close()
                    }
                }

            card
                .padding(AppTheme.Spacing.xxl)
                .frame(maxWidth: 340)
                .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
                .padding(.horizontal, AppTheme.Spacing.xl)
                .scaleEffect(isVisible ? 1 : 0.85)
                .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(AppTheme.Animation.spring) {
                isVisible = true
            }
        }
    }

    // MARK: - 卡片内容

    private var card: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // 图标
            Image(systemName: phaseIcon)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(phaseIconColor)

            // 标题
            Text(phaseTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            // 描述 / 结果
            Text(phase == .finished ? resultText : "将上传 \(totalCount) 个文件至「\(targetFolderDisplayName)」")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // 进度条
            if phase != .idle {
                VStack(spacing: AppTheme.Spacing.xs) {
                    ProgressView(value: Double(currentProgress), total: Double(max(totalCount, 1)))
                        .tint(.primary)
                    Text("\(currentProgress)/\(totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // 删除开关（仅上传前可改动）
            deleteToggle

            // 操作按钮
            actionButtons
        }
    }

    // MARK: - 删除开关

    @ViewBuilder
    private var deleteToggle: some View {
        let locked = phase != .idle
        Button {
            guard !locked else { return }
            deleteAfterUpload.toggle()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: deleteAfterUpload ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                Text("上传后删除本地照片")
                    .font(.subheadline)
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(locked ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    // MARK: - 按钮区

    @ViewBuilder
    private var actionButtons: some View {
        switch phase {
        case .idle:
            HStack(spacing: AppTheme.Spacing.md) {
                GlassButton("取消", style: .secondary, size: .medium) {
                    close()
                }
                .frame(maxWidth: .infinity)

                GlassButton("上传", icon: "arrow.up", style: .primary, size: .medium) {
                    uploadTask = Task { await startUpload() }
                }
                .frame(maxWidth: .infinity)
            }
        case .uploading:
            GlassButton(cancelRequested ? "正在取消…" : "取消上传",
                        icon: "stop.fill", style: .destructive, size: .medium,
                        isEnabled: !cancelRequested) {
                cancelRequested = true
                uploadTask?.cancel()
            }
            .frame(maxWidth: .infinity)
        case .finished:
            GlassButton("完成", icon: "checkmark", style: .primary, size: .medium) {
                close()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 阶段展示

    private var phaseIcon: String {
        switch phase {
        case .idle: return "square.and.arrow.up.on.square"
        case .uploading: return "arrow.up.circle"
        case .finished: return failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        }
    }

    private var phaseIconColor: Color {
        switch phase {
        case .idle: return .blue
        case .uploading: return .blue
        case .finished: return failedCount > 0 ? .orange : .green
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .idle: return "上传到「\(targetFolderDisplayName)」"
        case .uploading: return "正在上传…"
        case .finished: return "上传结束"
        }
    }

    // MARK: - 关闭

    private func close() {
        withAnimation(AppTheme.Animation.quick) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onClose()
        }
    }

    // MARK: - 上传逻辑

    private func startUpload() async {
        phase = .uploading
        currentProgress = 0
        uploadedAssetIds = []
        failedCount = 0
        cancelRequested = false

        // 收集所有 assetIdentifier
        let assetIds = pickerResults.compactMap(\.assetIdentifier)
        let folder = targetFolder

        guard !assetIds.isEmpty else {
            phase = .idle
            GlassAlertManager.shared.showError("上传失败", message: "无法访问所选照片")
            return
        }

        // 上传前查询服务器分片策略：单文件超过阈值走分片上传，避免大文件直传失败
        // 查询失败则回退为「全部直传」（chunkSize = 0 表示不分片）
        let chunkThreshold: Int = (try? await apiService.upload.getUploadPolicy().chunkSize) ?? 0

        var cancelled = false

        // 逐个处理
        for (i, assetId) in assetIds.enumerated() {
            // 取消：在开始下一个文件前中断（进行中的文件会先完成）
            if Task.isCancelled {
                cancelled = true
                break
            }
            do {
                // 通过 ObjC PhotoExporter 导出文件（避免 Swift 6 线程断言）
                let pendingFile = try await exportViaObjC(assetId: assetId)

                if chunkThreshold > 0 && pendingFile.data.count > chunkThreshold {
                    // 大文件：分片上传（服务端合并）
                    _ = try await apiService.upload.uploadFileChunked(
                        fileName: pendingFile.fileName,
                        data: pendingFile.data,
                        to: folder,
                        chunkSize: chunkThreshold
                    )
                } else {
                    // 小文件：原有直传
                    _ = try await apiService.upload.uploadFiles([pendingFile], to: folder)
                }
                uploadedAssetIds.append(assetId)
            } catch {
                // 取消导致的中断不计入失败
                if Task.isCancelled {
                    cancelled = true
                    break
                }
                failedCount += 1
                print("文件上传失败[\(i)]: \(error.localizedDescription)")
            }

            currentProgress = i + 1
        }

        await finishUpload(total: assetIds.count, cancelled: cancelled)
    }

    // MARK: - 结束处理

    private func finishUpload(total: Int, cancelled: Bool) async {
        phase = .finished
        let ok = uploadedAssetIds.count

        // 结果文案
        if cancelled {
            resultText = "已取消上传，成功 \(ok)/\(total) 个"
        } else if failedCount > 0 {
            resultText = "完成：成功 \(ok) 个，失败 \(failedCount) 个"
        } else {
            resultText = "全部 \(ok) 个文件上传成功"
        }

        // 删除逻辑
        guard deleteAfterUpload && !uploadedAssetIds.isEmpty else { return }

        if cancelled || failedCount > 0 {
            // 取消 / 部分失败：询问是否删除已成功上传的文件
            promptDeleteUploaded()
        } else {
            // 全部成功：按上传前的选择直接删除本地
            await deleteLocalPhotos(assetIds: uploadedAssetIds)
            resultText = "全部上传成功，已从相册删除 \(ok) 个"
        }
    }

    /// 弹出删除确认（复用全局命令式确认弹窗）
    private func promptDeleteUploaded() {
        let ids = uploadedAssetIds
        let count = ids.count
        GlassConfirmManager.shared.show(
            config: GlassConfirmConfig(
                title: "删除已上传的文件？",
                message: "有 \(count) 个文件已成功上传到服务器，是否从手机相册删除它们？",
                icon: "trash.fill",
                iconColor: .red,
                confirmTitle: "删除",
                confirmStyle: .destructive,
                cancelTitle: "保留"
            ),
            onConfirm: {
                Task { @MainActor in
                    await deleteLocalPhotos(assetIds: ids)
                    resultText = "已从相册删除 \(count) 个已上传文件"
                }
            }
        )
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
