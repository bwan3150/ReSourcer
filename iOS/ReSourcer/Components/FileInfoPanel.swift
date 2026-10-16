//
//  FileInfoPanel.swift
//  ReSourcer
//
//  文件信息面板：原生 presentationDetents（半屏 + 接近全高）+
//  底部操作栏固定、上方模块区独立滚动。
//

import SwiftUI

/// 信息面板两档高度：系统原生 `.medium`（半屏）+ `.large`（接近全高）。
enum FileInfoPanelDetent: String, Hashable {
    case half
    case expanded

    static let halfPresentation = PresentationDetent.medium
    static let expandedPresentation = PresentationDetent.large

    static var allPresentations: Set<PresentationDetent> {
        [halfPresentation, expandedPresentation]
    }

    var presentation: PresentationDetent {
        switch self {
        case .half: return Self.halfPresentation
        case .expanded: return Self.expandedPresentation
        }
    }

    init(presentation: PresentationDetent) {
        if presentation == Self.expandedPresentation {
            self = .expanded
        } else {
            self = .half
        }
    }
}

/// 原生 sheet 壳：标题 + 可滚模块区 + 固定底栏。
struct FileInfoPanel<Modules: View, Actions: View>: View {

    @Binding var isPresented: Bool
    var title: String = "文件信息"
    /// 初始 / 当前 detent（半屏或接近全高）
    @Binding var selectedDetent: FileInfoPanelDetent
    @ViewBuilder var modules: () -> Modules
    @ViewBuilder var actions: () -> Actions

    @State private var presentationSelection: PresentationDetent = FileInfoPanelDetent.halfPresentation

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                modules()
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    // 额外底距：滚到底时「基础信息」完整露在固定工具栏之上
                    .padding(.bottom, AppTheme.Spacing.lg)
            }
            // XCUITest scrolls this (not app-level swipe) so tall info sheets stay open.
            .accessibilityIdentifier("glassSheetScroll-\(title)")
            .scrollBounceBehavior(.basedOnSize)
            // 固定底栏：两档 detent 下都贴在 sheet 底部，不进 ScrollView、不被内容遮挡
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actions()
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.sm)
                    .padding(.bottom, AppTheme.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea(edges: .bottom)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents(
            FileInfoPanelDetent.allPresentations,
            selection: $presentationSelection
        )
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(AppTheme.CornerRadius.sheet)
        .accessibilityElement(children: .contain)
        .accessibilityValue(selectedDetent.rawValue)
        .background {
            // Detent probe for XCUITest — does not flatten child accessibility
            Color.clear
                .accessibilityIdentifier("fileInfoPanel-\(selectedDetent.rawValue)")
                .accessibilityValue(selectedDetent.rawValue)
                .allowsHitTesting(false)
        }
        .onAppear {
            presentationSelection = selectedDetent.presentation
        }
        .onChange(of: presentationSelection) { _, newValue in
            let mapped = FileInfoPanelDetent(presentation: newValue)
            if selectedDetent != mapped {
                selectedDetent = mapped
            }
        }
        .onChange(of: selectedDetent) { _, newValue in
            let target = newValue.presentation
            if presentationSelection != target {
                presentationSelection = target
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)

            Spacer()

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("关闭")
            .accessibilityIdentifier("glassSheetCloseButton")
        }
        .frame(height: AppTheme.BottomSheet.headerHeight)
        .padding(.horizontal, AppTheme.Spacing.sm)
    }
}

extension View {
    /// 文件信息面板：原生两档 detent + sticky 操作栏。
    func fileInfoPanel<Modules: View, Actions: View>(
        isPresented: Binding<Bool>,
        selectedDetent: Binding<FileInfoPanelDetent>,
        title: String = "文件信息",
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder modules: @escaping () -> Modules
    ) -> some View {
        sheet(isPresented: isPresented) {
            FileInfoPanel(
                isPresented: isPresented,
                title: title,
                selectedDetent: selectedDetent,
                modules: modules,
                actions: actions
            )
        }
    }
}
