package com.resourcer.eink.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * 电纸书优化主题
 * - 高对比度黑白配色
 * - 无渐变、无阴影
 * - 扁平化设计，减少电子墨水屏刷新压力
 */

// 电纸书主色调：纯黑 + 纯白 + 灰阶
val EInkBlack = Color(0xFF000000)
val EInkDarkGray = Color(0xFF333333)
val EInkGray = Color(0xFF666666)
val EInkLightGray = Color(0xFFCCCCCC)
val EInkVeryLightGray = Color(0xFFF0F0F0)
val EInkWhite = Color(0xFFFFFFFF)
val EInkAccent = Color(0xFF1A1A1A) // 深黑作为强调色

private val EInkColorScheme = lightColorScheme(
    primary = EInkBlack,
    onPrimary = EInkWhite,
    primaryContainer = EInkDarkGray,
    onPrimaryContainer = EInkWhite,
    secondary = EInkGray,
    onSecondary = EInkWhite,
    secondaryContainer = EInkLightGray,
    onSecondaryContainer = EInkBlack,
    tertiary = EInkGray,
    background = EInkWhite,
    onBackground = EInkBlack,
    surface = EInkWhite,
    onSurface = EInkBlack,
    surfaceVariant = EInkVeryLightGray,
    onSurfaceVariant = EInkDarkGray,
    outline = EInkLightGray,
    outlineVariant = Color(0xFFE0E0E0),
    error = Color(0xFFCC0000),
    onError = EInkWhite
)

@Composable
fun EInkTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = EInkColorScheme,
        content = content
    )
}
