//
//  TagEditorView.swift
//  ReSourcer
//
//  标签编辑器 — 选择/创建/编辑/删除标签
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

    /// 新建标签
    @State private var showCreateTag = false
    @State private var newTagName = ""
    @State private var newTagColor = "#007AFF"

    /// 编辑标签
    @State private var editingTag: Tag? = nil
    @State private var editTagName = ""
    @State private var editTagColor = ""

    /// 关闭时回调（返回最新的文件标签）
    var onDismiss: (([Tag]) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    /// 预设颜色
    private let presetColors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D55",
        "#8E8E93", "#5856D6", "#00C7BE", "#A2845E"
    ]

    var body: some View {
        NavigationStack {
            List {
                // 已有标签列表
                Section {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if allTags.isEmpty {
                        Text("暂无标签，点击下方按钮创建")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(allTags) { tag in
                            tagRow(tag)
                        }
                    }
                } header: {
                    Text("选择标签")
                }

                // 新建标签
                Section {
                    if showCreateTag {
                        createTagForm
                    } else {
                        Button {
                            showCreateTag = true
                        } label: {
                            Label("新建标签", systemImage: "plus.circle")
                        }
                    }
                }
            }
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
            .sheet(item: $editingTag) { tag in
                editTagSheet(tag)
            }
        }
    }

    // MARK: - 标签行

    private func tagRow(_ tag: Tag) -> some View {
        Button {
            toggleTag(tag)
        } label: {
            HStack {
                Circle()
                    .fill(Color(hex: tag.color))
                    .frame(width: 12, height: 12)
                Text(tag.name)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedTagIds.contains(tag.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteTag(tag)
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                editingTag = tag
                editTagName = tag.name
                editTagColor = tag.color
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    // MARK: - 新建标签表单

    private var createTagForm: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            TextField("标签名称", text: $newTagName)
                .textFieldStyle(.roundedBorder)

            // 颜色选择
            Text("选择颜色")
                .font(.caption)
                .foregroundStyle(.secondary)
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

            HStack {
                Button("取消") {
                    showCreateTag = false
                    newTagName = ""
                    newTagColor = "#007AFF"
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("创建") {
                    createNewTag()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
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
            // 刷新列表
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
