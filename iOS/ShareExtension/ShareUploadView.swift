//
//  ShareUploadView.swift
//  ShareExtension
//
//  Flow B：在 Share Extension 内选服务器 / 源 / 子文件夹并上传。
//  小文件前台直传；大文件 background URLSession（关掉弹窗可续传）。
//

import SwiftUI

struct ShareUploadView: View {

    let fileURLs: [URL]
    let imageItems: [ShareImageItem]
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var servers: [Server] = []
    @State private var selectedServerId: String = ""
    @State private var sourceFolders: [String] = []
    @State private var selectedSource: String = ""
    @State private var subfolders: [FolderInfo] = []
    @State private var selectedSubfolder: String = "" // empty = source root

    @State private var isLoadingMeta = false
    @State private var isUploading = false
    @State private var progressText = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var selectedServer: Server? {
        servers.first { $0.id == selectedServerId }
    }

    private var targetFolder: String {
        if selectedSubfolder.isEmpty { return selectedSource }
        return "\(selectedSource)/\(selectedSubfolder)"
    }

    private var fileCount: Int { fileURLs.count + imageItems.count }

    var body: some View {
        Form {
            Section("目标") {
                Picker("服务器", selection: $selectedServerId) {
                    ForEach(servers) { server in
                        // 必须同时展示名称与 URL，否则公网/局域网无法区分
                        Text(ShareBridge.sharePickerLabel(for: server))
                            .tag(server.id)
                    }
                }
                .accessibilityIdentifier("shareServerPicker")
                .onChange(of: selectedServerId) { _, _ in
                    Task { await reloadSources() }
                }

                if sourceFolders.isEmpty {
                    Text(isLoadingMeta ? "加载源文件夹…" : (errorMessage ?? "无可用源文件夹"))
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                        .accessibilityIdentifier("shareSourceFoldersStatus")
                } else {
                    Picker("源文件夹", selection: $selectedSource) {
                        ForEach(sourceFolders, id: \.self) { path in
                            Text(displayName(for: path)).tag(path)
                        }
                    }
                    .onChange(of: selectedSource) { _, _ in
                        Task { await reloadSubfolders() }
                    }
                }

                Picker("子文件夹", selection: $selectedSubfolder) {
                    Text("（源文件夹根目录）").tag("")
                    ForEach(subfolders) { folder in
                        Text(folder.name).tag(folder.name)
                    }
                }
            }

            Section("内容") {
                Text("\(fileCount) 个文件待上传")
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if isUploading {
                    ProgressView(progressText.isEmpty ? "上传中…" : progressText)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await startUpload() }
                } label: {
                    HStack {
                        Spacer()
                        Text(isUploading ? "上传中…" : "开始上传")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isUploading || selectedServer == nil || selectedSource.isEmpty || fileCount == 0)
            }
        }
        .navigationTitle("上传到 ReSourcer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    if isUploading {
                        // 后台任务已派发时可直接关闭
                        onFinish()
                    } else {
                        onCancel()
                    }
                }
            }
        }
        .task {
            await bootstrap()
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        servers = ShareBridge.loadServers()
        let last = ShareBridge.loadLastDestination()
        if let last, servers.contains(where: { $0.id == last.serverId }) {
            selectedServerId = last.serverId
        } else if let current = ShareBridge.currentServer() {
            selectedServerId = current.id
        } else {
            selectedServerId = servers.first?.id ?? ""
        }

        await reloadSources()

        if let last, last.serverId == selectedServerId {
            if sourceFolders.contains(last.sourceFolder) {
                selectedSource = last.sourceFolder
            }
            await reloadSubfolders()
            if last.subfolder.isEmpty || subfolders.contains(where: { $0.name == last.subfolder }) {
                selectedSubfolder = last.subfolder
            }
        }
    }

    private func reloadSources() async {
        guard let server = selectedServer else {
            sourceFolders = []
            selectedSource = ""
            return
        }
        if server.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceFolders = []
            selectedSource = ""
            errorMessage = "无法读取服务器凭证：请先在主 App 打开一次以同步 App Group / Keychain"
            isLoadingMeta = false
            return
        }
        isLoadingMeta = true
        errorMessage = nil
        defer { isLoadingMeta = false }
        do {
            // 活跃地址优先，失败再试主/备用（群晖常见公网 vs 局域网）
            let paths = try await ShareUploadClient.loadSourceFoldersTryingCandidates(for: server)
            sourceFolders = paths
            if selectedSource.isEmpty || !paths.contains(selectedSource) {
                selectedSource = paths.first ?? ""
            }
            await reloadSubfolders()
        } catch {
            errorMessage = "加载源文件夹失败：\(error.localizedDescription)"
            sourceFolders = []
        }
    }

    private func reloadSubfolders() async {
        guard let server = selectedServer, !selectedSource.isEmpty else {
            subfolders = []
            selectedSubfolder = ""
            return
        }
        do {
            let url = ShareBridge.effectiveBaseURL(for: server)
            let client = try ShareUploadClient(server: server, baseURLOverride: url)
            subfolders = try await client.subfolders(in: selectedSource)
            if !selectedSubfolder.isEmpty,
               !subfolders.contains(where: { $0.name == selectedSubfolder }) {
                selectedSubfolder = ""
            }
        } catch {
            subfolders = []
        }
    }

    private func displayName(for path: String) -> String {
        path.components(separatedBy: "/").last ?? path
    }

    // MARK: - Upload

    private func startUpload() async {
        guard let server = selectedServer, !selectedSource.isEmpty else { return }
        isUploading = true
        errorMessage = nil
        statusMessage = nil
        progressText = "准备中…"

        // 记住选择
        let pref = ShareDestinationPreference(
            serverId: server.id,
            sourceFolder: selectedSource,
            subfolder: selectedSubfolder
        )
        ShareBridge.saveLastDestination(pref)

        do {
            let client = try ShareUploadClient(server: server)
            let chunkThreshold = (try? await client.uploadPolicyChunkSize()) ?? 0
            // 超过阈值或大于 8MB 走后台会话，关掉 Extension 也能续传
            let backgroundFloor = 8 * 1024 * 1024
            let useBackgroundCutoff = chunkThreshold > 0 ? chunkThreshold : backgroundFloor

            var prepared: [(fileName: String, data: Data, mime: String)] = []
            for url in fileURLs {
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent
                prepared.append((name, data, ShareUploadFileHelpers.mimeType(forFileName: name)))
            }
            for item in imageItems {
                prepared.append((
                    item.fileName,
                    item.data,
                    ShareUploadFileHelpers.mimeType(forFileName: item.fileName)
                ))
            }

            guard !prepared.isEmpty else {
                errorMessage = "没有可上传的文件"
                isUploading = false
                return
            }

            let staging = AppGroup.uploadStagingURL ?? FileManager.default.temporaryDirectory
            var backgroundEnqueued = false

            for (index, file) in prepared.enumerated() {
                progressText = "\(index + 1)/\(prepared.count) \(file.fileName)"
                let large = file.data.count > useBackgroundCutoff

                if large {
                    try await enqueueBackground(
                        client: client,
                        server: server,
                        fileName: file.fileName,
                        data: file.data,
                        mime: file.mime,
                        targetFolder: targetFolder,
                        chunkThreshold: chunkThreshold,
                        staging: staging
                    )
                    backgroundEnqueued = true
                } else {
                    _ = try await client.uploadDirect(
                        fileName: file.fileName,
                        data: file.data,
                        mimeType: file.mime,
                        to: targetFolder
                    )
                }
            }

            if backgroundEnqueued {
                statusMessage = "大文件已转入后台上传，关闭后仍会继续。"
                progressText = "已开始后台上传"
                // 稍等再关，让用户看到提示
                try? await Task.sleep(nanoseconds: 600_000_000)
                isUploading = false
                onFinish()
            } else {
                progressText = "完成"
                statusMessage = "上传成功"
                isUploading = false
                try? await Task.sleep(nanoseconds: 400_000_000)
                onFinish()
            }
        } catch {
            errorMessage = error.localizedDescription
            isUploading = false
        }
    }

    private func enqueueBackground(
        client: ShareUploadClient,
        server: Server,
        fileName: String,
        data: Data,
        mime: String,
        targetFolder: String,
        chunkThreshold: Int,
        staging: URL
    ) async throws {
        let jobId = UUID().uuidString
        let localCopy = staging.appendingPathComponent("src-\(jobId)-\(fileName)")
        try data.write(to: localCopy, options: .atomic)

        if chunkThreshold > 0 && data.count > chunkThreshold {
            let totalChunks = max(1, (data.count + chunkThreshold - 1) / chunkThreshold)
            let uploadId = try await client.initChunkedUpload(
                fileName: fileName,
                fileSize: UInt64(data.count),
                targetFolder: targetFolder,
                totalChunks: totalChunks
            )
            var job = ShareBridge.BackgroundUploadJob(
                id: jobId,
                serverId: server.id,
                baseURL: server.baseURL,
                targetFolder: targetFolder,
                fileName: fileName,
                uploadId: uploadId,
                totalChunks: totalChunks,
                completedChunkIndexes: [],
                localFilePath: localCopy.path,
                kind: .chunked,
                createdAt: Date()
            )
            ShareBridge.upsertBackgroundJob(job)

            for index in 0..<totalChunks {
                let start = index * chunkThreshold
                let end = min(start + chunkThreshold, data.count)
                let chunk = data.subdata(in: start..<end)
                let chunkURL = try ShareUploadFileHelpers.writeChunkFile(
                    data: chunk, index: index, to: staging
                )
                var request = try await client.chunkPartRequest(uploadId: uploadId, index: index)
                _ = BackgroundUploadManager.shared.enqueueChunkPart(
                    request: request,
                    chunkFileURL: chunkURL,
                    jobId: jobId,
                    chunkIndex: index
                )
            }
            // job 已登记；完成由 BackgroundUploadManager 回调 finalize
            _ = job
        } else {
            let (bodyURL, contentType) = try ShareUploadFileHelpers.writeMultipartBody(
                fileName: fileName,
                fileData: data,
                mimeType: mime,
                targetFolder: targetFolder,
                to: staging
            )
            var request = try await client.directUploadRequest()
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            let job = ShareBridge.BackgroundUploadJob(
                id: jobId,
                serverId: server.id,
                baseURL: server.baseURL,
                targetFolder: targetFolder,
                fileName: fileName,
                uploadId: nil,
                totalChunks: nil,
                completedChunkIndexes: [],
                localFilePath: localCopy.path,
                kind: .direct,
                createdAt: Date()
            )
            _ = BackgroundUploadManager.shared.enqueueDirectUpload(
                request: request,
                bodyFileURL: bodyURL,
                job: job
            )
        }
    }
}
