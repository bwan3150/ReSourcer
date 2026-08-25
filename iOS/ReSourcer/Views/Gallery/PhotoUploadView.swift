//
//  PhotoUploadView.swift
//  ReSourcer
//
//  上传入口的三种来源：手机图库 / 系统文件 / 相机拍摄，统一由悬浮弹窗完成上传
//  Photos 框架操作通过 ObjC PhotoExporter 执行，避免 Swift 6 的线程断言崩溃
//

import SwiftUI
import PhotosUI
import Photos
import UIKit
import UniformTypeIdentifiers

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

// MARK: - 相机拍摄包装器

/// 包装 UIImagePickerController，调起系统相机拍照 / 录像
/// 拍摄结果先落到临时目录，再交给上传弹窗处理
struct CameraCaptureWrapper: UIViewControllerRepresentable {

    @Binding var isPresented: Bool
    /// 拍摄完成回调，参数为临时文件 URL
    let onCaptured: (URL) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureWrapper

        init(parent: CameraCaptureWrapper) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // 先回传结果再收起，确保 onChange 时结果已就绪
            if let movieURL = info[.mediaURL] as? URL {
                if let dest = Self.moveToTemporary(movieURL) {
                    parent.onCaptured(dest)
                }
            } else if let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.95),
                      let dest = Self.writeToTemporary(data: data, ext: "jpg") {
                parent.onCaptured(dest)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }

        /// 拍摄时间戳文件名前缀
        private static func timestamp() -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            return formatter.string(from: Date())
        }

        /// 把录像文件搬到自己的临时目录（系统给的路径随时可能被清理）
        static func moveToTemporary(_ url: URL) -> URL? {
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("VID_\(timestamp()).\(ext)")
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            } catch {
                return nil
            }
        }

        /// 把照片数据写入临时目录
        static func writeToTemporary(data: Data, ext: String) -> URL? {
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("IMG_\(timestamp()).\(ext)")
            do {
                try data.write(to: dest)
                return dest
            } catch {
                return nil
            }
        }
    }
}

// MARK: - 上传条目与来源

/// 待上传条目
enum UploadItem: Identifiable, Equatable {
    /// 相册资源（上传后可从相册删除）
    case photoAsset(id: String)
    /// 本地文件（系统文件 App 选中的原文件，或相机拍摄的临时文件）
    case file(url: URL)

    var id: String {
        switch self {
        case .photoAsset(let id): return "asset:\(id)"
        case .file(let url): return "file:\(url.path)"
        }
    }
}

/// 上传来源：决定弹窗文案与「上传后删除」的语义
enum UploadOrigin: Equatable {
    /// 手机图库多选
    case photoLibrary
    /// 系统文件夹多选
    case files
    /// 相机拍摄（临时文件，上传成功后自动清理）
    case camera

    /// 「上传后删除」开关标题，nil 表示不显示开关
    var deleteToggleTitle: String? {
        switch self {
        case .photoLibrary: return "上传后删除本地照片"
        case .files: return "上传后删除原文件"
        case .camera: return nil
        }
    }

    /// 开关默认值：图库沿用原有的默认勾选，文件默认不删
    var deleteDefaultsOn: Bool {
        switch self {
        case .photoLibrary: return true
        case .files, .camera: return false
        }
    }

    /// 部分失败时询问删除的文案
    var deletePromptMessage: String {
        switch self {
        case .photoLibrary: return "个文件已成功上传到服务器，是否从手机相册删除它们？"
        case .files, .camera: return "个文件已成功上传到服务器，是否删除本机上的原文件？"
        }
    }

    /// 删除完成后的结果文案
    var deletedResultNoun: String {
        switch self {
        case .photoLibrary: return "已从相册删除"
        case .files, .camera: return "已删除本地原文件"
        }
    }
}

// MARK: - 上传悬浮弹窗

/// 上传悬浮弹窗
/// - 悬浮居中弹窗（非底部抽屉）
/// - 只能通过「取消 / 完成」按钮收起，点击弹窗外侧不会关闭
/// - 上传中禁止改动「上传后删除」开关，仅允许取消上传
/// - 上传后删除仅在上传前决定；取消 / 部分失败结束时若曾勾选删除，则弹窗询问是否删除已上传的文件
struct PhotoUploadFloatingView: View {

    let apiService: APIService
    /// 待上传条目
    let items: [UploadItem]
    /// 上传来源
    let origin: UploadOrigin
    let targetFolder: String
    /// 弹窗关闭回调（负责清理选择结果并刷新列表）
    let onClose: () -> Void

    init(
        apiService: APIService,
        items: [UploadItem],
        origin: UploadOrigin,
        targetFolder: String,
        onClose: @escaping () -> Void
    ) {
        self.apiService = apiService
        self.items = items
        self.origin = origin
        self.targetFolder = targetFolder
        self.onClose = onClose
        _deleteAfterUpload = State(initialValue: origin.deleteDefaultsOn)
    }

    /// 上传流程阶段
    private enum Phase {
        case idle       // 上传前（可编辑开关、可取消/开始）
        case uploading  // 上传中（锁定开关、仅允许取消上传）
        case finished   // 已结束（可关闭）
    }

    @State private var phase: Phase = .idle
    @State private var deleteAfterUpload: Bool
    @State private var currentProgress = 0
    /// 已成功上传的条目（用于结束后按需删除本地）
    @State private var uploadedItems: [UploadItem] = []
    @State private var failedCount = 0
    @State private var cancelRequested = false
    @State private var resultText = ""
    @State private var isVisible = false
    @State private var uploadTask: Task<Void, Never>?

    /// 目标文件夹显示名
    private var targetFolderDisplayName: String {
        targetFolder.components(separatedBy: "/").last ?? "源文件夹"
    }

