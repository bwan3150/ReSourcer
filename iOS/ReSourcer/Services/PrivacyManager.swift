//
//  PrivacyManager.swift
//  ReSourcer
//
//  私密源文件夹管理 - 本地存储私密标记，Keychain 存储手势图案哈希
//  私密标记与手势密码仅保存在本机，不同步到服务器；忘记手势无法找回
//

import Foundation
import CryptoKit
import Security

/// 私密源文件夹管理器（单例）
/// - 私密路径集合存 UserDefaults
/// - 手势图案哈希存 Keychain
/// - 会话解锁状态仅存内存，App 重启后自动重置为未解锁
@MainActor @Observable
final class PrivacyManager {

    static let shared = PrivacyManager()

    /// 本次会话是否已解锁私密（App 重启后重置为 false）
    var isUnlocked = false

    /// 私密源文件夹路径集合
    private(set) var privateFolders: Set<String>

    private init() {
        let arr = UserDefaults.standard.stringArray(forKey: Self.privateKey) ?? []
        privateFolders = Set(arr)
    }

    // MARK: - 私密路径集合

    private static let privateKey = "private_source_folders"

    /// 指定路径是否为私密
    func isPrivate(_ path: String) -> Bool {
        privateFolders.contains(path)
    }

    /// 设置/取消某路径的私密标记
    func setPrivate(_ path: String, _ value: Bool) {
        if value {
            privateFolders.insert(path)
        } else {
            privateFolders.remove(path)
        }
        UserDefaults.standard.set(Array(privateFolders), forKey: Self.privateKey)
    }

    // MARK: - 手势图案（Keychain）

    private let patternAccount = "resourcer.privacy.pattern"

    /// 是否已设置手势图案
    var hasPattern: Bool {
        KeychainHelper.read(account: patternAccount) != nil
    }

    /// 设置手势图案（覆盖旧值）
    func setPattern(_ dots: [Int]) {
        KeychainHelper.save(Self.hash(dots), account: patternAccount)
    }

    /// 校验手势图案是否正确
    func verifyPattern(_ dots: [Int]) -> Bool {
        guard let stored = KeychainHelper.read(account: patternAccount) else { return false }
        return stored == Self.hash(dots)
    }

    /// 清除手势图案
    func clearPattern() {
        KeychainHelper.delete(account: patternAccount)
    }

    /// 将手势点序列哈希为字符串（SHA256）
    private static func hash(_ dots: [Int]) -> String {
        let raw = dots.map(String.init).joined(separator: "-")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Keychain 简易封装

/// 通用密码型 Keychain 读写封装
enum KeychainHelper {

    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
