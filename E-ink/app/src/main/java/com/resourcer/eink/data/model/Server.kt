package com.resourcer.eink.data.model

import java.util.UUID

/**
 * 服务器配置模型
 * 支持内网 HTTP 地址 + 公网 HTTPS 地址，可随时切换
 */
data class Server(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    /** 内网地址，如 http://192.168.1.100:1234 */
    val localUrl: String,
    /** 公网地址，如 https://example.com（可为空） */
    val remoteUrl: String = "",
    /** API Key 认证 */
    val apiKey: String,
    /** true = 使用公网地址，false = 使用内网地址 */
    val useRemote: Boolean = false
) {
    /** 当前激活的 URL */
    val activeUrl: String
        get() = if (useRemote && remoteUrl.isNotBlank()) remoteUrl else localUrl

    /** 切换内网/公网地址 */
    fun toggleUrl(): Server = copy(useRemote = !useRemote)

    /** 是否配置了公网地址 */
    val hasRemoteUrl: Boolean get() = remoteUrl.isNotBlank()

    /** 当前地址标签 */
    val activeLabel: String get() = if (useRemote && hasRemoteUrl) "公网" else "内网"
}
