//
//  MainTabView.swift
//  ReSourcer
//
//  主界面 - 底部 Tab 导航容器
//

import SwiftUI

struct MainTabView: View {

    // MARK: - Properties

    @Binding var selectedTab: AppTab
    let apiService: APIService

    // MARK: - Body

    var body: some View {
        ZStack {
            // 背景
            backgroundGradient
                .ignoresSafeArea()

            // 内容区域
            VStack(spacing: 0) {
                // 页面内容
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 底部导航栏
                GlassTabBar(selection: $selectedTab)
                    .padding(.bottom, safeAreaBottom > 0 ? 0 : AppTheme.Spacing.sm)
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 根据当前 Tab 切换背景色
    private var backgroundColors: [Color] {
        switch selectedTab {
        case .gallery:
            return [Color.blue.opacity(0.15), Color.purple.opacity(0.15)]
        case .classifier:
            return [Color.orange.opacity(0.15), Color.pink.opacity(0.15)]
        case .download:
            return [Color.green.opacity(0.15), Color.teal.opacity(0.15)]
        case .settings:
            return [Color.gray.opacity(0.15), Color.blue.opacity(0.15)]
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            GalleryView(apiService: apiService)
                .tag(AppTab.gallery)

            ClassifierView(apiService: apiService)
                .tag(AppTab.classifier)

            DownloadView(apiService: apiService)
                .tag(AppTab.download)

            SettingsView(apiService: apiService)
                .tag(AppTab.settings)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(AppTheme.Animation.standard, value: selectedTab)
    }

    // MARK: - Safe Area

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
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
