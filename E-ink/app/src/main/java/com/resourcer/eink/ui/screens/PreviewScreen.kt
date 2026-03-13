package com.resourcer.eink.ui.screens

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.zIndex
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.resourcer.eink.data.model.IndexedFile
import com.resourcer.eink.data.model.Server
import com.resourcer.eink.ui.theme.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 文件预览界面（电纸书优化版）
 * - 图片/视频统一：全屏画面 + 左右翻页按钮 + 顶/底控制栏 overlay
 * - 视频底部额外有小步进按钮（-30s / -5s / +5s / +30s）+ 提取帧按钮
 * - 无任何动画，无滑动手势
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PreviewScreen(
    server: Server,
    files: List<IndexedFile>,
    initialIndex: Int,
    onBack: () -> Unit
) {
    var currentIndex by remember { mutableIntStateOf(initialIndex.coerceIn(0, files.lastIndex)) }
    var showControls by remember { mutableStateOf(true) }
    val currentFile = files.getOrNull(currentIndex) ?: return

    Box(modifier = Modifier.fillMaxSize().background(EInkWhite)) {

        // ── 文件内容区（全屏，统一布局）──────────────────────────────────
        FilePage(
            server = server,
            file = currentFile,
            showControls = showControls,
            onToggleControls = { showControls = !showControls }
        )

        // ── 翻页按钮覆盖层（zIndex 明确置于 FilePage 之上，随 showControls 显隐）
        if (showControls) Box(
            modifier = Modifier
                .fillMaxSize()
                .zIndex(1f),
            contentAlignment = Alignment.Center
        ) {
            if (currentIndex > 0) {
                IconButton(
                    onClick = { currentIndex-- },
                    modifier = Modifier
                        .align(Alignment.CenterStart)
                        .padding(start = 4.dp)
                        .size(52.dp)
                ) {
                    Surface(
                        color = EInkWhite,
                        shape = MaterialTheme.shapes.small,
                        border = androidx.compose.foundation.BorderStroke(1.dp, EInkBlack)
                    ) {
                        Icon(
                            Icons.Default.ChevronLeft,
                            contentDescription = "上一个",
                            modifier = Modifier.size(36.dp).padding(4.dp),
                            tint = EInkBlack
                        )
                    }
                }
            }
            if (currentIndex < files.lastIndex) {
                IconButton(
                    onClick = { currentIndex++ },
                    modifier = Modifier
                        .align(Alignment.CenterEnd)
                        .padding(end = 4.dp)
                        .size(52.dp)
                ) {
                    Surface(
                        color = EInkWhite,
                        shape = MaterialTheme.shapes.small,
                        border = androidx.compose.foundation.BorderStroke(1.dp, EInkBlack)
                    ) {
                        Icon(
                            Icons.Default.ChevronRight,
                            contentDescription = "下一个",
                            modifier = Modifier.size(36.dp).padding(4.dp),
                            tint = EInkBlack
                        )
                    }
                }
            }
        }

        // ── 顶部控制栏 ───────────────────────────────────────────────────
        if (showControls) {
            Surface(
                modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter),
                color = EInkWhite,
                tonalElevation = 0.dp
            ) {
                Column {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 4.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                currentFile.fileName,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                color = EInkBlack
                            )
                            Text(
                                "${currentIndex + 1} / ${files.size}",
                                fontSize = 12.sp,
                                color = EInkGray
                            )
                        }
                    }
                    HorizontalDivider(color = EInkVeryLightGray)
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 单文件页（统一全屏布局）
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun FilePage(
    server: Server,
    file: IndexedFile,
    showControls: Boolean,
    onToggleControls: () -> Unit
) {
    when {
        file.isVideo -> VideoFramePage(server, file, showControls, onToggleControls)
        file.isImage || file.isGif -> ImagePage(server, file, onToggleControls)
        else -> OtherFilePage(file, onToggleControls)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 图片页（全屏 + 双指缩放）
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun ImagePage(server: Server, file: IndexedFile, onTap: () -> Unit) {
    val context = LocalContext.current
    val contentUrl = "${server.activeUrl}/api/preview/content/_?uuid=${file.uuid}"
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTransformGestures { _, pan, zoom, _ ->
                    scale = (scale * zoom).coerceIn(0.5f, 6f)
                    offset = if (scale > 1f) offset + pan else Offset.Zero
                }
            }
            .pointerInput(Unit) {
                detectTapGestures(onTap = { onTap() })
            },
        contentAlignment = Alignment.Center
    ) {
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(contentUrl)
                .addHeader("Cookie", "api_key=${server.apiKey}")
                .crossfade(false)
                .build(),
            contentDescription = file.fileName,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer(scaleX = scale, scaleY = scale, translationX = offset.x, translationY = offset.y),
            contentScale = if (scale > 1f) ContentScale.None else ContentScale.Fit
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 视频帧页（全屏画面 + 底部小控制栏 overlay，与图片页统一风格）
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun VideoFramePage(
    server: Server,
    file: IndexedFile,
    showControls: Boolean,
    onTap: () -> Unit
) {
    val context = LocalContext.current
    val contentUrl = "${server.activeUrl}/api/preview/content/_?uuid=${file.uuid}"
    val apiDurationMs = ((file.duration ?: 0.0) * 1000).toLong()

    var durationMs by remember { mutableLongStateOf(apiDurationMs) }
    var isFetchingDuration by remember { mutableStateOf(false) }
    var selectedTimeMs by remember { mutableLongStateOf(0L) }
    var extractedFrame by remember { mutableStateOf<Bitmap?>(null) }
    var isExtracting by remember { mutableStateOf(false) }
    var extractError by remember { mutableStateOf<String?>(null) }

    // API 未返回时长时，后台从视频流读取
    LaunchedEffect(contentUrl) {
        if (durationMs <= 0L) {
            isFetchingDuration = true
            durationMs = withContext(Dispatchers.IO) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(contentUrl, mapOf("Cookie" to "api_key=${server.apiKey}"))
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull() ?: 0L
                } catch (_: Exception) { 0L }
                finally { try { retriever.release() } catch (_: Exception) { } }
            }
            isFetchingDuration = false
        }
    }

    // 执行帧提取
    LaunchedEffect(isExtracting) {
        if (isExtracting) {
            extractedFrame = withContext(Dispatchers.IO) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(contentUrl, mapOf("Cookie" to "api_key=${server.apiKey}"))
                    retriever.getFrameAtTime(selectedTimeMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                } catch (_: Exception) { null }
                finally { try { retriever.release() } catch (_: Exception) { } }
            }
            isExtracting = false
            if (extractedFrame == null) extractError = "帧提取失败，请检查网络连接"
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) { detectTapGestures(onTap = { onTap() }) },
        contentAlignment = Alignment.Center
    ) {
        // ── 全屏帧画面（提取前显示缩略图）────────────────────────────────
        val frame = extractedFrame
        if (frame != null) {
            Image(
                bitmap = frame.asImageBitmap(),
                contentDescription = "视频帧",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Fit
            )
        } else {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data("${server.activeUrl}/api/preview/thumbnail?uuid=${file.uuid}&size=800")
                    .addHeader("Cookie", "api_key=${server.apiKey}")
                    .crossfade(false)
                    .build(),
                contentDescription = file.fileName,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Fit
            )
        }

        // ── 提取中遮罩 ────────────────────────────────────────────────────
        if (isExtracting) {
            Box(
                modifier = Modifier.fillMaxSize().background(EInkWhite.copy(alpha = 0.6f)),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = EInkBlack)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("提取帧中...", fontSize = 14.sp, color = EInkBlack)
                }
            }
        }

        // ── 视频角标（未提取时显示时长标签）─────────────────────────────
        if (extractedFrame == null && !isExtracting && !showControls) {
            Surface(
                modifier = Modifier.align(Alignment.TopStart).padding(12.dp),
                color = EInkBlack.copy(alpha = 0.7f),
                shape = MaterialTheme.shapes.extraSmall
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.VideoFile, contentDescription = null, modifier = Modifier.size(14.dp), tint = EInkWhite)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(file.formattedDuration() ?: "视频", fontSize = 12.sp, color = EInkWhite)
                }
            }
        }

        // ── 底部帧控制栏（showControls 时显示，与顶栏风格一致）──────────
        if (showControls) {
            Surface(
                modifier = Modifier.fillMaxWidth().align(Alignment.BottomCenter),
                color = EInkWhite,
                tonalElevation = 0.dp
            ) {
                Column {
                    HorizontalDivider(color = EInkVeryLightGray)
                    Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {

                        // 步进按钮行 + 时间显示（已知时长时）
                        when {
                            isFetchingDuration -> {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.Center
                                ) {
                                    CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp, color = EInkGray)
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text("读取视频信息...", fontSize = 12.sp, color = EInkGray)
                                }
                                Spacer(modifier = Modifier.height(6.dp))
                            }
                            durationMs > 0 -> {
                                // 步进按钮：-30s | -5s | 当前时间/总时长 | +5s | +30s
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    listOf(-30_000L to "-30s", -5_000L to "-5s").forEach { (delta, label) ->
                                        OutlinedButton(
                                            onClick = {
                                                selectedTimeMs = (selectedTimeMs + delta).coerceIn(0L, durationMs)
                                            },
                                            modifier = Modifier.weight(1f).height(34.dp),
                                            contentPadding = PaddingValues(0.dp)
                                        ) { Text(label, fontSize = 12.sp) }
                                    }
                                    Text(
                                        "${formatTime(selectedTimeMs)} / ${formatTime(durationMs)}",
                                        modifier = Modifier.weight(2f),
                                        fontSize = 12.sp,
                                        color = EInkBlack,
                                        fontWeight = FontWeight.Medium,
                                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                                    )
                                    listOf(5_000L to "+5s", 30_000L to "+30s").forEach { (delta, label) ->
                                        OutlinedButton(
                                            onClick = {
                                                selectedTimeMs = (selectedTimeMs + delta).coerceIn(0L, durationMs)
                                            },
                                            modifier = Modifier.weight(1f).height(34.dp),
                                            contentPadding = PaddingValues(0.dp)
                                        ) { Text(label, fontSize = 12.sp) }
                                    }
                                }
                                Spacer(modifier = Modifier.height(6.dp))
                            }
                            else -> {
                                // 时长未知，仍可提取第一帧
                            }
                        }

                        // 提取帧按钮
                        if (!isFetchingDuration) {
                            Button(
                                onClick = { if (!isExtracting) { isExtracting = true; extractError = null } },
                                modifier = Modifier.fillMaxWidth().height(36.dp),
                                enabled = !isExtracting,
                                colors = ButtonDefaults.buttonColors(containerColor = EInkBlack, contentColor = EInkWhite),
                                contentPadding = PaddingValues(0.dp)
                            ) {
                                Icon(Icons.Default.Image, contentDescription = null, modifier = Modifier.size(15.dp))
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(
                                    if (durationMs > 0) "提取此帧（${formatTime(selectedTimeMs)}）" else "提取第一帧",
                                    fontSize = 13.sp
                                )
                            }
                        }

                        // 错误提示
                        extractError?.let {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 其他文件
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun OtherFilePage(file: IndexedFile, onTap: () -> Unit) {
    Box(
        modifier = Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures(onTap = { onTap() }) },
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
            Icon(
                when { file.isAudio -> Icons.Default.AudioFile; file.isPdf -> Icons.Default.PictureAsPdf; else -> Icons.Default.InsertDriveFile },
                contentDescription = null, modifier = Modifier.size(80.dp), tint = EInkLightGray
            )
            Spacer(modifier = Modifier.height(20.dp))
            Text(file.fileName, fontSize = 18.sp, fontWeight = FontWeight.Medium, color = EInkBlack)
            Spacer(modifier = Modifier.height(8.dp))
            Text(file.extensionLabel, fontSize = 14.sp, color = EInkGray)
            Text(file.formattedSize(), fontSize = 14.sp, color = EInkGray)
            Spacer(modifier = Modifier.height(16.dp))
            Surface(color = EInkVeryLightGray, shape = MaterialTheme.shapes.small) {
                Text("此文件类型不支持预览", modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp), fontSize = 13.sp, color = EInkGray)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 工具
// ─────────────────────────────────────────────────────────────────────────────

private fun formatTime(ms: Long): String {
    val totalSec = ms / 1000
    return String.format("%d:%02d", totalSec / 60, totalSec % 60)
}
