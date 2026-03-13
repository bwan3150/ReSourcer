package com.resourcer.eink.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.resourcer.eink.data.cache.SfCacheStats
import com.resourcer.eink.data.cache.ThumbnailCache
import com.resourcer.eink.data.model.Server
import com.resourcer.eink.data.model.SourceFoldersResponse
import com.resourcer.eink.data.model.SwitchSourceFolderRequest
import com.resourcer.eink.data.network.ApiClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 设置页面 ViewModel
 * - 服务器连接状态
 * - 切换内网/公网地址
 * - 切换源文件夹
 * - 缓存管理（按源文件夹清除）
 */
class SettingsViewModel(application: Application) : AndroidViewModel(application) {

    enum class ServerStatus { CHECKING, ONLINE, AUTH_ERROR, OFFLINE }

    data class UiState(
        val serverStatus: ServerStatus = ServerStatus.CHECKING,
        val sourceFolders: SourceFoldersResponse? = null,
        val isLoadingSourceFolders: Boolean = false,
        val isSwitchingFolder: Boolean = false,
        val isSwitchingUrl: Boolean = false,
        val cacheStats: List<SfCacheStats> = emptyList(),
        val totalCacheBytes: Long = 0L,
        val toast: String? = null
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val cache get() = ThumbnailCache.getInstance(getApplication<Application>().cacheDir)

    /** 进入设置页时加载所有数据 */
    fun load(server: Server) {
        viewModelScope.launch {
            checkHealth(server)
            loadSourceFolders(server)
            refreshCacheStats(server)
        }
    }

    // ─── 服务器健康检查 ────────────────────────────────────────────────────

    private suspend fun checkHealth(server: Server) {
        _uiState.value = _uiState.value.copy(serverStatus = ServerStatus.CHECKING)
        try {
            val api = ApiClient.getApiService(server)
            val resp = api.authCheck()
            _uiState.value = _uiState.value.copy(
                serverStatus = if (resp.isSuccessful) ServerStatus.ONLINE else ServerStatus.AUTH_ERROR
            )
        } catch (_: Exception) {
            _uiState.value = _uiState.value.copy(serverStatus = ServerStatus.OFFLINE)
        }
    }

    // ─── 切换内网 / 公网 URL ───────────────────────────────────────────────

    /**
     * 切换到指定 URL，验证连接成功后才保存；失败则回退
     * 实际的 Server 对象由 ServerViewModel 持有，这里只做连接验证
     * 返回 true 表示切换成功
     */
    fun switchUrl(
        serverViewModel: ServerViewModel,
        server: Server,
        useRemote: Boolean
    ) {
        if (_uiState.value.isSwitchingUrl) return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isSwitchingUrl = true)
            val updated = server.copy(useRemote = useRemote)
            try {
                val api = ApiClient.getApiService(updated)
                val resp = api.authCheck()
                if (resp.isSuccessful) {
                    serverViewModel.saveServer(updated)
                    serverViewModel.setActiveServer(updated)
                    _uiState.value = _uiState.value.copy(
                        isSwitchingUrl = false,
                        serverStatus = ServerStatus.ONLINE,
                        toast = "已切换到${updated.activeLabel}地址"
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isSwitchingUrl = false,
                        toast = "连接失败，已保持原地址"
                    )
                }
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(
                    isSwitchingUrl = false,
                    toast = "连接失败，已保持原地址"
                )
            }
        }
    }

    // ─── 源文件夹 ──────────────────────────────────────────────────────────

    private suspend fun loadSourceFolders(server: Server) {
        _uiState.value = _uiState.value.copy(isLoadingSourceFolders = true)
        try {
            val api = ApiClient.getApiService(server)
            val resp = api.configSources()
            _uiState.value = _uiState.value.copy(
                sourceFolders = resp,
                isLoadingSourceFolders = false
            )
        } catch (_: Exception) {
            _uiState.value = _uiState.value.copy(isLoadingSourceFolders = false)
        }
    }

    /** 切换源文件夹，切换成功后重新加载列表 */
    fun switchSourceFolder(server: Server, path: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isSwitchingFolder = true)
            try {
                val api = ApiClient.getApiService(server)
                api.configSourcesSwitch(SwitchSourceFolderRequest(path))
                val resp = api.configSources()
                _uiState.value = _uiState.value.copy(
                    sourceFolders = resp,
                    isSwitchingFolder = false,
                    toast = "已切换到 ${path.substringAfterLast('/')}"
                )
                onSuccess()
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(
                    isSwitchingFolder = false,
                    toast = "切换失败"
                )
            }
        }
    }

    // ─── 缓存管理 ──────────────────────────────────────────────────────────

    private fun refreshCacheStats(server: Server) {
        val stats = cache.sourceFolderStats(server.activeUrl)
        _uiState.value = _uiState.value.copy(
            cacheStats = stats,
            totalCacheBytes = cache.totalSize()
        )
    }

    /** 清除全部缩略图缓存 */
    fun clearAllCache(server: Server) {
        cache.clearAll()
        refreshCacheStats(server)
        _uiState.value = _uiState.value.copy(toast = "缓存已清除")
    }

    /** 清除指定源文件夹的缩略图缓存 */
    fun clearSourceFolderCache(server: Server, sfPath: String) {
        cache.clearBySourceFolder(sfPath, server.activeUrl)
        refreshCacheStats(server)
        _uiState.value = _uiState.value.copy(
            toast = "已清除 ${sfPath.substringAfterLast('/')} 的缩略图"
        )
    }

    fun clearToast() {
        _uiState.value = _uiState.value.copy(toast = null)
    }
}
