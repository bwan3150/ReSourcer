package com.resourcer.eink.data.prefs

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.resourcer.eink.data.model.Server

/**
 * 服务器配置本地持久化
 * 使用 SharedPreferences + Gson 存储 Server 对象列表
 */
class ServerPrefs(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("server_prefs", Context.MODE_PRIVATE)
    private val gson = Gson()

    companion object {
        private const val KEY_SERVERS = "servers"
        private const val KEY_ACTIVE_SERVER_ID = "active_server_id"
    }

    /** 保存服务器列表 */
    fun saveServers(servers: List<Server>) {
        prefs.edit()
            .putString(KEY_SERVERS, gson.toJson(servers))
            .apply()
    }

    /** 读取服务器列表 */
    fun loadServers(): List<Server> {
        val json = prefs.getString(KEY_SERVERS, null) ?: return emptyList()
        return try {
            val type = object : com.google.gson.reflect.TypeToken<List<Server>>() {}.type
            gson.fromJson(json, type) ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** 保存当前激活的服务器 ID */
    fun saveActiveServerId(id: String) {
        prefs.edit().putString(KEY_ACTIVE_SERVER_ID, id).apply()
    }

    /** 读取当前激活的服务器 ID */
    fun loadActiveServerId(): String? =
        prefs.getString(KEY_ACTIVE_SERVER_ID, null)

    /** 添加或更新服务器 */
    fun saveServer(server: Server) {
        val servers = loadServers().toMutableList()
        val idx = servers.indexOfFirst { it.id == server.id }
        if (idx >= 0) servers[idx] = server else servers.add(server)
        saveServers(servers)
    }

    /** 删除服务器 */
    fun deleteServer(serverId: String) {
        val servers = loadServers().filter { it.id != serverId }
        saveServers(servers)
        if (loadActiveServerId() == serverId) {
            saveActiveServerId(servers.firstOrNull()?.id ?: "")
        }
    }
}
