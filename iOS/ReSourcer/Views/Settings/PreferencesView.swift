//
//  PreferencesView.swift
//  ReSourcer
//
//  偏好设置页 — 预览设置 / 忽略配置 / 自动播放
//

import SwiftUI

struct PreferencesView: View {

    let apiService: APIService

    // MARK: - State

    @State private var prefs = LocalStorageService.shared.getPreviewPreferences()

    // 忽略文件夹（服务端）
    @State private var ignoredFolders: [String] = []
    @State private var showAddFolder = false
    @State private var newFolderName = ""

    // 忽略文件（服务端）
    @State private var ignoredFiles: [String] = []
    @State private var showAddFile = false
    @State private var newFileName = ""

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                previewSection
                ignoredFoldersSection
                ignoredFilesSection
                autoplaySection
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("偏好设置")
        .task {
            await loadIgnoreConfig()
        }
    }

    // MARK: - 预览设置

    private var previewSection: some View {
        SettingsSection(title: "预览") {
            VStack(spacing: AppTheme.Spacing.md) {

                // 允许点击收起 UI
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("点击中间收起界面")
                            .font(.body)
                        Text("关闭后界面始终保持显示")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $prefs.allowToggleUI)
                        .labelsHidden()
                        .onChange(of: prefs.allowToggleUI) { _, _ in savePrefs() }
                }

                Divider()

                // 自动隐藏延迟
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("视频自动收起界面")
                                .font(.body)
                            Text(prefs.autoHideDelay == 0 ? "永不自动收起" : "\(prefs.autoHideDelay) 秒后自动收起")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    let delayOptions = [0, 3, 5, 10, 15, 30]
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(delayOptions, id: \.self) { sec in
                            Button {
                                prefs.autoHideDelay = sec
                                savePrefs()
                            } label: {
                                Text(sec == 0 ? "永不" : "\(sec)s")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, AppTheme.Spacing.sm)
                                    .padding(.vertical, AppTheme.Spacing.xxs)
                                    .foregroundStyle(prefs.autoHideDelay == sec ? .white : .primary)
                                    .background(
                                        prefs.autoHideDelay == sec
                                            ? Color.blue
                                            : Color.primary.opacity(0.08),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .opacity(prefs.allowToggleUI ? 1 : 0.4)
                .disabled(!prefs.allowToggleUI)
            }
        }
    }

    // MARK: - 忽略文件夹

    private var ignoredFoldersSection: some View {
        SettingsSection(title: "忽略文件夹") {
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("扫描和浏览时会跳过这些文件夹")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(ignoredFolders, id: \.self) { folder in
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "folder.badge.minus")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                            .frame(width: 24)

                        Text(folder)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            removeIgnoredFolder(folder)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, AppTheme.Spacing.xxs)
                }

                if showAddFolder {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        TextField("文件夹名称", text: $newFolderName)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button { addIgnoredFolder() } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button {
                            showAddFolder = false
                            newFolderName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button { showAddFolder = true } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue)
                            Text("添加忽略文件夹")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 忽略文件

    private var ignoredFilesSection: some View {
        SettingsSection(title: "忽略文件") {
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("扫描和查询时会跳过这些文件名（服务端过滤）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(ignoredFiles, id: \.self) { file in
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "doc.badge.minus")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                            .frame(width: 24)

                        Text(file)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            removeIgnoredFile(file)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, AppTheme.Spacing.xxs)
                }

                if showAddFile {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        TextField("文件名", text: $newFileName)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button { addIgnoredFile() } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newFileName.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button {
                            showAddFile = false
                            newFileName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button { showAddFile = true } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue)
                            Text("添加忽略文件")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 自动播放设置

    private var autoplaySection: some View {
        SettingsSection(title: "自动播放") {
            VStack(spacing: AppTheme.Spacing.md) {

                // 图片停留时间
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("图片停留时间")
                                .font(.body)
                            Text("顺序/随机播放时每张图片显示的时长")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(prefs.imageAutoAdvanceSeconds) 秒")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    let advanceOptions = [3, 5, 8, 10, 15, 20, 30]
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(advanceOptions, id: \.self) { sec in
                            Button {
                                prefs.imageAutoAdvanceSeconds = sec
                                savePrefs()
                            } label: {
                                Text("\(sec)s")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, AppTheme.Spacing.sm)
                                    .padding(.vertical, AppTheme.Spacing.xxs)
                                    .foregroundStyle(prefs.imageAutoAdvanceSeconds == sec ? .white : .primary)
                                    .background(
                                        prefs.imageAutoAdvanceSeconds == sec
                                            ? Color.blue
                                            : Color.primary.opacity(0.08),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                // 按文件类型过滤
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("同类型连播")
                            .font(.body)
                        Text("自动播放只跳同类文件（图片→图片，视频→视频，音频→音频…）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $prefs.filterAutoplayByFileType)
                        .labelsHidden()
                        .onChange(of: prefs.filterAutoplayByFileType) { _, _ in savePrefs() }
                }
            }
        }
    }

    // MARK: - 忽略配置加载 / 保存

    private func loadIgnoreConfig() async {
        do {
            let state = try await apiService.config.getConfigState()
            ignoredFolders = state.ignoredFolders ?? ["@eaDir", "#recycle", "$RECYCLE.BIN"]
            ignoredFiles = state.ignoredFiles ?? [".DS_Store"]
        } catch {
            ignoredFolders = ["@eaDir", "#recycle", "$RECYCLE.BIN"]
            ignoredFiles = [".DS_Store"]
        }
    }

    private func addIgnoredFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !ignoredFolders.contains(name) else { return }
        ignoredFolders.append(name)
        newFolderName = ""
        showAddFolder = false
        saveIgnoreConfig()
    }

    private func removeIgnoredFolder(_ folder: String) {
        ignoredFolders.removeAll { $0 == folder }
        saveIgnoreConfig()
    }

    private func addIgnoredFile() {
        let name = newFileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !ignoredFiles.contains(name) else { return }
        ignoredFiles.append(name)
        newFileName = ""
        showAddFile = false
        saveIgnoreConfig()
    }

    private func removeIgnoredFile(_ file: String) {
        ignoredFiles.removeAll { $0 == file }
        saveIgnoreConfig()
    }

    private func saveIgnoreConfig() {
        Task {
            do {
                let state = try await apiService.config.getConfigState()
                try await apiService.config.saveConfig(
                    sourceFolder: state.sourceFolder,
                    categories: [],
                    hiddenFolders: state.hiddenFolders,
                    ignoredFolders: ignoredFolders,
                    ignoredFiles: ignoredFiles
                )
            } catch {
                GlassAlertManager.shared.showError("保存失败", message: error.localizedDescription)
            }
        }
    }

    private func savePrefs() {
        LocalStorageService.shared.savePreviewPreferences(prefs)
    }
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        NavigationStack {
            PreferencesView(apiService: api)
        }
        .previewWithGlassBackground()
    }
}
