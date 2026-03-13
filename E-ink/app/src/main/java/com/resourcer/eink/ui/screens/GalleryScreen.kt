package com.resourcer.eink.ui.screens

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.resourcer.eink.data.cache.ThumbnailCache
import com.resourcer.eink.data.model.*
import com.resourcer.eink.data.network.ApiClient
import com.resourcer.eink.ui.theme.*
import com.resourcer.eink.ui.viewmodel.GalleryViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * Gallery 主界面
 * - 顶栏文件夹名称可点击 → 进入 FolderBrowserPage（全屏独立页面）
 * - FolderBrowserPage 选好目录后点"跳转" → 返回 Gallery 并刷新
 * - 无动画（电纸书优化）
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GalleryScreen(
    server: Server,
    viewModel: GalleryViewModel,
    onFileClick: (files: List<IndexedFile>, index: Int) -> Unit
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    var isGridView by remember { mutableStateOf(true) }
    var showFolderBrowser by remember { mutableStateOf(false) }
    val cache = remember { ThumbnailCache.getInstance(context.cacheDir) }
    val okHttpClient = remember(server) { ApiClient.getOkHttpClient(server) }

    // 初次加载
    LaunchedEffect(server.activeUrl) {
        viewModel.loadRoot(server)
    }

    // 进入文件夹浏览页时屏蔽 Gallery 的返回键
    BackHandler(enabled = viewModel.canGoBack && !showFolderBrowser) {
        viewModel.navigateBack(server)
    }

    if (showFolderBrowser) {
        // ── 全屏文件夹浏览页 ──────────────────────────────────────────────
        FolderBrowserPage(
            server = server,
            sourceFolder = uiState.currentSourceFolder,
            onNavigate = { selectedPath ->
                showFolderBrowser = false
                viewModel.navigateTo(server, selectedPath)
            },
            onDismiss = { showFolderBrowser = false }
        )
    } else {
        // ── 正常图库界面 ──────────────────────────────────────────────────
        Scaffold(
            topBar = {
                Column {
                    TopAppBar(
                        navigationIcon = {
                            if (viewModel.canGoBack) {
                                IconButton(onClick = { viewModel.navigateBack(server) }) {
                                    Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                                }
                            }
                        },
                        title = {
                            // 点击进入文件夹浏览页
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { showFolderBrowser = true }
                                    .padding(end = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    Icons.Default.Folder,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                    tint = EInkGray
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(
                                    currentFolderTitle(uiState),
                                    fontSize = 16.sp,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f)
                                )
                                Icon(
                                    Icons.Default.ChevronRight,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                    tint = EInkGray
                                )
                            }
                        },
                        actions = {
                            IconButton(onClick = { isGridView = !isGridView }) {
                                Icon(
                                    if (isGridView) Icons.Default.ViewList else Icons.Default.GridView,
                                    contentDescription = "切换视图"
                                )
                            }
                            IconButton(onClick = { viewModel.refresh(server) }) {
                                Icon(Icons.Default.Refresh, contentDescription = "刷新")
                            }
                        },
                        colors = TopAppBarDefaults.topAppBarColors(
                            containerColor = EInkWhite,
                            titleContentColor = EInkBlack,
                            actionIconContentColor = EInkBlack,
                            navigationIconContentColor = EInkBlack
                        )
                    )
                    HorizontalDivider(color = EInkLightGray)
                }
            }
        ) { padding ->
            Box(modifier = Modifier.fillMaxSize().padding(padding)) {
                when {
                    uiState.isLoading -> CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                        color = EInkBlack
                    )

                    uiState.errorMsg != null -> ErrorView(
                        message = uiState.errorMsg!!,
                        onRetry = { viewModel.refresh(server) },
                        modifier = Modifier.align(Alignment.Center)
                    )

                    uiState.files.isEmpty() -> {
                        Text(
                            "文件夹为空",
                            modifier = Modifier.align(Alignment.Center),
                            color = EInkGray
                        )
                    }

                    else -> {
                        if (isGridView) {
                            GridContentView(
                                server = server,
                                cache = cache,
                                okHttpClient = okHttpClient,
                                currentSourceFolder = uiState.currentSourceFolder,
                                files = uiState.files,
                                hasMore = uiState.hasMoreFiles,
                                isLoadingMore = uiState.isLoadingMore,
                                onFileClick = { file ->
                                    val idx = uiState.files.indexOf(file)
                                    if (idx >= 0) onFileClick(uiState.files, idx)
                                },
                                onLoadMore = { viewModel.loadMoreFiles(server) }
                            )
                        } else {
                            ListContentView(
                                server = server,
                                cache = cache,
                                okHttpClient = okHttpClient,
                                currentSourceFolder = uiState.currentSourceFolder,
                                files = uiState.files,
                                hasMore = uiState.hasMoreFiles,
                                isLoadingMore = uiState.isLoadingMore,
                                onFileClick = { file ->
                                    val idx = uiState.files.indexOf(file)
                                    if (idx >= 0) onFileClick(uiState.files, idx)
                                },
                                onLoadMore = { viewModel.loadMoreFiles(server) }
                            )
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 全屏文件夹浏览页
// ─────────────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FolderBrowserPage(
    server: Server,
    sourceFolder: String,
    onNavigate: (path: String) -> Unit,
    onDismiss: () -> Unit
) {
    // currentPath 独立保存，pathStack 仅做后退历史（不包含 currentPath）
    var currentPath by remember { mutableStateOf(sourceFolder) }
    val pathStack = remember { mutableStateListOf<String>() }
    var subfolders by remember { mutableStateOf<List<IndexedFolder>?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    // 用于取消上一次未完成的加载
    val jobHolder = remember { arrayOfNulls<kotlinx.coroutines.Job>(1) }

    // 显式加载函数，和 iOS loadSubfolders(path:) 一一对应
    fun loadSubfolders(path: String) {
        jobHolder[0]?.cancel()
        subfolders = null
        loadError = null
        jobHolder[0] = scope.launch {
            try {
                val api = ApiClient.getApiService(server)
                subfolders = api.indexerFolders(parentPath = path, sourceFolder = sourceFolder)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                loadError = e.message ?: e.toString()
                subfolders = emptyList()
            }
        }
    }

    // 进入子文件夹
    fun enterFolder(path: String) {
        pathStack.add(currentPath)
        currentPath = path
        loadSubfolders(path)
    }

    fun goBack() {
        if (pathStack.isNotEmpty()) {
            val prev = pathStack.removeLast()
            currentPath = prev
            loadSubfolders(prev)
        } else {
            onDismiss()
        }
    }

    // 首次进入时加载根层
    LaunchedEffect(Unit) { loadSubfolders(sourceFolder) }

    BackHandler { goBack() }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    navigationIcon = {
                        IconButton(onClick = { goBack() }) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                        }
                    },
                    title = {
                        val name = currentPath.substringAfterLast('/').ifEmpty { currentPath }
                        Text(name, fontWeight = FontWeight.Bold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = EInkWhite,
                        titleContentColor = EInkBlack,
                        navigationIconContentColor = EInkBlack
                    )
                )
                HorizontalDivider(color = EInkLightGray)
            }
        },
        bottomBar = {
            Column {
                HorizontalDivider(color = EInkLightGray)
                Box(modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                    Button(
                        onClick = { onNavigate(currentPath) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = EInkBlack, contentColor = EInkWhite)
                    ) {
                        Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("跳转到此处")
                    }
                }
            }
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {

            // ── 面包屑：pathStack + currentPath ──────────────────────────
            val breadcrumbPaths = pathStack + currentPath
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                breadcrumbPaths.forEachIndexed { idx, path ->
                    val name = path.substringAfterLast('/').ifEmpty { path }
                    val isCurrent = idx == breadcrumbPaths.lastIndex
                    Text(
                        text = name,
                        fontSize = 13.sp,
                        color = if (isCurrent) EInkBlack else EInkGray,
                        fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.Normal,
                        modifier = if (!isCurrent) Modifier.clickable {
                            // 弹回到第 idx 层：截断 pathStack，更新 currentPath
                            val target = breadcrumbPaths[idx]
                            while (pathStack.size > idx) pathStack.removeLast()
                            currentPath = target
                            loadSubfolders(target)
                        } else Modifier
                    )
                    if (idx < breadcrumbPaths.lastIndex) {
                        Text(" › ", fontSize = 13.sp, color = EInkLightGray)
                    }
                }
            }
            HorizontalDivider(color = EInkVeryLightGray)

            // ── 子文件夹内容 ──────────────────────────────────────────────
            // 用本地变量捕获 subfolders 快照，避免 Compose snapshot 竞态：
            // when 判断时非 null，但 items(subfolders!!) 执行时可能已被 loadSubfolders 重置为 null
            val currentSubfolders = subfolders
            when {
                currentSubfolders == null -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = EInkBlack)
                    }
                }
                loadError != null -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            modifier = Modifier.padding(24.dp)
                        ) {
                            Icon(Icons.Default.ErrorOutline, contentDescription = null, modifier = Modifier.size(48.dp), tint = EInkLightGray)
                            Spacer(modifier = Modifier.height(12.dp))
                            Text("加载失败", fontSize = 15.sp, color = EInkBlack, fontWeight = FontWeight.Medium)
                            Spacer(modifier = Modifier.height(6.dp))
                            Text(loadError!!, fontSize = 12.sp, color = EInkGray)
                            Spacer(modifier = Modifier.height(16.dp))
                            OutlinedButton(onClick = { loadSubfolders(currentPath) }) { Text("重试") }
                        }
                    }
                }
                currentSubfolders.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(Icons.Default.FolderOff, contentDescription = null, modifier = Modifier.size(48.dp), tint = EInkLightGray)
                            Spacer(modifier = Modifier.height(12.dp))
                            Text("没有子文件夹", color = EInkGray, fontSize = 14.sp)
                            Spacer(modifier = Modifier.height(4.dp))
                            Text("可点击下方按钮跳转到此处", color = EInkLightGray, fontSize = 12.sp)
                        }
                    }
                }
                else -> {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(currentSubfolders) { folder ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { enterFolder(folder.path) }
                                    .padding(horizontal = 16.dp, vertical = 14.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(Icons.Default.Folder, contentDescription = null, modifier = Modifier.size(24.dp), tint = EInkDarkGray)
                                Spacer(modifier = Modifier.width(14.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(folder.name, fontSize = 15.sp, color = EInkBlack, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(folder.contentDescription, fontSize = 12.sp, color = EInkLightGray)
                                }
                                Icon(Icons.Default.ChevronRight, contentDescription = null, tint = EInkLightGray, modifier = Modifier.size(18.dp))
                            }
                            HorizontalDivider(color = EInkVeryLightGray)
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 网格视图
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun GridContentView(
    server: Server,
    cache: ThumbnailCache,
    okHttpClient: okhttp3.OkHttpClient,
    currentSourceFolder: String,
    files: List<IndexedFile>,
    hasMore: Boolean,
    isLoadingMore: Boolean,
    onFileClick: (IndexedFile) -> Unit,
    onLoadMore: () -> Unit
) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 150.dp),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        items(files, span = { GridItemSpan(1) }, key = { it.uuid }) { file ->
            FileGridItem(
                server = server,
                cache = cache,
                okHttpClient = okHttpClient,
                file = file,
                sourceFolder = currentSourceFolder,
                onClick = { onFileClick(file) }
            )
        }
        if (hasMore || isLoadingMore) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                LoadMoreTrigger(isLoading = isLoadingMore, onLoadMore = onLoadMore)
            }
        }
    }
}

