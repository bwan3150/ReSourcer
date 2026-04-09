//
//  AboutView.swift
//  ReSourcer
//
//  About page - version info, update checks, links
//

import SwiftUI

struct AboutView: View {

    let apiService: APIService
    let appConfig: AppConfigResponse?

    @State private var isCheckingServer = false
    @State private var isCheckingIOS = false
    @State private var isUpdatingServer = false
    @State private var latestServerVersion: String?
    @State private var latestIOSVersion: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var hasServerUpdate: Bool {
        guard let latest = latestServerVersion else { return false }
        return latest != appConfig?.version
    }

    private var hasIOSUpdate: Bool {
        guard let latest = latestIOSVersion else { return false }
        return latest != appVersion
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                // Logo
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text("ReSourcer")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .padding(.top, AppTheme.Spacing.xl)

                // Version cards
                VStack(spacing: AppTheme.Spacing.md) {
                    versionRow(
                        label: "iOS",
                        current: appVersion,
                        latest: latestIOSVersion,
                        hasUpdate: hasIOSUpdate,
                        isChecking: isCheckingIOS,
                        onCheck: { Task { await checkIOSUpdate() } },
                        onUpdate: {
                            if let iosUrl = appConfig?.iosUrl, let url = URL(string: iosUrl) {
                                UIApplication.shared.open(url)
                            }
                        }
                    )

                    versionRow(
                        label: "Server",
                        current: appConfig?.version ?? "...",
                        latest: latestServerVersion,
                        hasUpdate: hasServerUpdate,
                        isChecking: isCheckingServer,
                        onCheck: { Task { await checkServerUpdate() } },
                        onUpdate: { Task { await triggerServerUpdate() } },
                        isUpdating: isUpdatingServer
                    )
                }

                // Links
                VStack(spacing: 0) {
                    if let iosUrl = appConfig?.iosUrl, let url = URL(string: iosUrl) {
                        linkRow(icon: "iphone", label: "iOS 下载") {
                            UIApplication.shared.open(url)
                        }
                        Divider().padding(.leading, 44)
                    }

                    linkRow(icon: nil, label: "GitHub", systemIcon: false) {
                        let urlString = appConfig?.githubUrl ?? "https://github.com/bwan3150/ReSourcer"
                        if let url = URL(string: urlString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(AppTheme.Spacing.md)
                .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Version Row

    private func versionRow(
        label: String,
        current: String,
        latest: String?,
        hasUpdate: Bool,
        isChecking: Bool,
        onCheck: @escaping () -> Void,
        onUpdate: @escaping () -> Void,
        isUpdating: Bool = false
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(current)
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.monospaced)
            }

            Spacer()

            if hasUpdate, let latest {
                Text(latest)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.orange))

                Button(action: onUpdate) {
                    Group {
                        if isUpdating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
            } else {
                Button(action: onCheck) {
                    Group {
                        if isChecking {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isChecking)
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - Link Row

    private func linkRow(icon: String?, label: String, systemIcon: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                if let icon, systemIcon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                } else {
                    Image("GithubIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                }

                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Methods

    private func checkIOSUpdate() async {
        isCheckingIOS = true
        if let version = await Self.fetchPgyerVersion() {
            await MainActor.run { latestIOSVersion = version }
            if version == appVersion {
                GlassAlertManager.shared.showSuccess("已是最新版本")
            }
        }
        isCheckingIOS = false
    }

    private func checkServerUpdate() async {
        isCheckingServer = true
        do {
            let result = try await apiService.config.checkUpdate()
            await MainActor.run { latestServerVersion = result.latestVersion }
            if result.latestVersion == appConfig?.version {
                GlassAlertManager.shared.showSuccess("已是最新版本")
            }
        } catch {}
        isCheckingServer = false
    }

    private func triggerServerUpdate() async {
        isUpdatingServer = true
        do {
            let result = try await apiService.config.updateServer()
            GlassAlertManager.shared.showSuccess(result.message)
            latestServerVersion = nil
            // Wait for server to restart
            await waitForRestart()
            isUpdatingServer = false
            GlassAlertManager.shared.showSuccess("服务器已重启")
        } catch {
            GlassAlertManager.shared.showError("更新失败")
            isUpdatingServer = false
        }
    }

    private func waitForRestart() async {
        // Phase 1: wait for server to go down
        var wentDown = false
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(500))
            do {
                _ = try await apiService.auth.checkHealth()
            } catch {
                wentDown = true; break
            }
        }
        if !wentDown {
            try? await Task.sleep(for: .seconds(2))
        }
        // Phase 2: wait for server to come back up
        for _ in 0..<30 {
            do {
                _ = try await apiService.auth.checkHealth()
                return
            } catch {}
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private static func fetchPgyerVersion() async -> String? {
        guard let url = URL(string: "https://www.pgyer.com/resourcer-ios") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let pattern = #"aVersion\s*=\s*'([^']+)'"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        } catch {
            return nil
        }
    }
}
