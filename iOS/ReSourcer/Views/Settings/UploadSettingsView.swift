//
//  UploadSettingsView.swift
//  ReSourcer
//
//  上传设置页面：查看/调整服务器分片大小限制（大文件上传阈值）
//

import SwiftUI

struct UploadSettingsView: View {

    let apiService: APIService

    /// 当前服务器分片策略
    @State private var policy: UploadPolicyResponse?
    /// 输入的分片大小（MB，字符串以便编辑）
    @State private var inputMB: String = ""
    /// 加载 / 保存状态
    @State private var isLoading = false
    @State private var isSaving = false

    /// 快捷预设档位（MB）
    private let presets: [Int] = [10, 30, 50, 100, 200]

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // 当前策略卡片
                SettingsSection(title: "") {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.blue)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("分片大小限制")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)

                                Text("超过此大小的文件将自动分片上传")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            currentBadge
                        }
                    }
                }

                // 调整卡片
                SettingsSection(title: "") {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("调整分片大小（MB）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // 预设档位
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                ForEach(presets, id: \.self) { mb in
                                    GlassChip(
                                        "\(mb) MB",
                                        isSelected: inputMB == String(mb)
                                    ) {
                                        inputMB = String(mb)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        // 自定义数值输入
                        GlassTextField(
                            "",
                            text: $inputMB,
                            placeholder: "自定义大小",
                            icon: "number"
                        )
                        .keyboardType(.numberPad)

                        Text("范围 1 ~ 10240 MB。设置越小分片越多、单次请求越稳；设置越大分片越少。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        // 保存按钮
                        GlassButton(
                            "保存",
                            icon: "checkmark",
                            style: .primary,
                            size: .medium,
                            isEnabled: canSave,
                            isLoading: isSaving
                        ) {
                            Task { await save() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("上传设置")
        .task {
            await loadPolicy()
        }
    }

    // MARK: - 当前值 Badge

    private var currentBadge: some View {
        Group {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else if let policy {
                Text("\(policy.chunkSizeMb) MB")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            } else {
                Text("未知")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - 校验

    /// 解析后的合法 MB 值
    private var parsedMB: Int? {
        guard let v = Int(inputMB.trimmingCharacters(in: .whitespaces)), v >= 1, v <= 10240 else {
            return nil
        }
        return v
    }

    /// 是否可保存（值合法且与当前不同）
    private var canSave: Bool {
        guard let mb = parsedMB, !isSaving else { return false }
        return mb != policy?.chunkSizeMb
    }

    // MARK: - 数据加载 / 保存

    private func loadPolicy() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await apiService.upload.getUploadPolicy()
            policy = p
            inputMB = String(p.chunkSizeMb)
        } catch {
            policy = nil
        }
    }

    private func save() async {
        guard let mb = parsedMB else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await apiService.upload.updateUploadPolicy(chunkSizeMb: mb)
            policy = updated
            inputMB = String(updated.chunkSizeMb)
            GlassAlertManager.shared.showSuccess("已保存", message: "分片大小已设为 \(updated.chunkSizeMb) MB")
        } catch {
            GlassAlertManager.shared.showError("保存失败", message: error.localizedDescription)
        }
    }
}
