//
//  ThumbnailCacheDetailView.swift
//  ReSourcer
//
//  缩略图缓存详情页 — 按服务器分组展示，支持分层清除
//

import SwiftUI

struct ThumbnailCacheDetailView: View {

    // MARK: - State

    @State private var isLoading = true
    @State private var servers: [ThumbnailServerCacheInfo] = []

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

            Button {
                clearServer(server)
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
        .padding(AppTheme.Spacing.md)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
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
        isLoading = false
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
