package com.resourcer.eink.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.resourcer.eink.data.model.*
import com.resourcer.eink.data.network.ApiClient
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class GalleryViewModel : ViewModel() {

    companion object {
        private const val PAGE_SIZE = 50
    }

    data class UiState(
        val isLoading: Boolean = false,
        val errorMsg: String? = null,
        val currentPath: String = "",
        val currentSourceFolder: String = "",
        val breadcrumb: List<BreadcrumbItem> = emptyList(),
        val subfolders: List<IndexedFolder> = emptyList(),
        val files: List<IndexedFile> = emptyList(),
        val filesTotal: Int = 0,
        val hasMoreFiles: Boolean = false,
        val isLoadingMore: Boolean = false,
        val sourceFolders: List<GalleryFolderInfo> = emptyList()
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val backStack = ArrayDeque<Pair<String, String>>() // (path, sourceFolder)
    private var filesOffset = 0
    private var loadMoreJob: Job? = null

    // ─── 根目录 ────────────────────────────────────────────────────────────

    fun loadRoot(server: Server) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMsg = null)
            try {
                val api = ApiClient.getApiService(server)
                backStack.clear()
                // 优先用 /api/config/sources 取当前活跃源文件夹，否则取 folderList 第一个
                val currentSf = runCatching { api.configSources().current }.getOrNull()
                    ?: runCatching { api.folderList().folders.firstOrNull()?.path }.getOrNull()
                if (!currentSf.isNullOrEmpty()) {
                    loadFolder(server, currentSf, currentSf)
                } else {
                    _uiState.value = UiState(isLoading = false, errorMsg = "未找到源文件夹")
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, errorMsg = "加载失败：${e.message}")
            }
        }
    }

    // ─── 进入文件夹 ────────────────────────────────────────────────────────

    fun enterFolder(server: Server, folderPath: String, sourceFolder: String? = null) {
        backStack.addLast(_uiState.value.currentPath to _uiState.value.currentSourceFolder)
        val sf = sourceFolder ?: _uiState.value.currentSourceFolder
        loadFolder(server, folderPath, sf)
    }

    fun navigateTo(server: Server, path: String) {
        if (path.isEmpty()) {
            backStack.clear()
            loadRoot(server)
            return
        }
        if (path != _uiState.value.currentPath) {
            backStack.addLast(_uiState.value.currentPath to _uiState.value.currentSourceFolder)
            loadFolder(server, path, _uiState.value.currentSourceFolder)
        }
    }

    fun navigateBack(server: Server): Boolean {
        if (backStack.isEmpty()) return false
        val (prevPath, prevSf) = backStack.removeLast()
        if (prevPath.isEmpty()) loadRoot(server)
        else loadFolder(server, prevPath, prevSf)
        return true
    }

    val canGoBack: Boolean get() = backStack.isNotEmpty()

    // ─── 加载文件夹 ────────────────────────────────────────────────────────

    private fun loadFolder(server: Server, folderPath: String, sourceFolder: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                isLoading = true, errorMsg = null,
                currentPath = folderPath, currentSourceFolder = sourceFolder,
                files = emptyList(), subfolders = emptyList(), hasMoreFiles = false
            )
            filesOffset = 0
            try {
                val api = ApiClient.getApiService(server)

                val filesResp = api.indexerFiles(folderPath = folderPath, offset = 0, limit = PAGE_SIZE)

                val breadcrumbResp = runCatching {
                    api.indexerBreadcrumb(folderPath = folderPath)
                }.getOrNull()

                filesOffset = PAGE_SIZE
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    subfolders = emptyList(),
                    files = filesResp.files,
                    filesTotal = filesResp.total,
                    hasMoreFiles = filesResp.hasMore,
                    breadcrumb = breadcrumbResp?.breadcrumb ?: emptyList(),
                    sourceFolders = emptyList()
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, errorMsg = "加载失败：${e.message}")
            }
        }
    }

    // ─── 加载更多 ──────────────────────────────────────────────────────────

    fun loadMoreFiles(server: Server) {
        val state = _uiState.value
        if (!state.hasMoreFiles || state.isLoadingMore) return
        loadMoreJob?.cancel()
        loadMoreJob = viewModelScope.launch {
            _uiState.value = state.copy(isLoadingMore = true)
            try {
                val api = ApiClient.getApiService(server)
                val resp = api.indexerFiles(folderPath = state.currentPath, offset = filesOffset, limit = PAGE_SIZE)
                filesOffset += PAGE_SIZE
                _uiState.value = _uiState.value.copy(
                    isLoadingMore = false,
                    files = _uiState.value.files + resp.files,
                    hasMoreFiles = resp.hasMore
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoadingMore = false, errorMsg = "加载更多失败：${e.message}")
            }
        }
    }

    fun refresh(server: Server) {
        val state = _uiState.value
        if (state.currentPath.isEmpty()) loadRoot(server)
        else loadFolder(server, state.currentPath, state.currentSourceFolder)
    }

    /** 源文件夹切换后重置 */
    fun resetForSourceFolderChange(server: Server) {
        backStack.clear()
        loadRoot(server)
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMsg = null)
    }
}
