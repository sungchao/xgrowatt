package com.example.xgrowatt.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val XGrowattDarkColorScheme = darkColorScheme(
    primary = SolarGold,
    onPrimary = Color(0xFF1A1200),
    secondary = BatteryGreen,
    onSecondary = Color(0xFF001C0F),
    tertiary = GridPurple,
    onTertiary = Color(0xFF1A0030),
    background = BgDark,
    onBackground = TextPrimary,
    surface = SurfaceDark,
    onSurface = TextPrimary,
    surfaceVariant = CardBg,
    onSurfaceVariant = TextSecondary,
    error = AlertRed,
    onError = Color.White,
    outline = Color(0xFF3A3A45),
)

@Composable
fun XGrowattTheme(
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = XGrowattDarkColorScheme,
        typography = Typography,
        content = content,
    )
}
