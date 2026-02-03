//
//  ReSourcerApp.swift
//  ReSourcer
//
//  App 入口
//

import SwiftUI

@main
struct ReSourcerApp: App {

    // MARK: - State

    /// 当前选中的 Tab
    @State private var selectedTab: AppTab = .gallery

    /// 是否已登录（连接到服务器）
    @State private var isLoggedIn = false

    /// 当前 API 服务
    @State private var apiService: APIService?

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn, let service = apiService {
                    // 主界面
                    MainTabView(selectedTab: $selectedTab, apiService: service)
                } else {
                    // 登录/连接界面
                    ServerConnectView(
                        onConnected: { service in
                            self.apiService = service
                            self.isLoggedIn = true
                        }
                    )
                }
            }
            .withGlassAlerts()
            .animation(AppTheme.Animation.standard, value: isLoggedIn)
            .onAppear {
                checkExistingLogin()
            }
            .onReceive(NotificationCenter.default.publisher(for: .userDidLogout)) { _ in
                handleLogout()
            }
        }
    }

    // MARK: - Methods

    /// 检查是否已有登录状态
    private func checkExistingLogin() {
        if LocalStorageService.shared.isLoggedIn(),
           let server = LocalStorageService.shared.getCurrentServer(),
           let service = APIService.create(for: server) {
            self.apiService = service
            self.isLoggedIn = true

            // 异步验证连接状态
            Task {
                let status = await service.checkConnection()
                if status != .online {
                    await MainActor.run {
                        handleLogout()
                        if status == .authError {
                            GlassAlertManager.shared.showError("认证失败", message: "API Key 已失效，请重新登录")
                        }
                    }
                }
            }
        }
    }

    /// 处理登出
    private func handleLogout() {
        withAnimation(AppTheme.Animation.standard) {
            isLoggedIn = false
            apiService = nil
            selectedTab = .gallery
        }
    }
}

// MARK: - App Tab 枚举

/// 主要 Tab 项
enum AppTab: String, GlassTabItem, CaseIterable {
    case gallery
    case classifier
    case download
    case settings

    var title: String {
        switch self {
        case .gallery: return "首页"
        case .classifier: return "分类"
        case .download: return "下载"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .gallery: return "photo.on.rectangle"
        case .classifier: return "square.grid.2x2"
        case .download: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .gallery: return "photo.on.rectangle.fill"
        case .classifier: return "square.grid.2x2.fill"
        case .download: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
