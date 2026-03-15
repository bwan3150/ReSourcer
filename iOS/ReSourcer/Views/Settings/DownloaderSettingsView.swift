//
//  DownloaderSettingsView.swift
//  ReSourcer
//
//  下载器管理页面：查看版本、检查/执行更新
//

import SwiftUI

// MARK: - 下载器数据模型

private struct DownloaderInfo: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let iconColor: Color
    let supportsUpdate: Bool
}

// MARK: - View

struct DownloaderSettingsView: View {

    let apiService: APIService

    // yt-dlp 状态
    @State private var ytdlpVersion: String?
    @State private var isLoadingVersion = false
    @State private var isUpdating = false
    @State private var updateOutput: String?
    @State private var updateError: String?
    @State private var showUpdateResult = false

    private let downloaders: [DownloaderInfo] = [
        DownloaderInfo(
            id: "ytdlp",
            name: "yt-dlp",
            description: "支持 YouTube、Bilibili、X、TikTok 等平台",
            icon: "arrow.down.circle.fill",
            iconColor: .blue,
            supportsUpdate: true
        ),
        DownloaderInfo(
            id: "pixiv",
            name: "Pixiv Toolkit",
            description: "Pixiv 专用下载器",
            icon: "paintbrush.fill",
            iconColor: .purple,
            supportsUpdate: false
        ),
    ]

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                ForEach(downloaders) { downloader in
                    downloaderCard(downloader)
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("下载器")
        .task {
            await loadYtdlpVersion()
        }
    }

    // MARK: - 下载器卡片

    @ViewBuilder
    private func downloaderCard(_ downloader: DownloaderInfo) -> some View {
        SettingsSection(title: "") {
            VStack(spacing: AppTheme.Spacing.md) {
                // 标题行
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: downloader.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(downloader.iconColor)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(downloader.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Text(downloader.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // 版本号（仅 yt-dlp）
                    if downloader.supportsUpdate {
                        versionBadge
                    }
                }

                // yt-dlp 更新区域
                if downloader.supportsUpdate {
                    Divider()
                    updateSection
                }
            }
        }
    }

    // MARK: - 版本 Badge

    private var versionBadge: some View {
        Group {
            if isLoadingVersion {
                ProgressView()
                    .scaleEffect(0.7)
            } else if let version = ytdlpVersion {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            } else {
                Text("未安装")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - 更新区域

    private var updateSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // 更新中：显示进度指示
            if isUpdating {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("正在更新 yt-dlp，请稍候…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, AppTheme.Spacing.xs)
            }

            // 更新结果
            if showUpdateResult {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    if let error = updateError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text("更新失败")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.red)
                        }
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    } else if let output = updateOutput {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(updateResultSummary(output))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.sm)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            // 更新按钮
            if !isUpdating {
                Button {
                    Task { await performUpdate() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                        Text("检查并更新")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 解析更新输出摘要

    private func updateResultSummary(_ output: String) -> String {
        let lower = output.lowercased()
        if lower.contains("up to date") || lower.contains("已是最新") {
            return "已是最新版本"
        } else if lower.contains("updating") || lower.contains("updated") || lower.contains("successfully") {
            // 尝试从输出中提取新版本号
            let lines = output.components(separatedBy: "\n")
            for line in lines {
                if line.contains("Updating to") || line.contains("Updated to") {
                    return line.trimmingCharacters(in: .whitespaces)
                }
            }
            return "更新成功"
        }
        return "更新完成"
    }

    // MARK: - 数据加载

    private func loadYtdlpVersion() async {
        isLoadingVersion = true
        defer { isLoadingVersion = false }
        do {
            let response = try await apiService.download.getYtdlpVersion()
            ytdlpVersion = response.version
        } catch {
            ytdlpVersion = nil
        }
    }

    private func performUpdate() async {
        isUpdating = true
        showUpdateResult = false
        updateOutput = nil
        updateError = nil

        defer { isUpdating = false }

        do {
            let response = try await apiService.download.updateYtdlp()
            if let error = response.error {
                updateError = error
            } else {
                updateOutput = response.output ?? "更新完成"
            }
        } catch {
            updateError = error.localizedDescription
        }

        showUpdateResult = true

        // 更新完成后刷新版本号
        await loadYtdlpVersion()
    }
}
