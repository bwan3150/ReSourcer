package com.resourcer.eink.ui.screens

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.resourcer.eink.data.model.Server
import com.resourcer.eink.ui.theme.*
import com.resourcer.eink.ui.viewmodel.ServerViewModel

/**
 * 服务器管理界面
 * - 列出已保存的服务器
 * - 添加/编辑服务器（内网地址 + 公网地址 + API Key）
 * - 切换内网/公网
 * - 测试连接
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ServerSetupScreen(
    viewModel: ServerViewModel,
    onServerSelected: (Server) -> Unit
) {
    val servers by viewModel.servers.collectAsState()
    val activeServer by viewModel.activeServer.collectAsState()
    val testResult by viewModel.testResult.collectAsState()
    val isTesting by viewModel.isTesting.collectAsState()

    var showAddDialog by remember { mutableStateOf(false) }
    var editingServer by remember { mutableStateOf<Server?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "服务器管理",
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp
                    )
                },
                actions = {
                    IconButton(onClick = { showAddDialog = true }) {
                        Icon(Icons.Default.Add, contentDescription = "添加服务器")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = EInkWhite,
                    titleContentColor = EInkBlack
                )
            )
        }
    ) { padding ->
        if (servers.isEmpty()) {
            // 空状态提示
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.Storage,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = EInkLightGray
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text("还没有服务器", color = EInkGray, fontSize = 16.sp)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("点击右上角添加", color = EInkLightGray, fontSize = 14.sp)
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                items(servers) { server ->
                    ServerItem(
                        server = server,
                        isActive = activeServer?.id == server.id,
                        onSelect = {
                            viewModel.setActiveServer(server)
                            onServerSelected(server)
                        },
                        onEdit = { editingServer = server },
                        onDelete = { viewModel.deleteServer(server.id) },
                        onToggleUrl = { viewModel.toggleServerUrl(server) },
                        onTest = { viewModel.testConnection(server) },
                        isTesting = isTesting && activeServer?.id == server.id,
                        testResult = if (activeServer?.id == server.id) testResult else null
                    )
                    HorizontalDivider(color = EInkVeryLightGray)
                }
            }
        }
    }

    // 添加服务器弹窗
    if (showAddDialog) {
        ServerEditDialog(
            server = null,
            onDismiss = { showAddDialog = false },
            onSave = { server ->
                viewModel.saveServer(server)
                showAddDialog = false
            }
        )
    }

    // 编辑服务器弹窗
    editingServer?.let { server ->
        ServerEditDialog(
            server = server,
            onDismiss = { editingServer = null },
            onSave = { updated ->
                viewModel.saveServer(updated)
                editingServer = null
            }
        )
    }
}

@Composable
private fun ServerItem(
    server: Server,
    isActive: Boolean,
    onSelect: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onToggleUrl: () -> Unit,
    onTest: () -> Unit,
    isTesting: Boolean,
    testResult: Boolean?
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(16.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
        ) {
            // 激活指示
            if (isActive) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .padding(end = 0.dp)
                ) {
                    // 实心圆点表示激活
                    Icon(
                        Icons.Default.Circle,
                        contentDescription = "已激活",
                        modifier = Modifier.size(8.dp),
                        tint = EInkBlack
                    )
                }
                Spacer(modifier = Modifier.width(8.dp))
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = server.name,
                    fontWeight = if (isActive) FontWeight.Bold else FontWeight.Normal,
                    fontSize = 16.sp,
                    color = EInkBlack
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = server.activeUrl,
                    fontSize = 12.sp,
                    color = EInkGray
                )
                if (server.hasRemoteUrl) {
                    Text(
                        text = "当前：${server.activeLabel}",
                        fontSize = 11.sp,
                        color = EInkLightGray
                    )
                }
            }

            // 操作按钮
            Row {
                if (server.hasRemoteUrl) {
                    IconButton(onClick = onToggleUrl, modifier = Modifier.size(36.dp)) {
                        Icon(
                            Icons.Default.SwapHoriz,
                            contentDescription = "切换地址",
                            tint = EInkGray,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
                IconButton(onClick = onTest, modifier = Modifier.size(36.dp)) {
                    if (isTesting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                            color = EInkGray
                        )
                    } else {
                        Icon(
                            Icons.Default.NetworkCheck,
                            contentDescription = "测试连接",
                            tint = when (testResult) {
                                true -> EInkBlack
                                false -> MaterialTheme.colorScheme.error
                                null -> EInkGray
                            },
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
                IconButton(onClick = onEdit, modifier = Modifier.size(36.dp)) {
                    Icon(
                        Icons.Default.Edit,
                        contentDescription = "编辑",
                        tint = EInkGray,
                        modifier = Modifier.size(20.dp)
                    )
                }
                IconButton(onClick = onDelete, modifier = Modifier.size(36.dp)) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = "删除",
                        tint = EInkLightGray,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        }

        // 测试结果提示
        testResult?.let {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = if (it) "✓ 连接成功" else "✗ 连接失败",
                fontSize = 12.sp,
                color = if (it) EInkBlack else MaterialTheme.colorScheme.error
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ServerEditDialog(
    server: Server?,
    onDismiss: () -> Unit,
    onSave: (Server) -> Unit
) {
    var name by remember { mutableStateOf(server?.name ?: "") }
    var localUrl by remember { mutableStateOf(server?.localUrl ?: "http://") }
    var remoteUrl by remember { mutableStateOf(server?.remoteUrl ?: "") }
    var apiKey by remember { mutableStateOf(server?.apiKey ?: "") }
    var showApiKey by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(if (server == null) "添加服务器" else "编辑服务器")
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("名称") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                OutlinedTextField(
                    value = localUrl,
                    onValueChange = { localUrl = it },
                    label = { Text("内网地址（HTTP）") },
                    placeholder = { Text("http://192.168.x.x:1234") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
                )
                OutlinedTextField(
                    value = remoteUrl,
                    onValueChange = { remoteUrl = it },
                    label = { Text("公网地址（HTTPS，可选）") },
                    placeholder = { Text("https://example.com") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
                )
                OutlinedTextField(
                    value = apiKey,
                    onValueChange = { apiKey = it },
                    label = { Text("API Key") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = if (showApiKey) VisualTransformation.None
                    else PasswordVisualTransformation(),
                    trailingIcon = {
                        IconButton(onClick = { showApiKey = !showApiKey }) {
                            Icon(
                                if (showApiKey) Icons.Default.VisibilityOff
                                else Icons.Default.Visibility,
                                contentDescription = null
                            )
                        }
                    }
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (name.isNotBlank() && localUrl.isNotBlank() && apiKey.isNotBlank()) {
                        onSave(
                            Server(
                                id = server?.id ?: java.util.UUID.randomUUID().toString(),
                                name = name.trim(),
                                localUrl = localUrl.trim().trimEnd('/'),
                                remoteUrl = remoteUrl.trim().trimEnd('/'),
                                apiKey = apiKey.trim(),
                                useRemote = server?.useRemote ?: false
                            )
                        )
                    }
                }
            ) {
                Text("保存")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("取消")
            }
        }
    )
}
