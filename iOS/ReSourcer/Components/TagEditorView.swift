//
//  TagEditorView.swift
//  ReSourcer
//
//  标签编辑器 — 胶囊标签云 + 底部添加/编辑按钮
//

import SwiftUI

struct TagEditorView: View {

    let apiService: APIService
    let sourceFolder: String
    let fileUuid: String

    /// 当前文件已选中的标签 ID
    @State private var selectedTagIds: Set<Int> = []
    /// 当前源文件夹的所有标签
    @State private var allTags: [Tag] = []
    /// 加载中
    @State private var isLoading = true

    /// 编辑模式
    @State private var isEditMode = false

    /// 新建标签
    @State private var showCreateTag = false
    @State private var newTagName = ""
    @State private var newTagColor = "#007AFF"

    /// 编辑标签
    @State private var editingTag: Tag? = nil
    @State private var editTagName = ""
    @State private var editTagColor = ""

    /// 删除确认
    @State private var tagToDelete: Tag? = nil

    /// 关闭时回调（返回最新的文件标签）
    var onDismiss: (([Tag]) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    /// 预设颜色（6 列 × 7 行 = 42 色）
    private let presetColors = [
        "#FF3B30", "#FF6961", "#E74C3C", "#C0392B", "#FF2D55", "#D32F2F",
        "#FF9500", "#FF7043", "#F39C12", "#E67E22", "#FFCC00", "#FFD426",
        "#34C759", "#4CD964", "#2ECC71", "#27AE60", "#1ABC9C", "#16A085",
        "#00C7BE", "#20B2AA", "#3CB371", "#009688", "#00BCD4", "#5AC8FA",
        "#007AFF", "#2196F3", "#6495ED", "#1976D2", "#5856D6", "#3F51B5",
        "#AF52DE", "#9370DB", "#9C27B0", "#8E24AA", "#DA70D6", "#E91E63",
        "#A2845E", "#D2691E", "#F4A460", "#8E8E93", "#6D6D6D", "#4A4A4A"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 标签云区域
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if allTags.isEmpty {
                    Spacer()
                    Text("暂无标签")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        FlowLayout(spacing: 8) {
                            ForEach(allTags) { tag in
                                tagCapsule(tag)
                            }
                        }
                        .padding(.top, AppTheme.Spacing.sm)
                    }
                }

                Divider()

                // 底部按钮区
                HStack {
                    Button {
                        newTagName = ""
                        newTagColor = "#007AFF"
                        showCreateTag = true
                    } label: {
                        Label("添加", systemImage: "plus.circle")
                            .font(.body)
                    }

                    Spacer()

                    Button {
                        withAnimation { isEditMode.toggle() }
                    } label: {
                        Text(isEditMode ? "完成编辑" : "编辑")
                            .font(.body)
                    }
                    .disabled(allTags.isEmpty)
                }
            }
            .padding()
            .navigationTitle("编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saveAndDismiss()
                    }
                }
            }
            .task {
                await loadData()
            }
            .sheet(isPresented: $showCreateTag) {
                createTagSheet
            }
            .sheet(item: $editingTag) { tag in
                editTagSheet(tag)
            }
            .alert("删除标签", isPresented: Binding(
                get: { tagToDelete != nil },
                set: { if !$0 { tagToDelete = nil } }
            )) {
                Button("取消", role: .cancel) { tagToDelete = nil }
                Button("删除", role: .destructive) {
                    if let tag = tagToDelete {
                        deleteTag(tag)
                        tagToDelete = nil
                    }
                }
            } message: {
                if let tag = tagToDelete {
                    Text("确定删除标签「\(tag.name)」？此操作不可撤销。")
                }
            }
        }
    }

    // MARK: - 标签胶囊

    private func tagCapsule(_ tag: Tag) -> some View {
        let isSelected = selectedTagIds.contains(tag.id)
        return Button {
            if isEditMode {
                editingTag = tag
                editTagName = tag.name
                editTagColor = tag.color
            } else {
                toggleTag(tag)
            }
        } label: {
            HStack(spacing: 4) {
                Text(tag.name)
                    .font(.body)
                if isEditMode {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color(hex: tag.color).opacity(0.85)
                    : Color.gray.opacity(0.2)
            )
            .foregroundStyle(
                isSelected ? .white : .secondary
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 新建标签弹窗

    private var createTagSheet: some View {
        NavigationStack {
            Form {
                Section("标签名称") {
                    TextField("名称", text: $newTagName)
                }
                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(presetColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: newTagColor == color ? 2 : 0)
                                        .padding(-2)
                                )
                                .onTapGesture { newTagColor = color }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("新建标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showCreateTag = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        createNewTag()
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - 编辑标签弹窗

    private func editTagSheet(_ tag: Tag) -> some View {
        NavigationStack {
            Form {
                Section("标签名称") {
                    TextField("名称", text: $editTagName)
                }
                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(presetColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: editTagColor == color ? 2 : 0)
                                        .padding(-2)
                                )
                                .onTapGesture { editTagColor = color }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("删除标签", role: .destructive) {
                        editingTag = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            tagToDelete = tag
                        }
                    }
                }
            }
            .navigationTitle("编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingTag = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        updateTag(tag)
                    }
                    .disabled(editTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - 操作方法

    private func loadData() async {
        isLoading = true
        async let tagsResult = apiService.tag.getTags(sourceFolder: sourceFolder)
        async let fileTagsResult = apiService.tag.getFileTags(fileUuid: fileUuid)

        allTags = (try? await tagsResult) ?? []
        let fileTags = (try? await fileTagsResult) ?? []
        selectedTagIds = Set(fileTags.map { $0.id })
        isLoading = false
    }

    private func toggleTag(_ tag: Tag) {
        if selectedTagIds.contains(tag.id) {
            selectedTagIds.remove(tag.id)
        } else {
            selectedTagIds.insert(tag.id)
        }
    }

    private func createNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let color = newTagColor

        Task {
            if let tag = try? await apiService.tag.createTag(sourceFolder: sourceFolder, name: name, color: color) {
                allTags.append(tag)
                selectedTagIds.insert(tag.id)
                newTagName = ""
                newTagColor = "#007AFF"
                showCreateTag = false
            }
        }
    }

    private func updateTag(_ tag: Tag) {
        let name = editTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        Task {
            try? await apiService.tag.updateTag(id: tag.id, name: name, color: editTagColor)
            if let index = allTags.firstIndex(where: { $0.id == tag.id }) {
                allTags[index] = Tag(id: tag.id, sourceFolder: tag.sourceFolder, name: name, color: editTagColor, createdAt: tag.createdAt)
            }
            editingTag = nil
        }
    }

    private func deleteTag(_ tag: Tag) {
        Task {
            try? await apiService.tag.deleteTag(id: tag.id)
            allTags.removeAll { $0.id == tag.id }
            selectedTagIds.remove(tag.id)
        }
    }

    private func saveAndDismiss() {
        let tagIds = Array(selectedTagIds)
        Task {
            try? await apiService.tag.setFileTags(fileUuid: fileUuid, tagIds: tagIds)
            let updatedTags = allTags.filter { selectedTagIds.contains($0.id) }
            onDismiss?(updatedTags)
            dismiss()
        }
    }
}
