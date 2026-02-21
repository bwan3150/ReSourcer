//
//  ThumbnailCacheDetailView.swift
//  ReSourcer
//
//  缩略图缓存详情页 — 按服务器 > 源文件夹分组展示，支持分层清除
//

import SwiftUI

struct ThumbnailCacheDetailView: View {

    // MARK: - State

    @State private var isLoading = true
    @State private var servers: [ThumbnailServerCacheInfo] = []
    @State private var expandedServers: Set<String> = []

    // MARK: - Body

    var body: some View {
        ScrollView {
            if isLoading {
                GlassLoadingView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if servers.isEmpty {
                GlassEmptyView(
                    icon: "photo.stack",
                    title: "暂无缩略图缓存",
                    message: "浏览画廊后会自动缓存缩略图"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                VStack(spacing: AppTheme.Spacing.lg) {
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

    // MARK: - 服务器卡片

    @ViewBuilder
    private func serverCard(_ server: ThumbnailServerCacheInfo) -> some View {
        VStack(spacing: 0) {
            // 服务器头部行
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedServers.contains(server.serverHash) {
                        expandedServers.remove(server.serverHash)
                    } else {
                        expandedServers.insert(server.serverHash)
                    }
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

                        Text("\(server.fileCount) 个文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(ThumbnailCacheService.formatSize(server.totalSize))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Image(systemName: expandedServers.contains(server.serverHash) ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(AppTheme.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 展开的源文件夹列表
            if expandedServers.contains(server.serverHash) {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, AppTheme.Spacing.md)

                    ForEach(server.sourceFolders) { folder in
                        sourceFolderRow(server: server, folder: folder)
                    }

                    // 服务器级全部清除
                    Button {
                        clearServer(server)
                    } label: {
                        HStack {
                            Spacer()
                            Text("清除此服务器全部缓存")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - 源文件夹行

    @ViewBuilder
    private func sourceFolderRow(server: ThumbnailServerCacheInfo, folder: ThumbnailSourceFolderCacheInfo) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: folder.folderHash == "_ungrouped" ? "questionmark.folder.fill" : "folder.fill")
                .font(.system(size: 16))
                .foregroundStyle(folder.folderHash == "_ungrouped" ? .gray : .yellow)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.folderName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(folder.fileCount) 个文件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(ThumbnailCacheService.formatSize(folder.totalSize))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                clearSourceFolder(server: server, folder: folder)
            } label: {
                Text("清除")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, AppTheme.Spacing.xxs)
            }
            .interactiveGlassBackground(in: Capsule())
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    // MARK: - 总计

    private var totalText: some View {
        let total = servers.reduce(Int64(0)) { $0 + $1.totalSize }
        let fileCount = servers.reduce(0) { $0 + $1.fileCount }
        return Text("共 \(fileCount) 个文件，总计 \(ThumbnailCacheService.formatSize(total))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Actions

    private func loadData() async {
        let stats = await Task.detached(priority: .utility) {
            ThumbnailCacheService.shared.getCacheStatistics()
        }.value

        servers = stats
        // 默认展开所有服务器
        expandedServers = Set(stats.map { $0.serverHash })
        isLoading = false
    }

    private func clearSourceFolder(server: ThumbnailServerCacheInfo, folder: ThumbnailSourceFolderCacheInfo) {
        ThumbnailCacheService.shared.clearSourceFolderCache(
            serverHash: server.serverHash, folderHash: folder.folderHash
        )
        withAnimation {
            if let serverIdx = servers.firstIndex(where: { $0.serverHash == server.serverHash }) {
                servers[serverIdx].sourceFolders.removeAll { $0.folderHash == folder.folderHash }
                // 如果服务器下没有源文件夹了，移除整个服务器
                if servers[serverIdx].sourceFolders.isEmpty {
                    servers.remove(at: serverIdx)
                }
            }
        }
        GlassAlertManager.shared.showSuccess("\(folder.folderName) 缓存已清除")
    }

    private func clearServer(_ server: ThumbnailServerCacheInfo) {
        ThumbnailCacheService.shared.clearServerCache(serverHash: server.serverHash)
        withAnimation {
            servers.removeAll { $0.serverHash == server.serverHash }
        }
        GlassAlertManager.shared.showSuccess("\(server.displayHost) 缓存已清除")
    }

    private func clearAll() {
        ThumbnailCacheService.shared.clearAll()
        withAnimation {
            servers = []
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
