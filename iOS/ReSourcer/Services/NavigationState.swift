//
//  NavigationState.swift
//  ReSourcer
//
//  全局导航状态 — 跨页面共享当前文件夹位置
//

import Foundation

/// 全局导航状态单例，供 Gallery / Classifier / Download 等页面共享当前文件夹位置
@MainActor @Observable
final class NavigationState {

    static let shared = NavigationState()

    /// 源文件夹路径
    var sourceFolder: String = ""

    /// 当前浏览的文件夹完整路径
    var currentFolderPath: String = ""

    /// 是否位于源文件夹根目录
    var isAtRoot: Bool {
        currentFolderPath == sourceFolder || currentFolderPath.isEmpty
    }

    /// 设置源文件夹（同时重置当前路径）
    func setSourceFolder(_ path: String) {
        sourceFolder = path
        currentFolderPath = path
    }

    /// 设置当前文件夹路径
    func setCurrentFolder(_ path: String) {
        currentFolderPath = path
    }

    private init() {}
}
