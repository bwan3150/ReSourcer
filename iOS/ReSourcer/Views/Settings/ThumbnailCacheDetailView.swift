//
//  ThumbnailCacheDetailView.swift
//  ReSourcer
//
//  缩略图缓存详情页 — 按服务器/文件夹分组展示，支持分层清除
//

import SwiftUI

struct ThumbnailCacheDetailView: View {

    // MARK: - State

    @State private var isLoading = true
    @State private var servers: [ThumbnailServerCacheInfo] = []
    @State private var legacySize: Int64 = 0
    @State private var legacyCount: Int = 0
    @State private var expandedServerHash: String?

    // MARK: - Body

    var body: some View {
        ScrollView {
            if isLoading {
                GlassLoadingView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if servers.isEmpty && legacySize == 0 {
                GlassEmptyView(
                    icon: "photo.stack",
                    title: "暂无缩略图缓存",
                    message: "浏览画廊后会自动缓存缩略图"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // 旧版缓存（如有）
                    if legacySize > 0 {
                        legacyCacheCard
                    }

                    // 服务器卡片列表
                    ForEach(servers) { server in
                        serverCard(server)
                    }

                    // 总计
                    totalText

                    // 清除全部
                    GlassButton.destructive("清除全部缩略图", icon: "trash") {
                        clearAll()
                    }
                    .padding(.top, AppTheme.Spacing.sm)
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
        .navigationTitle("缩略图缓存")
        .task {
            await loadData()
        }
    }

    // MARK: - 旧版缓存卡片

    private var legacyCacheCard: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("旧版缓存")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text("\(legacyCount) 个文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(ThumbnailCacheService.formatSize(legacySize))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    clearLegacy()
                } label: {
                    Text("清除")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xxs)
                }
                .interactiveGlassBackground(in: Capsule())
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - 服务器卡片

    @ViewBuilder
    private func serverCard(_ server: ThumbnailServerCacheInfo) -> some View {
        let isExpanded = expandedServerHash == server.serverHash

        VStack(spacing: 0) {
            // 可点击的服务器头部
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedServerHash = isExpanded ? nil : server.serverHash
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.displayHost)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Text("\(server.totalFileCount) 个文件 · \(server.folders.count) 个文件夹")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(ThumbnailCacheService.formatSize(server.totalSize))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 展开内容
            if isExpanded {
                Divider()
                    .padding(.vertical, AppTheme.Spacing.sm)

                VStack(spacing: AppTheme.Spacing.sm) {
                    // 文件夹列表
                    ForEach(server.folders) { folder in
                        folderRow(folder, serverHash: server.serverHash)
                    }

                    // 清除此服务器缓存
                    Button {
                        clearServer(server)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Image(systemName: "trash")
                                .font(.caption)
                            Text("清除此服务器缓存")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.sm)
                    }
                    .interactiveGlassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm))
                    .padding(.top, AppTheme.Spacing.xs)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - 文件夹行

    @ViewBuilder
    private func folderRow(_ folder: ThumbnailFolderCacheInfo, serverHash: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "folder")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if folder.folderPath != folder.displayName {
                    Text(folder.folderPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(folder.fileCount)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(ThumbnailCacheService.formatSize(folder.totalSize))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                clearFolder(serverHash: serverHash, folder: folder)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .padding(.horizontal, AppTheme.Spacing.sm)
    }

    // MARK: - 总计

    private var totalText: some View {
        let serverTotal = servers.reduce(Int64(0)) { $0 + $1.totalSize }
        let total = serverTotal + legacySize
        let fileCount = servers.reduce(0) { $0 + $1.totalFileCount } + legacyCount
        return Text("共 \(fileCount) 个文件，总计 \(ThumbnailCacheService.formatSize(total))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Actions

    private func loadData() async {
        let result = await Task.detached(priority: .utility) {
            let stats = ThumbnailCacheService.shared.getCacheStatistics()
            let legSize = ThumbnailCacheService.shared.legacyCacheSize()
            let legCount = ThumbnailCacheService.shared.legacyCacheCount()
            return (stats, legSize, legCount)
        }.value

        servers = result.0
        legacySize = result.1
        legacyCount = result.2
        isLoading = false
    }

    private func clearLegacy() {
        ThumbnailCacheService.shared.clearLegacyCache()
        legacySize = 0
        legacyCount = 0
        GlassAlertManager.shared.showSuccess("旧版缓存已清除")
    }

    private func clearServer(_ server: ThumbnailServerCacheInfo) {
        ThumbnailCacheService.shared.clearServerCache(serverHash: server.serverHash)
        withAnimation {
            servers.removeAll { $0.serverHash == server.serverHash }
            expandedServerHash = nil
        }
        GlassAlertManager.shared.showSuccess("\(server.displayHost) 缓存已清除")
    }

    private func clearFolder(serverHash: String, folder: ThumbnailFolderCacheInfo) {
        ThumbnailCacheService.shared.clearFolderCache(serverHash: serverHash, folderHash: folder.folderHash)
        withAnimation {
            if let serverIdx = servers.firstIndex(where: { $0.serverHash == serverHash }) {
                servers[serverIdx].folders.removeAll { $0.folderHash == folder.folderHash }
                // 如果服务器下没有文件夹了，移除整个服务器
                if servers[serverIdx].folders.isEmpty {
                    servers.remove(at: serverIdx)
                    expandedServerHash = nil
                }
            }
        }
        GlassAlertManager.shared.showSuccess("\(folder.displayName) 缓存已清除")
    }

    private func clearAll() {
        ThumbnailCacheService.shared.clearAll()
        withAnimation {
            servers = []
            legacySize = 0
            legacyCount = 0
        }
        GlassAlertManager.shared.showSuccess("全部缩略图缓存已清除")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ThumbnailCacheDetailView()
    }
}
