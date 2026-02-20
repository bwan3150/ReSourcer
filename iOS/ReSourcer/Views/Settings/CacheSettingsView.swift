//
//  CacheSettingsView.swift
//  ReSourcer
//
//  缓存管理二级页面
//

import SwiftUI

struct CacheSettingsView: View {

    // MARK: - Properties

    @State private var thumbnailSize: Int64 = 0
    @State private var videoSize: Int64 = 0
    @State private var networkSize: Int64 = 0
    @State private var tempSize: Int64 = 0

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // 缩略图缓存（NavigationLink 进入详情页）
                NavigationLink {
                    ThumbnailCacheDetailView()
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("缩略图缓存")
                                .font(.body)
                                .foregroundStyle(.primary)

                            Text("画廊和分类页的缩略图")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(ThumbnailCacheService.formatSize(thumbnailSize))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(AppTheme.Spacing.md)
                .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))

                // 视频播放缓存
                cacheRow(
                    icon: "play.rectangle",
                    iconColor: .purple,
                    title: "视频播放缓存",
                    description: "视频预览产生的系统缓存",
                    size: videoSize
                ) {
                    clearVideoCache()
                }

                // 网络缓存
                cacheRow(
                    icon: "arrow.up.arrow.down.circle",
                    iconColor: .green,
                    title: "网络缓存",
                    description: "API 请求产生的 HTTP 缓存",
                    size: networkSize
                ) {
                    clearNetworkCache()
                }

                // App 临时文件
                cacheRow(
                    icon: "doc",
                    iconColor: .gray,
                    title: "App 临时文件",
                    description: "系统产生的临时文件",
                    size: tempSize
                ) {
                    clearAppTemp()
                }

                // 总计
                totalSection

                // 清除全部
                GlassButton.destructive("清除全部缓存", icon: "trash") {
                    clearAllCache()
                }
                .padding(.top, AppTheme.Spacing.sm)
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("缓存管理")
        .task {
            await refreshSizes()
        }
    }

    // MARK: - Cache Row

    @ViewBuilder
    private func cacheRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        size: Int64,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(ThumbnailCacheService.formatSize(size))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    onClear()
                } label: {
                    Text("清除")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xxs)
                }
                .interactiveGlassBackground(in: Capsule())
                .disabled(size == 0)
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - Total

    private var totalSection: some View {
        let total = thumbnailSize + videoSize + networkSize + tempSize
        return Text("总计: \(ThumbnailCacheService.formatSize(total))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Actions

    private func refreshSizes() async {
        // 在后台线程计算大小
        let sizes = await Task.detached(priority: .utility) {
            return (
                ThumbnailCacheService.shared.diskCacheSize(),
                ThumbnailCacheService.videoCacheSize(),
                ThumbnailCacheService.networkCacheSize(),
                ThumbnailCacheService.appTempSize()
            )
        }.value

        thumbnailSize = sizes.0
        videoSize = sizes.1
        networkSize = sizes.2
        tempSize = sizes.3
    }

    private func clearVideoCache() {
        ThumbnailCacheService.clearVideoCache()
        Task { await refreshSizes() }
        GlassAlertManager.shared.showSuccess("视频缓存已清除")
    }

    private func clearNetworkCache() {
        ThumbnailCacheService.clearNetworkCache()
        networkSize = 0
        GlassAlertManager.shared.showSuccess("网络缓存已清除")
    }

    private func clearAppTemp() {
        ThumbnailCacheService.clearAppTemp()
        Task { await refreshSizes() }
        GlassAlertManager.shared.showSuccess("临时文件已清除")
    }

    private func clearAllCache() {
        ThumbnailCacheService.shared.clearAll()
        ThumbnailCacheService.clearVideoCache()
        ThumbnailCacheService.clearNetworkCache()
        ThumbnailCacheService.clearAppTemp()
        Task { await refreshSizes() }
        GlassAlertManager.shared.showSuccess("全部缓存已清除")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CacheSettingsView()
    }
}
