package com.resourcer.eink.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.resourcer.eink.data.model.Server
import com.resourcer.eink.ui.theme.*
import com.resourcer.eink.ui.viewmodel.ServerViewModel
import com.resourcer.eink.ui.viewmodel.SettingsViewModel

/**
 * 设置页面
 * - 服务器状态 + 内网/公网切换
 * - 源文件夹切换
 * - 缩略图缓存管理（按源文件夹清除）
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    server: Server,
    serverViewModel: ServerViewModel,
    settingsViewModel: SettingsViewModel,
    onGalleryRefreshNeeded: () -> Unit
) {
    val uiState by settingsViewModel.uiState.collectAsState()

    // 进入页面时加载数据
    LaunchedEffect(server.activeUrl) {
        settingsViewModel.load(server)
    }

    // Toast 提示
    uiState.toast?.let { msg ->
        LaunchedEffect(msg) {
            kotlinx.coroutines.delay(2000)
            settingsViewModel.clearToast()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("设置", fontWeight = FontWeight.Bold, fontSize = 18.sp) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = EInkWhite,
                    titleContentColor = EInkBlack
                )
            )
        },
        snackbarHost = {
            uiState.toast?.let { msg ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 80.dp, start = 16.dp, end = 16.dp),
                    contentAlignment = Alignment.BottomCenter
                ) {
                    Surface(
                        color = EInkDarkGray,
                        shape = MaterialTheme.shapes.small
                    ) {
                        Text(
                            msg,
                            color = EInkWhite,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                            fontSize = 14.sp
                        )
                    }
                }
            }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(vertical = 16.dp)
        ) {
            // ── 1. 服务器状态 ───────────────────────────────────────────
            item {
                SettingsSection(title = "服务器") {
                    // 服务器名称 + 状态
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            if (server.useRemote) Icons.Default.Cloud else Icons.Default.Home,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = EInkGray
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(server.name, fontSize = 15.sp, color = EInkBlack, fontWeight = FontWeight.Medium)
                            Text(
                                server.activeUrl,
                                fontSize = 11.sp,
                                color = EInkGray,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                        // 状态指示
                        StatusDot(uiState.serverStatus)
                    }

                    // 内网 / 公网切换（仅在配置了两个地址时显示）
                    if (server.hasRemoteUrl) {
                        HorizontalDivider(color = EInkVeryLightGray)
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            "地址切换",
                            fontSize = 12.sp,
                            color = EInkGray,
                            fontWeight = FontWeight.Medium
                        )
                        Spacer(modifier = Modifier.height(8.dp))

                        UrlRow(
                            label = "内网",
                            url = server.localUrl,
                            isActive = !server.useRemote,
                            isLoading = uiState.isSwitchingUrl && server.useRemote,
                            onClick = {
                                if (server.useRemote) {
                                    settingsViewModel.switchUrl(serverViewModel, server, false)
                                }
                            }
                        )
                        Spacer(modifier = Modifier.height(6.dp))
                        UrlRow(
                            label = "公网",
                            url = server.remoteUrl,
                            isActive = server.useRemote,
                            isLoading = uiState.isSwitchingUrl && !server.useRemote,
                            onClick = {
                                if (!server.useRemote) {
                                    settingsViewModel.switchUrl(serverViewModel, server, true)
                                }
                            }
                        )
                    }
                }
            }

            // ── 2. 源文件夹 ──────────────────────────────────────────────
            item {
                SettingsSection(title = "源文件夹") {
                    val sf = uiState.sourceFolders
                    if (uiState.isLoadingSourceFolders || sf == null) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = EInkGray
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("加载中...", fontSize = 14.sp, color = EInkGray)
                        }
                    } else {
                        val allFolders = listOf(sf.current) + sf.backups
                        allFolders.forEachIndexed { idx, path ->
                            val isCurrent = path == sf.current
                            SourceFolderRow(
                                path = path,
                                isCurrent = isCurrent,
                                isLoading = uiState.isSwitchingFolder && !isCurrent,
                                onClick = {
                                    if (!isCurrent) {
                                        settingsViewModel.switchSourceFolder(server, path) {
                                            onGalleryRefreshNeeded()
                                        }
                                    }
                                }
                            )
                            if (idx < allFolders.lastIndex) {
                                HorizontalDivider(
                                    color = EInkVeryLightGray,
                                    modifier = Modifier.padding(vertical = 4.dp)
                                )
                            }
                        }
                    }
                }
            }

            // ── 3. 缓存管理 ──────────────────────────────────────────────
            item {
                SettingsSection(title = "缩略图缓存") {
                    // 总大小
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.Storage,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                                tint = EInkGray
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("总缓存", fontSize = 14.sp, color = EInkBlack)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                formatBytes(uiState.totalCacheBytes),
                                fontSize = 13.sp,
                                color = EInkGray
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            OutlinedButton(
                                onClick = { settingsViewModel.clearAllCache(server) },
                                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                                modifier = Modifier.height(32.dp)
                            ) {
                                Text("全部清除", fontSize = 12.sp)
                            }
                        }
                    }

                    // 按源文件夹分项
                    if (uiState.cacheStats.isNotEmpty()) {
                        HorizontalDivider(
                            color = EInkVeryLightGray,
                            modifier = Modifier.padding(vertical = 10.dp)
                        )
                        Text(
                            "按文件夹清除",
                            fontSize = 12.sp,
                            color = EInkGray,
                            fontWeight = FontWeight.Medium
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        uiState.cacheStats.forEach { stat ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        stat.name,
                                        fontSize = 13.sp,
                                        color = EInkBlack,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    Text(stat.formattedSize(), fontSize = 11.sp, color = EInkGray)
                                }
                                Spacer(modifier = Modifier.width(8.dp))
                                TextButton(
                                    onClick = {
                                        settingsViewModel.clearSourceFolderCache(server, stat.sfPath)
                                    },
                                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp)
                                ) {
                                    Text("清除", fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                    }
                }
            }

            // 底部留空
            item { Spacer(modifier = Modifier.height(16.dp)) }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 子组件
// ─────────────────────────────────────────────────────────────────────────────

@Composable
fun SettingsSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column {
        if (title.isNotEmpty()) {
            Text(
                title,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = EInkGray,
                modifier = Modifier.padding(start = 4.dp, bottom = 6.dp)
            )
        }
        Surface(
            color = EInkVeryLightGray,
            shape = MaterialTheme.shapes.small,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(14.dp), content = content)
        }
    }
}

@Composable
private fun StatusDot(status: SettingsViewModel.ServerStatus) {
    val (color, label) = when (status) {
        SettingsViewModel.ServerStatus.ONLINE -> EInkBlack to "在线"
        SettingsViewModel.ServerStatus.AUTH_ERROR -> MaterialTheme.colorScheme.error to "认证错误"
        SettingsViewModel.ServerStatus.OFFLINE -> MaterialTheme.colorScheme.error to "离线"
        SettingsViewModel.ServerStatus.CHECKING -> EInkLightGray to "检查中"
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .then(
                    Modifier.padding(0.dp) // placeholder for shape
                )
        ) {
            Surface(
                modifier = Modifier.fillMaxSize(),
                shape = MaterialTheme.shapes.extraSmall,
                color = color
            ) {}
        }
        Spacer(modifier = Modifier.width(4.dp))
        Text(label, fontSize = 12.sp, color = EInkGray)
    }
}

@Composable
private fun UrlRow(
    label: String,
    url: String,
    isActive: Boolean,
    isLoading: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !isActive && !isLoading, onClick = onClick)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = EInkGray
            )
        } else {
            Icon(
                if (isActive) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = if (isActive) EInkBlack else EInkLightGray
            )
        }
        Spacer(modifier = Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                label,
                fontSize = 13.sp,
                color = if (isActive) EInkBlack else EInkGray,
                fontWeight = if (isActive) FontWeight.SemiBold else FontWeight.Normal
            )
            Text(
                url,
                fontSize = 11.sp,
                color = EInkLightGray,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun SourceFolderRow(
    path: String,
    isCurrent: Boolean,
    isLoading: Boolean,
    onClick: () -> Unit
) {
    val name = path.substringAfterLast('/').ifEmpty { path }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !isCurrent && !isLoading, onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = EInkGray
            )
        } else {
            Icon(
                if (isCurrent) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = if (isCurrent) EInkBlack else EInkLightGray
            )
        }
        Spacer(modifier = Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                name,
                fontSize = 14.sp,
                color = if (isCurrent) EInkBlack else EInkGray,
                fontWeight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal
            )
            Text(
                path,
                fontSize = 11.sp,
                color = EInkLightGray,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

fun formatBytes(bytes: Long): String = when {
    bytes <= 0L -> "0B"
    bytes < 1024 -> "${bytes}B"
    bytes < 1024 * 1024 -> "${bytes / 1024}KB"
    bytes < 1024L * 1024 * 1024 -> "${bytes / (1024 * 1024)}MB"
    else -> String.format("%.1fGB", bytes / (1024.0 * 1024 * 1024))
}