    private var totalCount: Int { items.count }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 背景遮罩：只吞掉点击，不再作为收起弹窗的手段（仅「取消 / 完成」可收起）
            Color.black.opacity(isVisible ? 0.5 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

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

            // 删除开关（仅上传前可改动；相机拍摄无此开关）
            deleteToggle

            // 操作按钮
            actionButtons
        }
    }

    // MARK: - 删除开关

    @ViewBuilder
    private var deleteToggle: some View {
        if let toggleTitle = origin.deleteToggleTitle {
            let locked = phase != .idle
            Button {
                guard !locked else { return }
                deleteAfterUpload.toggle()
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: deleteAfterUpload ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                    Text(toggleTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
        case .idle:
            switch origin {
            case .photoLibrary: return "square.and.arrow.up.on.square"
            case .files: return "folder.badge.plus"
            case .camera: return "camera.fill"
            }
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
        // 相机拍摄且尚未开始上传就取消：顺手清掉临时文件
        if origin == .camera && phase == .idle {
            removeLocalFiles(for: items)
        }

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
        uploadedItems = []
        failedCount = 0
        cancelRequested = false

        let pending = items
        let folder = targetFolder

        guard !pending.isEmpty else {
            phase = .idle
            GlassAlertManager.shared.showError("上传失败", message: "没有可上传的文件")
            return
        }

        // 上传前查询服务器分片策略：单文件超过阈值走分片上传，避免大文件直传失败
        // 查询失败则回退为「全部直传」（chunkSize = 0 表示不分片）
        let chunkThreshold: Int = (try? await apiService.upload.getUploadPolicy().chunkSize) ?? 0

        var cancelled = false

        // 逐个处理
        for (i, item) in pending.enumerated() {
            // 取消：在开始下一个文件前中断（进行中的文件会先完成）
            if Task.isCancelled {
                cancelled = true
                break
            }
            do {
                let pendingFile = try await exportFile(for: item)

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
                uploadedItems.append(item)
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

        await finishUpload(total: pending.count, cancelled: cancelled)
    }

    // MARK: - 结束处理

    private func finishUpload(total: Int, cancelled: Bool) async {
        phase = .finished
        let ok = uploadedItems.count

        // 结果文案
        if cancelled {
            resultText = "已取消上传，成功 \(ok)/\(total) 个"
        } else if failedCount > 0 {
            resultText = "完成：成功 \(ok) 个，失败 \(failedCount) 个"
        } else {
            resultText = "全部 \(ok) 个文件上传成功"
        }

        // 相机拍摄产生的临时文件：上传成功后即清理，不再询问
        if origin == .camera {
            removeLocalFiles(for: uploadedItems)
            return
        }

        // 删除逻辑
        guard deleteAfterUpload && !uploadedItems.isEmpty else { return }

        if cancelled || failedCount > 0 {
            // 取消 / 部分失败：询问是否删除已成功上传的文件
            promptDeleteUploaded()
        } else {
            // 全部成功：按上传前的选择直接删除本地
            await deleteLocalCopies(of: uploadedItems)
            resultText = "全部上传成功，\(origin.deletedResultNoun) \(ok) 个"
        }
    }

    /// 弹出删除确认（复用全局命令式确认弹窗）
    private func promptDeleteUploaded() {
        let done = uploadedItems
        let count = done.count
        GlassConfirmManager.shared.show(
            config: GlassConfirmConfig(
                title: "删除已上传的文件？",
                message: "有 \(count) \(origin.deletePromptMessage)",
                icon: "trash.fill",
                iconColor: .red,
                confirmTitle: "删除",
                confirmStyle: .destructive,
                cancelTitle: "保留"
            ),
            onConfirm: {
                Task { @MainActor in
                    await deleteLocalCopies(of: done)
                    resultText = "\(origin.deletedResultNoun) \(count) 个已上传文件"
                }
            }
        )
    }

    // MARK: - 导出待上传文件

    /// 把条目导出为待上传文件
    private func exportFile(for item: UploadItem) async throws -> PendingUploadFile {
        switch item {
        case .photoAsset(let assetId):
            return try await exportViaObjC(assetId: assetId)
        case .file(let url):
            return try await exportLocalFile(at: url)
        }
    }

    /// 读取本地文件（文件 App 选中的 URL 需要安全作用域）
    /// 读盘放到后台，避免大文件卡住主线程
    private func exportLocalFile(at url: URL) async throws -> PendingUploadFile {
        let data = try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url)
        }.value

        return PendingUploadFile(
            fileName: url.lastPathComponent,
            data: data,
            mimeType: PendingUploadFile.mimeType(for: url.pathExtension)
        )
    }

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

    // MARK: - 删除本地副本

    /// 按条目类型分别删除：相册资源走 Photos，本地文件走 FileManager
    private func deleteLocalCopies(of done: [UploadItem]) async {
        var assetIds: [String] = []
        var fileItems: [UploadItem] = []

        for item in done {
            switch item {
            case .photoAsset(let id): assetIds.append(id)
            case .file: fileItems.append(item)
            }
        }

        removeLocalFiles(for: fileItems)
        await deleteLocalPhotos(assetIds: assetIds)
    }

    private func deleteLocalPhotos(assetIds: [String]) async {
        guard !assetIds.isEmpty else { return }

        await withCheckedContinuation { continuation in
            PhotoExporter.deleteAssets(withIdentifiers: assetIds) { _, _ in
                continuation.resume()
            }
        }
    }

    /// 删除本机文件（部分来源为只读，删除失败时静默跳过）
    private func removeLocalFiles(for fileItems: [UploadItem]) {
        for case .file(let url) in fileItems {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
