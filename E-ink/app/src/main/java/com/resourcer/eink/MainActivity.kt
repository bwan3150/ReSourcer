package com.resourcer.eink

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.resourcer.eink.data.model.IndexedFile
import com.resourcer.eink.data.model.Server
import com.resourcer.eink.ui.screens.GalleryScreen
import com.resourcer.eink.ui.screens.PreviewScreen
import com.resourcer.eink.ui.screens.ServerSetupScreen
import com.resourcer.eink.ui.screens.SettingsScreen
import com.resourcer.eink.ui.theme.EInkTheme
import com.resourcer.eink.ui.theme.EInkWhite
import com.resourcer.eink.ui.viewmodel.GalleryViewModel
import com.resourcer.eink.ui.viewmodel.ServerViewModel
import com.resourcer.eink.ui.viewmodel.SettingsViewModel

/**
 * 主 Activity
 * 导航结构：
 *  - 未配置服务器 → ServerSetupScreen（全屏）
 *  - 已配置 → 底部 NavBar（Gallery | Settings）
 *  - 点击文件 → PreviewScreen（全屏覆盖）
 */
class MainActivity : ComponentActivity() {

    private val serverViewModel: ServerViewModel by viewModels()
    private val galleryViewModel: GalleryViewModel by viewModels()
    private val settingsViewModel: SettingsViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            EInkTheme {
                AppRoot(
                    serverViewModel = serverViewModel,
                    galleryViewModel = galleryViewModel,
                    settingsViewModel = settingsViewModel
                )
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 根路由
// ─────────────────────────────────────────────────────────────────────────────

enum class BottomTab { GALLERY, SETTINGS }

@Composable
private fun AppRoot(
    serverViewModel: ServerViewModel,
    galleryViewModel: GalleryViewModel,
    settingsViewModel: SettingsViewModel
) {
    val activeServer by serverViewModel.activeServer.collectAsState()

    // 文件预览状态（不走导航栈，直接覆盖）
    var previewFiles by remember { mutableStateOf<List<IndexedFile>>(emptyList()) }
    var previewIndex by remember { mutableIntStateOf(0) }
    val showPreview = previewFiles.isNotEmpty()

    if (activeServer == null) {
        // ── 未配置服务器 → 全屏服务器设置 ──────────────────────────────
        ServerSetupScreen(
            viewModel = serverViewModel,
            onServerSelected = { /* 会自动触发 activeServer 更新 */ }
        )
    } else {
        // ── 主界面始终保持组合，PreviewScreen 以 Box 覆盖在上方（保留 Gallery 文件夹状态）
        Box(modifier = androidx.compose.ui.Modifier.fillMaxSize()) {
            MainTabScreen(
                server = activeServer!!,
                serverViewModel = serverViewModel,
                galleryViewModel = galleryViewModel,
                settingsViewModel = settingsViewModel,
                onFileClick = { files, idx ->
                    previewFiles = files
                    previewIndex = idx
                }
            )
            if (showPreview) {
                PreviewScreen(
                    server = activeServer!!,
                    files = previewFiles,
                    initialIndex = previewIndex,
                    onBack = { previewFiles = emptyList() }
                )
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 底部导航主界面
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun MainTabScreen(
    server: Server,
    serverViewModel: ServerViewModel,
    galleryViewModel: GalleryViewModel,
    settingsViewModel: SettingsViewModel,
    onFileClick: (List<IndexedFile>, Int) -> Unit
) {
    var currentTab by remember { mutableStateOf(BottomTab.GALLERY) }

    Scaffold(
        bottomBar = {
            NavigationBar(
                containerColor = EInkWhite,
                tonalElevation = 0.dp
            ) {
                NavigationBarItem(
                    selected = currentTab == BottomTab.GALLERY,
                    onClick = { currentTab = BottomTab.GALLERY },
                    icon = { Icon(Icons.Default.Photo, contentDescription = null) },
                    label = { Text("图库", fontSize = 12.sp, fontWeight = if (currentTab == BottomTab.GALLERY) FontWeight.Bold else FontWeight.Normal) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = androidx.compose.ui.graphics.Color.Black,
                        selectedTextColor = androidx.compose.ui.graphics.Color.Black,
                        indicatorColor = androidx.compose.ui.graphics.Color(0xFFE8E8E8),
                        unselectedIconColor = androidx.compose.ui.graphics.Color(0xFF888888),
                        unselectedTextColor = androidx.compose.ui.graphics.Color(0xFF888888)
                    )
                )
                NavigationBarItem(
                    selected = currentTab == BottomTab.SETTINGS,
                    onClick = { currentTab = BottomTab.SETTINGS },
                    icon = { Icon(Icons.Default.Settings, contentDescription = null) },
                    label = { Text("设置", fontSize = 12.sp, fontWeight = if (currentTab == BottomTab.SETTINGS) FontWeight.Bold else FontWeight.Normal) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = androidx.compose.ui.graphics.Color.Black,
                        selectedTextColor = androidx.compose.ui.graphics.Color.Black,
                        indicatorColor = androidx.compose.ui.graphics.Color(0xFFE8E8E8),
                        unselectedIconColor = androidx.compose.ui.graphics.Color(0xFF888888),
                        unselectedTextColor = androidx.compose.ui.graphics.Color(0xFF888888)
                    )
                )
            }
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when (currentTab) {
                BottomTab.GALLERY -> GalleryScreen(
                    server = server,
                    viewModel = galleryViewModel,
                    onFileClick = onFileClick
                )
                BottomTab.SETTINGS -> SettingsScreen(
                    server = server,
                    serverViewModel = serverViewModel,
                    settingsViewModel = settingsViewModel,
                    onGalleryRefreshNeeded = {
                        galleryViewModel.resetForSourceFolderChange(server)
                        currentTab = BottomTab.GALLERY
                    }
                )
            }
        }
    }
}
