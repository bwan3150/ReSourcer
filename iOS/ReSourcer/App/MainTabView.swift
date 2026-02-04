//
//  MainTabView.swift
//  ReSourcer
//
//  主界面 - 底部 Tab 导航容器
//  使用系统 TabView 自动获得 iOS 26 Liquid Glass 效果
//

import SwiftUI

struct MainTabView: View {

    // MARK: - Properties

    @Binding var selectedTab: AppTab
    let apiService: APIService

    // MARK: - Body

    var body: some View {
        // 使用系统 TabView，iOS 26 会自动应用 Liquid Glass
        TabView(selection: $selectedTab) {
            Tab("画廊", systemImage: "photo.on.rectangle.angled", value: .gallery) {
                GalleryView(apiService: apiService)
            }

            Tab("分类", systemImage: "square.grid.3x3", value: .classifier) {
                ClassifierView(apiService: apiService)
            }

            Tab("下载", systemImage: "arrow.down.circle", value: .download) {
                DownloadView(apiService: apiService)
            }

            Tab("设置", systemImage: "gearshape", value: .settings) {
                SettingsView(apiService: apiService)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab: AppTab = .gallery

        var body: some View {
            // 创建模拟服务
            let server = Server(
                name: "Preview Server",
                baseURL: "http://localhost:1234",
                apiKey: "preview-key"
            )

            if let apiService = APIService.create(for: server) {
                MainTabView(selectedTab: $selectedTab, apiService: apiService)
            } else {
                Text("无法创建预览")
            }
        }
    }

    return PreviewWrapper()
}
