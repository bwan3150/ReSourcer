package com.resourcer.eink.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.resourcer.eink.data.model.Server
import com.resourcer.eink.data.network.ApiClient
import com.resourcer.eink.data.prefs.ServerPrefs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 服务器管理 ViewModel
 */
class ServerViewModel(application: Application) : AndroidViewModel(application) {

    private val prefs = ServerPrefs(application)

    private val _servers = MutableStateFlow<List<Server>>(emptyList())
    val servers: StateFlow<List<Server>> = _servers.asStateFlow()

    private val _activeServer = MutableStateFlow<Server?>(null)
    val activeServer: StateFlow<Server?> = _activeServer.asStateFlow()

    /** 测试连接状态：null=未测试, true=成功, false=失败 */
    private val _testResult = MutableStateFlow<Boolean?>(null)
    val testResult: StateFlow<Boolean?> = _testResult.asStateFlow()

    private val _isTesting = MutableStateFlow(false)
    val isTesting: StateFlow<Boolean> = _isTesting.asStateFlow()

    init {
        loadFromPrefs()
    }

    private fun loadFromPrefs() {
        val servers = prefs.loadServers()
        _servers.value = servers
        val activeId = prefs.loadActiveServerId()
        _activeServer.value = servers.firstOrNull { it.id == activeId }
            ?: servers.firstOrNull()
    }

    /** 保存/更新服务器配置 */
    fun saveServer(server: Server) {
        prefs.saveServer(server)
        loadFromPrefs()
        // 若当前无激活服务器，将新服务器设为激活
        if (_activeServer.value == null) {
            setActiveServer(server)
        }
    }

    /** 设置当前激活服务器 */
    fun setActiveServer(server: Server) {
        _activeServer.value = server
        prefs.saveActiveServerId(server.id)
        // 重建 API 客户端
        ApiClient.getApiService(server)
    }

    /** 切换内网/公网地址 */
    fun toggleServerUrl(server: Server) {
        val updated = server.toggleUrl()
        prefs.saveServer(updated)
        if (_activeServer.value?.id == server.id) {
            _activeServer.value = updated
            // 重建 API 客户端以使用新地址
            ApiClient.getApiService(updated)
        }
        loadFromPrefs()
    }

    /** 删除服务器 */
    fun deleteServer(serverId: String) {
        prefs.deleteServer(serverId)
        loadFromPrefs()
    }

    /** 测试服务器连接 */
    fun testConnection(server: Server) {
        viewModelScope.launch {
            _isTesting.value = true
            _testResult.value = null
            try {
                val api = ApiClient.getApiService(server)
                val response = api.authCheck()
                _testResult.value = response.isSuccessful
            } catch (e: Exception) {
                _testResult.value = false
            } finally {
                _isTesting.value = false
            }
        }
    }

    /** 清除测试结果 */
    fun clearTestResult() {
        _testResult.value = null
    }
}