@Composable
private fun FolderGridItem(folder: IndexedFolder, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, EInkVeryLightGray, MaterialTheme.shapes.small)
            .clickable(onClick = onClick)
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(Icons.Default.Folder, contentDescription = null, modifier = Modifier.size(40.dp), tint = EInkDarkGray)
        Spacer(modifier = Modifier.height(6.dp))
        Text(folder.name, fontSize = 13.sp, color = EInkBlack, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(folder.contentDescription, fontSize = 11.sp, color = EInkLightGray, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun FileGridItem(
    server: Server,
    cache: ThumbnailCache,
    okHttpClient: okhttp3.OkHttpClient,
    file: IndexedFile,
    sourceFolder: String,
    onClick: () -> Unit
) {
    var bitmap by remember(file.uuid) { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(file.uuid) {
        if (file.isPreviewable) {
            bitmap = cache.load(
                uuid = file.uuid,
                serverUrl = server.activeUrl,
                sfPath = sourceFolder,
                apiKey = server.apiKey,
                size = 300,
                client = okHttpClient
            )
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, EInkVeryLightGray, MaterialTheme.shapes.small)
            .clickable(onClick = onClick)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f),
            contentAlignment = Alignment.Center
        ) {
            val bmp = bitmap
            if (bmp != null) {
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = file.fileName,
                    modifier = Modifier.fillMaxSize().clip(MaterialTheme.shapes.small),
                    contentScale = ContentScale.Crop
                )
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(fileTypeIcon(file), contentDescription = null, modifier = Modifier.size(36.dp), tint = EInkLightGray)
                    Text(file.extensionLabel, fontSize = 11.sp, color = EInkLightGray, fontWeight = FontWeight.Bold)
                }
            }
            if (file.isVideo) {
                file.formattedDuration()?.let { dur ->
                    Box(modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp)) {
                        Surface(color = EInkBlack.copy(alpha = 0.7f), shape = MaterialTheme.shapes.extraSmall) {
                            Text(dur, fontSize = 10.sp, color = EInkWhite, modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp))
                        }
                    }
                }
            }
        }
        Text(
            file.fileName,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 4.dp),
            fontSize = 11.sp, color = EInkBlack, maxLines = 1, overflow = TextOverflow.Ellipsis
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 列表视图
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun ListContentView(
    server: Server,
    cache: ThumbnailCache,
    okHttpClient: okhttp3.OkHttpClient,
    currentSourceFolder: String,
    files: List<IndexedFile>,
    hasMore: Boolean,
    isLoadingMore: Boolean,
    onFileClick: (IndexedFile) -> Unit,
    onLoadMore: () -> Unit
) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(files, key = { it.uuid }) { file ->
            FileListItem(
                server = server, cache = cache, okHttpClient = okHttpClient,
                file = file, sourceFolder = currentSourceFolder,
                onClick = { onFileClick(file) }
            )
            HorizontalDivider(color = EInkVeryLightGray)
        }
        if (hasMore || isLoadingMore) {
            item { LoadMoreTrigger(isLoading = isLoadingMore, onLoadMore = onLoadMore) }
        }
    }
}

