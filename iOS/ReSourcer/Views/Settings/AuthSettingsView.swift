//
//  AuthSettingsView.swift
//  ReSourcer
//
//  平台认证管理二级页面
//

import SwiftUI

struct AuthSettingsView: View {

    // MARK: - Properties

    let apiService: APIService

    @State private var authStatus: AuthStatus?
    @State private var expandedPlatform: AuthPlatform?
    @State private var credentialText: String = ""
    @State private var isSaving = false
    @State private var isDeleting = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                ForEach(AuthPlatform.allCases, id: \.self) { platform in
                    platformCard(platform)
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("平台认证")
        .task {
            await loadAuthStatus()
        }
    }

    // MARK: - Platform Card

    @ViewBuilder
    private func platformCard(_ platform: AuthPlatform) -> some View {
        let isConfigured = isConfigured(platform)
        let isExpanded = expandedPlatform == platform

        VStack(spacing: 0) {
            // 平台头部（可点击展开/收起）
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if isExpanded {
                        expandedPlatform = nil
                        credentialText = ""
                    } else {
                        expandedPlatform = platform
                        credentialText = ""
                    }
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    // 平台图标
                    Image(systemName: platformIcon(platform))
                        .font(.system(size: 18))
                        .foregroundStyle(platformColor(platform))
                        .frame(width: 28)

                    // 平台信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(platform.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Text(platform.authTypeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // 配置状态
                    HStack(spacing: 4) {
                        Text(isConfigured ? "已配置" : "未配置")
                            .font(.caption)
                            .foregroundStyle(isConfigured ? .green : .secondary)

                        Image(systemName: isConfigured ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(isConfigured ? .green : .gray)
                    }

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

                expandedContent(platform, isConfigured: isConfigured)
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private func expandedContent(_ platform: AuthPlatform, isConfigured: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // 说明文字
            Text(platform.instructions)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 输入框
            if platform == .x {
                // Cookies 使用多行输入
                TextEditor(text: $credentialText)
                    .font(.caption)
                    .frame(minHeight: 100, maxHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(AppTheme.Spacing.sm)
                    .clearGlassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
                    .overlay(alignment: .topLeading) {
                        if credentialText.isEmpty {
                            Text("粘贴 \(platform.authTypeDescription) 内容...")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(AppTheme.Spacing.sm)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                // Token 使用单行输入
                GlassTextField(
                    "",
                    text: $credentialText,
                    placeholder: "输入 \(platform.authTypeDescription)",
                    icon: "key",
                    isSecure: true
                )
            }

            // 操作按钮
            HStack(spacing: AppTheme.Spacing.md) {
                // 保存按钮
                Button {
                    saveCredential(for: platform)
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text("保存")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
                .interactiveGlassBackground(in: Capsule())
                .disabled(credentialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                // 删除按钮（仅在已配置时显示）
                if isConfigured {
                    Button {
                        deleteCredential(for: platform)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            if isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text("删除")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.sm)
                    }
                    .interactiveGlassBackground(in: Capsule())
                    .disabled(isDeleting)
                }
            }
        }
    }

    // MARK: - Helper

    private func platformIcon(_ platform: AuthPlatform) -> String {
        switch platform {
        case .x: return "xmark.circle.fill"
        case .pixiv: return "paintbrush.fill"
        }
    }

    private func platformColor(_ platform: AuthPlatform) -> Color {
        switch platform {
        case .x: return .primary
        case .pixiv: return .blue
        }
    }

    private func isConfigured(_ platform: AuthPlatform) -> Bool {
        guard let status = authStatus else { return false }
        switch platform {
        case .x: return status.x
        case .pixiv: return status.pixiv
        }
    }

    // MARK: - Methods

    private func loadAuthStatus() async {
        do {
            let config = try await apiService.config.getDownloadConfig()
            authStatus = config.authStatus
        } catch {
            // 静默失败
        }
    }

    private func saveCredential(for platform: AuthPlatform) {
        let content = credentialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isSaving = true
        Task {
            do {
                try await apiService.config.uploadCredentials(platform: platform, content: content)
                await loadAuthStatus()
                credentialText = ""
                expandedPlatform = nil
                GlassAlertManager.shared.showSuccess("\(platform.displayName) 认证已保存")
            } catch {
                GlassAlertManager.shared.showError("保存失败", message: error.localizedDescription)
            }
            isSaving = false
        }
    }

    private func deleteCredential(for platform: AuthPlatform) {
        isDeleting = true
        Task {
            do {
                try await apiService.config.deleteCredentials(platform: platform)
                await loadAuthStatus()
                credentialText = ""
                expandedPlatform = nil
                GlassAlertManager.shared.showSuccess("\(platform.displayName) 认证已删除")
            } catch {
                GlassAlertManager.shared.showError("删除失败", message: error.localizedDescription)
            }
            isDeleting = false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
        if let api = APIService.create(for: server) {
            AuthSettingsView(apiService: api)
        }
    }
}
