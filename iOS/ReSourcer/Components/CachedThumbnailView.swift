//
//  CachedThumbnailView.swift
//  ReSourcer
//
//  带磁盘缓存的缩略图组件 - 替代 AsyncImage
//

import SwiftUI

/// 带双层缓存的缩略图视图
/// 加载顺序：内存缓存 → 磁盘缓存 → 网络下载
struct CachedThumbnailView<Content: View, Placeholder: View>: View {

    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var isLoading = false

    // MARK: - Init

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: url) { _, _ in
            uiImage = nil
            loadImageIfNeeded()
        }
    }

    // MARK: - Loading

    private func loadImageIfNeeded() {
        guard let url, uiImage == nil, !isLoading else { return }

        // 同步查缓存（内存 + 磁盘）
        if let cached = ThumbnailCacheService.shared.getImage(for: url) {
            uiImage = cached
            return
        }

        // 异步网络加载
        isLoading = true
        Task {
            let loaded = await ThumbnailCacheService.shared.loadImage(from: url)
            await MainActor.run {
                uiImage = loaded
                isLoading = false
            }
        }
    }
}

// MARK: - 便捷初始化

extension CachedThumbnailView where Content == Image, Placeholder == _CachedThumbnailPlaceholder {
    /// 简化初始化 - 默认 resizable + fill 模式 + 灰色占位
    init(url: URL?) {
        self.url = url
        self.content = { $0 }
        self.placeholder = { _CachedThumbnailPlaceholder() }
    }
}

/// 默认占位视图
struct _CachedThumbnailPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(.gray.opacity(0.15))
            .overlay {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
            }
    }
}
