//
//  IgnoreSettingsView.swift
//  ReSourcer
//
//  忽略配置二级设置页 — 忽略文件夹（服务端）+ 忽略文件（本地）
//

import SwiftUI

struct IgnoreSettingsView: View {

    // MARK: - Properties

    let apiService: APIService

    // 忽略文件夹（服务端）
    @State private var ignoredFolders: [String] = []
    @State private var showAddFolder = false
    @State private var newFolderName = ""

    // 忽略文件（本地）
    @State private var ignoredFiles: [String] = []
    @State private var showAddFile = false
    @State private var newFileName = ""

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // 忽略文件夹
                ignoredFoldersSection

                // 忽略文件
                ignoredFilesSection
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("忽略配置")
        .task {
            await loadIgnoredFolders()
            loadIgnoredFiles()
        }
    }

    // MARK: - 忽略文件夹（服务端）

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

                        Button {
                            addIgnoredFolder()
                        } label: {
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
                    Button {
                        showAddFolder = true
                    } label: {
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

    // MARK: - 忽略文件（本地）

    private var ignoredFilesSection: some View {
        SettingsSection(title: "忽略文件") {
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("浏览和分类时会跳过这些文件名")
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

                        Button {
                            addIgnoredFile()
                        } label: {
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
                    Button {
                        showAddFile = true
                    } label: {
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

    // MARK: - 忽略文件夹方法

    private func loadIgnoredFolders() async {
        do {
            let state = try await apiService.config.getConfigState()
            ignoredFolders = state.ignoredFolders ?? ["@eaDir", "#recycle", "$RECYCLE.BIN"]
        } catch {
            ignoredFolders = ["@eaDir", "#recycle", "$RECYCLE.BIN"]
        }
    }

    private func addIgnoredFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !ignoredFolders.contains(name) else { return }

        ignoredFolders.append(name)
        newFolderName = ""
        showAddFolder = false
        saveIgnoredFolders()
    }

    private func removeIgnoredFolder(_ folder: String) {
        ignoredFolders.removeAll { $0 == folder }
        saveIgnoredFolders()
    }

    private func saveIgnoredFolders() {
        Task {
            do {
                let state = try await apiService.config.getConfigState()
                try await apiService.config.saveConfig(
                    sourceFolder: state.sourceFolder,
                    categories: [],
                    hiddenFolders: state.hiddenFolders,
                    ignoredFolders: ignoredFolders
                )
            } catch {
                GlassAlertManager.shared.showError("保存失败", message: error.localizedDescription)
            }
        }
    }

    // MARK: - 忽略文件方法

    private func loadIgnoredFiles() {
        ignoredFiles = LocalStorageService.shared.getAppSettings().ignoredFiles
    }

    private func addIgnoredFile() {
        let name = newFileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !ignoredFiles.contains(name) else { return }

        ignoredFiles.append(name)
        newFileName = ""
        showAddFile = false
        saveIgnoredFiles()
    }

    private func removeIgnoredFile(_ file: String) {
        ignoredFiles.removeAll { $0 == file }
        saveIgnoredFiles()
    }

    private func saveIgnoredFiles() {
        var settings = LocalStorageService.shared.getAppSettings()
        settings.ignoredFiles = ignoredFiles
        LocalStorageService.shared.saveAppSettings(settings)
    }
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test Server", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        NavigationStack {
            IgnoreSettingsView(apiService: api)
        }
        .previewWithGlassBackground()
    }
}