@Composable
private fun FolderListItem(folder: IndexedFolder, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.Folder, contentDescription = null, modifier = Modifier.size(28.dp), tint = EInkDarkGray)
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(folder.name, fontSize = 15.sp, color = EInkBlack)
            Text(folder.contentDescription, fontSize = 12.sp, color = EInkLightGray)
        }
        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = EInkLightGray, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun FileListItem(
    server: Server,
    cache: ThumbnailCache,
    okHttpClient: okhttp3.OkHttpClient,
    file: IndexedFile,
    sourceFolder: String,
    onClick: () -> Unit
) {
    var bitmap by remember(file.uuid) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(file.uuid) {
        if (file.isPreviewable) {
            bitmap = cache.load(
                uuid = file.uuid, serverUrl = server.activeUrl, sfPath = sourceFolder,
                apiKey = server.apiKey, size = 100, client = okHttpClient
            )
        }
    }

    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(modifier = Modifier.size(52.dp).border(1.dp, EInkVeryLightGray, MaterialTheme.shapes.extraSmall), contentAlignment = Alignment.Center) {
            val bmp = bitmap
            if (bmp != null) {
                Image(bitmap = bmp.asImageBitmap(), contentDescription = null, modifier = Modifier.fillMaxSize().clip(MaterialTheme.shapes.extraSmall), contentScale = ContentScale.Crop)
            } else {
                Icon(fileTypeIcon(file), contentDescription = null, modifier = Modifier.size(28.dp), tint = EInkLightGray)
            }
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(file.fileName, fontSize = 14.sp, color = EInkBlack, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row {
                Text(file.extensionLabel, fontSize = 11.sp, color = EInkGray)
                Text(" · ", fontSize = 11.sp, color = EInkLightGray)
                Text(file.formattedSize(), fontSize = 11.sp, color = EInkGray)
                file.formattedDuration()?.let { Text(" · $it", fontSize = 11.sp, color = EInkGray) }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 公用小组件
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun SectionLabel(text: String, modifier: Modifier = Modifier.padding(start = 4.dp, top = 8.dp, bottom = 4.dp)) {
    Text(text, modifier = modifier, fontSize = 13.sp, color = EInkGray, fontWeight = FontWeight.Medium)
}

@Composable
private fun LoadMoreTrigger(isLoading: Boolean, onLoadMore: () -> Unit) {
    Box(modifier = Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
        if (isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp, color = EInkGray)
        } else {
            LaunchedEffect(Unit) { onLoadMore() }
        }
    }
}

@Composable
private fun ErrorView(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier = modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Default.ErrorOutline, contentDescription = null, modifier = Modifier.size(48.dp), tint = EInkLightGray)
        Spacer(modifier = Modifier.height(12.dp))
        Text(message, color = EInkGray, fontSize = 14.sp)
        Spacer(modifier = Modifier.height(12.dp))
        OutlinedButton(onClick = onRetry) { Text("重试") }
    }
}

private fun fileTypeIcon(file: IndexedFile) = when {
    file.isAudio -> Icons.Default.AudioFile
    file.isPdf -> Icons.Default.PictureAsPdf
    else -> Icons.Default.InsertDriveFile
}

private fun currentFolderTitle(uiState: GalleryViewModel.UiState): String {
    if (uiState.currentPath.isEmpty()) return "图库"
    val last = uiState.breadcrumb.lastOrNull()?.name
    return last ?: uiState.currentPath.substringAfterLast('/').ifEmpty { uiState.currentPath }
}
