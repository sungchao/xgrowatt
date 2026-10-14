package com.example.xgrowatt.ui.components

import androidx.compose.animation.core.withInfiniteAnimationFrameMillis
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.example.xgrowatt.data.WeatherInfo
import kotlin.math.cos
import kotlin.math.sin

data class AtmosPalette(
    val top: Color,
    val middle: Color,
    val bottom: Color,
    val orb: Color,
    val horizon: Color
)

fun getAtmosphericPalette(isDay: Boolean, temp: Double, isOvercast: Boolean): AtmosPalette {
    if (isOvercast) {
        return if (isDay) {
            AtmosPalette(
                top = Color(0xFF4A5568),
                middle = Color(0xFF718096),
                bottom = Color(0xFF94A3B8),
                orb = Color(0xFFCBD5E0),
                horizon = Color(0xFFCBD5E0)
            )
        } else {
            AtmosPalette(
                top = Color(0xFF090D1A),
                middle = Color(0xFF111827),
                bottom = Color(0xFF1F2937),
                orb = Color(0xFF374151),
                horizon = Color(0xFF1F2937)
            )
        }
    }

    return if (!isDay) {
        if (temp < 10.0) {
            AtmosPalette(
                top = Color(0xFF030712),
                middle = Color(0xFF0B1530),
                bottom = Color(0xFF1E293B),
                orb = Color(0xFF38BDF8),
                horizon = Color(0xFF0284C7)
            )
        } else if (temp < 22.0) {
            AtmosPalette(
                top = Color(0xFF090514),
                middle = Color(0xFF1E112C),
                bottom = Color(0xFF3B0764),
                orb = Color(0xFFC084FC),
                horizon = Color(0xFF818CF8)
            )
        } else {
            AtmosPalette(
                top = Color(0xFF0B0410),
                middle = Color(0xFF2E0835),
                bottom = Color(0xFF701A75),
                orb = Color(0xFFF472B6),
                horizon = Color(0xFFD946EF)
            )
        }
    } else {
        if (temp < 12.0) {
            AtmosPalette(
                top = Color(0xFF075985),
                middle = Color(0xFF0284C7),
                bottom = Color(0xFF38BDF8),
                orb = Color(0xFFE0F2FE),
                horizon = Color(0xFF7DD3FC)
            )
        } else if (temp < 22.0) {
            AtmosPalette(
                top = Color(0xFF1E3A8A),
                middle = Color(0xFF3B82F6),
                bottom = Color(0xFF93C5FD),
                orb = Color(0xFFEFF6FF),
                horizon = Color(0xFFBFDBFE)
            )
        } else if (temp < 32.0) {
            AtmosPalette(
                top = Color(0xFF7C2D12),
                middle = Color(0xFFEA580C),
                bottom = Color(0xFFFDBA74),
                orb = Color(0xFFFEF3C7),
                horizon = Color(0xFFFF9E40)
            )
        } else {
            AtmosPalette(
                top = Color(0xFF7F1D1D),
                middle = Color(0xFFDC2626),
                bottom = Color(0xFFFCA5A5),
                orb = Color(0xFFFEE2E2),
                horizon = Color(0xFFF87171)
            )
        }
    }
}

data class Star(
    val x: Float,
    val y: Float,
    val size: Float,
    val phase: Float
)

data class SolarEnergyNode(
    val initialAngle: Float,
    val speedFactor: Float,
    val size: Float,
    val spawnTimeDelay: Float
)

data class ShootingStar(
    val startX: Float,
    val startY: Float,
    val angle: Float,
    val speed: Float,
    val triggerIntervalSeconds: Float,
    val length: Float
)

@Composable
fun AtmosphericBackground(weather: WeatherInfo, isDay: Boolean) {
    val temp = weather.temperature ?: 18.0
    val clearIcons = listOf("sunny", "clear", "clear_night", "cloudy_night", "partly_cloudy")
    val isOvercast = !clearIcons.contains(weather.icon) && weather.isRealData
    val palette = remember(isDay, temp, isOvercast) {
        getAtmosphericPalette(isDay, temp, isOvercast)
    }

    // Unified animation clock
    val frameTime by produceState(initialValue = 0L) {
        while (true) {
            withInfiniteAnimationFrameMillis {
                value = it
            }
        }
    }
    val nowSeconds = frameTime / 1000f

    // 1. Stars for night
    val stars = remember {
        (0..35).map {
            Star(
                x = Math.random().toFloat(),
                y = (Math.random() * 0.45).toFloat(),
                size = (0.7f + Math.random() * 1.6f).toFloat(),
                phase = (Math.random() * Math.PI * 2).toFloat()
            )
        }
    }

    // 2. Solar Energy Flow Nodes (only day & sunny/partly cloudy)
    val energyNodes = remember {
        (0..18).map {
            SolarEnergyNode(
                initialAngle = (Math.random() * Math.PI * 2).toFloat(),
                speedFactor = (0.6f + Math.random() * 0.8f).toFloat(),
                size = (2f + Math.random() * 3f).toFloat(),
                spawnTimeDelay = (Math.random() * 5.0).toFloat()
            )
        }
    }

    // 3. Shooting Stars (Meteors) for clear nights
    val meteors = remember {
        listOf(
            ShootingStar(startX = 0.2f, startY = 0.05f, angle = 35f, speed = 400f, triggerIntervalSeconds = 9f, length = 120f),
            ShootingStar(startX = 0.6f, startY = 0.02f, angle = 40f, speed = 550f, triggerIntervalSeconds = 14f, length = 150f)
        )
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // Layer 1: Sky Base, Stars, Shooting Stars & Cosmic/Atmospheric Flow Ribbons
        Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height

            // 3-color linear gradient
            drawRect(
                brush = Brush.verticalGradient(
                    0.0f to palette.top,
                    0.45f to palette.middle,
                    1.0f to palette.bottom,
                    startY = 0f,
                    endY = h
                ),
                size = size
            )

            // A. Stars
            if (!isDay) {
                stars.forEach { star ->
                    val twinkle = 0.2f + 0.8f * (sin(nowSeconds * 2.2f + star.phase) * 0.5f + 0.5f)
                    drawCircle(
                        color = Color.White.copy(alpha = twinkle * 0.75f),
                        radius = star.size.dp.toPx(),
                        center = Offset(star.x * w, star.y * h)
                    )
                }

                // B. Shooting Stars (Meteors)
                if (!isOvercast) {
                    meteors.forEach { meteor ->
                        val cycleTime = nowSeconds.mod(meteor.triggerIntervalSeconds)
                        // Active duration is 0.8 seconds
                        if (cycleTime < 0.8f) {
                            val progress = cycleTime / 0.8f
                            val distance = progress * meteor.speed
                            val angleRad = Math.toRadians(meteor.angle.toDouble())
                            val currentX = (meteor.startX * w) + (cos(angleRad) * distance).toFloat()
                            val currentY = (meteor.startY * h) + (sin(angleRad) * distance).toFloat()

                            // Draw meteor tail line
                            val tailEndX = currentX - (cos(angleRad) * meteor.length * (1f - progress)).toFloat()
                            val tailEndY = currentY - (sin(angleRad) * meteor.length * (1f - progress)).toFloat()

                            drawLine(
                                brush = Brush.linearGradient(
                                    colors = listOf(Color.White, Color.White.copy(alpha = 0f)),
                                    start = Offset(currentX, currentY),
                                    end = Offset(tailEndX, tailEndY)
                                ),
                                start = Offset(currentX, currentY),
                                end = Offset(tailEndX, tailEndY),
                                strokeWidth = 1.8.dp.toPx()
                            )
                        }
                    }
                }
            }

            // C. Volumetric Flow Ribbons (Swaying Wind / Aurora Borealis)
            val ribbonCount = if (isDay) 1 else 2
            val ribbonColor = if (isDay) {
                // Soft golden/white wind trails
                Color(0xFFFEF3C7).copy(alpha = 0.05f)
            } else {
                // Ethereal green/violet Aurora Borealis
                if (temp < 15.0) Color(0xFF34D399).copy(alpha = 0.08f) else Color(0xFFA855F7).copy(alpha = 0.08f)
            }

            for (r in 0 until ribbonCount) {
                val offsetPhase = r * 3.5f
                val flowPath = Path().apply {
                    val startY = h * (0.35f + r * 0.12f) + sin(nowSeconds * 0.4f + offsetPhase) * 40f
                    moveTo(0f, startY)
                    cubicTo(
                        w * 0.3f, startY - 80f * sin(nowSeconds * 0.6f + offsetPhase),
                        w * 0.7f, startY + 80f * cos(nowSeconds * 0.5f + offsetPhase),
                        w, startY + 20f * sin(nowSeconds * 0.4f + offsetPhase)
                    )
                }
                drawPath(
                    path = flowPath,
                    color = ribbonColor,
                    style = Stroke(width = (24f + r * 12f).dp.toPx())
                )
            }

            // D. Pulsing Sun/Moon Light Glow
            val orbPulse = 1f + 0.05f * sin(nowSeconds * 0.8f)
            val orbCenter = Offset(
                w * (if (isDay) 0.78f else 0.22f) + sin(nowSeconds * 0.2f) * 8f,
                h * 0.15f + cos(nowSeconds * 0.2f) * 6f
            )
            val orbRadius = h * 0.46f * orbPulse
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(palette.orb.copy(alpha = 0.45f), Color.Transparent),
                    center = orbCenter,
                    radius = orbRadius
                ),
                center = orbCenter,
                radius = orbRadius
            )

            // E. Warmth / Mist Horizon Glow
            val horizonPulse = 1f + 0.03f * cos(nowSeconds * 1.2f)
            val horizonCenter = Offset(w * 0.5f, h * 1.05f)
            val horizonRadius = h * 0.38f * horizonPulse
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(palette.horizon.copy(alpha = 0.35f), Color.Transparent),
                    center = horizonCenter,
                    radius = horizonRadius
                ),
                center = horizonCenter,
                radius = horizonRadius
            )
        }

        // Layer 2: Sun/Moon Core, Volumetric Cloud Wisps & Day Solar Energy Flow Loops
        val isPartlyCloudy = weather.icon == "partly_cloudy" || weather.icon == "cloudy_night"
        if (!isOvercast && weather.isRealData) {
            if (isDay) {
                SunVisual(nowSeconds = nowSeconds, isPartlyCloudy = isPartlyCloudy)

                // Render Solar Energy Flow Particles flowing out from Sun down to earth
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val w = size.width
                    val h = size.height
                    val sunCenter = Offset(w * 0.78f, h * 0.15f)

                    energyNodes.forEach { node ->
                        // Loop timeline for each particle
                        val lifetime = 4.5f
                        val age = (nowSeconds - node.spawnTimeDelay).mod(lifetime)
                        val progress = age / lifetime

                        // Parabolic vector path from sun down towards bottom-left screen
                        val startRad = w * 0.07f
                        val maxDistance = h * 1.1f
                        val distance = startRad + progress * maxDistance

                        // Spiral angular drift
                        val currentAngle = node.initialAngle + progress * 1.2f * node.speedFactor
                        val px = sunCenter.x + cos(currentAngle) * distance
                        val py = sunCenter.y + sin(currentAngle) * distance

                        if (px in 0f..w && py in 0f..h) {
                            // Fading transparency as it approaches the earth
                            val alpha = sin(progress * Math.PI.toFloat()) * 0.55f
                            drawCircle(
                                color = Color(0xFFFBBF24).copy(alpha = alpha), // Amber glow
                                radius = node.size.dp.toPx() * (1f - progress * 0.4f),
                                center = Offset(px, py)
                            )
                            // Soft glow tail
                            drawCircle(
                                color = Color(0xFFFEF3C7).copy(alpha = alpha * 0.3f),
                                radius = node.size.dp.toPx() * 2.2f,
                                center = Offset(px, py)
                            )
                        }
                    }
                }
            } else {
                MoonVisual(nowSeconds = nowSeconds, isPartlyCloudy = isPartlyCloudy)
            }
        }

        // Layer 3: Rain View Particle Animation
        val rainIcons = listOf("drizzle", "rainy", "stormy", "rainy_night", "stormy_night")
        val isRainy = rainIcons.contains(weather.icon)
        if (isRainy) {
            RainView(nowSeconds = nowSeconds)
        }
    }
}

@Composable
fun SunVisual(nowSeconds: Float, isPartlyCloudy: Boolean) {
    Canvas(modifier = Modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height
        val sunCenter = Offset(w * 0.78f, h * 0.15f)

        // A. Pulsating Sun Corona
        val coronaPulse = 1f + 0.08f * sin(nowSeconds * 2.5f)
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(Color(0xFFFEF3C7).copy(alpha = 0.35f), Color(0xFFF59E0B).copy(alpha = 0.05f), Color.Transparent),
                center = sunCenter,
                radius = w * 0.22f * coronaPulse
            ),
            radius = w * 0.22f * coronaPulse,
            center = sunCenter
        )

        // B. Cinematic Lens Flare (diagonal light rings from sun towards screen bottom-left)
        // 4 lens flare elements mapped along a diagonal line from sunCenter (0.78w, 0.15h) to (0.1w, 0.85h)
        val flareTarget = Offset(w * 0.15f, h * 0.8f)
        val flareVector = flareTarget - sunCenter
        val flares = listOf(
            0.18f to (w * 0.11f) to Color(0xFFFBBF24).copy(alpha = 0.04f), // amber ring
            0.38f to (w * 0.06f) to Color(0xFF38BDF8).copy(alpha = 0.03f), // cyan flare
            0.62f to (w * 0.18f) to Color(0xFFF472B6).copy(alpha = 0.02f), // pink dispersion ring
            0.82f to (w * 0.08f) to Color(0xFF34D399).copy(alpha = 0.03f)  // green flare
        )
        flares.forEach { (spec, color) ->
            val (ratio, radius) = spec
            val flareCenter = sunCenter + flareVector * ratio
            drawCircle(
                color = color,
                radius = radius,
                center = flareCenter
            )
        }

        // C. Sun Inner Intense Glow
        drawCircle(
            color = Color(0xFFFFD15C).copy(alpha = 0.25f),
            radius = w * 0.11f,
            center = sunCenter
        )

        // D. Sun Solid Core
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(Color.White, Color(0xFFF59E0B)),
                center = sunCenter,
                radius = w * 0.062f
            ),
            radius = w * 0.062f,
            center = sunCenter
        )

        // E. Drifting Volumetric Cloud Overlay (Partly Cloudy)
        if (isPartlyCloudy) {
            val driftOffset = (nowSeconds * 12f).mod(w + w * 0.6f) - w * 0.3f
            val cloudColor = Color.White.copy(alpha = 0.35f)
            val cloudCenter = Offset(sunCenter.x - w * 0.05f + driftOffset * 0.2f, sunCenter.y + w * 0.05f)

            drawCircle(
                color = cloudColor,
                radius = w * 0.048f,
                center = Offset(cloudCenter.x - w * 0.04f, cloudCenter.y)
            )
            drawCircle(
                color = cloudColor,
                radius = w * 0.068f,
                center = Offset(cloudCenter.x, cloudCenter.y - w * 0.02f)
            )
            drawCircle(
                color = cloudColor,
                radius = w * 0.048f,
                center = Offset(cloudCenter.x + w * 0.04f, cloudCenter.y)
            )
        }
    }
}

@Composable
fun MoonVisual(nowSeconds: Float, isPartlyCloudy: Boolean) {
    Canvas(modifier = Modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height
        val moonCenter = Offset(w * 0.22f, h * 0.15f)

        // Soft Moon Glow
        val glowPulse = 1f + 0.04f * sin(nowSeconds * 1.5f)
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(Color(0xFFE0F2FE).copy(alpha = 0.25f), Color.Transparent),
                center = moonCenter,
                radius = w * 0.16f * glowPulse
            ),
            radius = w * 0.16f * glowPulse,
            center = moonCenter
        )

        // Crescent Moon Path
        val r = w * 0.038f
        val moonPath = Path().apply {
            moveTo(moonCenter.x, moonCenter.y - r)
            cubicTo(
                moonCenter.x + r * 1.35f, moonCenter.y - r * 0.8f,
                moonCenter.x + r * 1.35f, moonCenter.y + r * 0.8f,
                moonCenter.x, moonCenter.y + r
            )
            cubicTo(
                moonCenter.x + r * 0.55f, moonCenter.y + r * 0.6f,
                moonCenter.x + r * 0.55f, moonCenter.y - r * 0.6f,
                moonCenter.x, moonCenter.y - r
            )
            close()
        }
        drawPath(
            path = moonPath,
            color = Color(0xFFF1F5F9).copy(alpha = 0.82f)
        )

        // Drifting Volumetric Cloud Overlay (Partly Cloudy)
        if (isPartlyCloudy) {
            val driftOffset = (nowSeconds * 8f).mod(w + w * 0.5f) - w * 0.25f
            val cloudColor = Color.White.copy(alpha = 0.3f)
            val cloudCenter = Offset(moonCenter.x + w * 0.02f + driftOffset * 0.15f, moonCenter.y + w * 0.03f)

            drawCircle(
                color = cloudColor,
                radius = w * 0.042f,
                center = Offset(cloudCenter.x - w * 0.03f, cloudCenter.y)
            )
            drawCircle(
                color = cloudColor,
                radius = w * 0.055f,
                center = Offset(cloudCenter.x, cloudCenter.y - w * 0.015f)
            )
            drawCircle(
                color = cloudColor,
                radius = w * 0.042f,
                center = Offset(cloudCenter.x + w * 0.03f, cloudCenter.y)
            )
        }
    }
}

@Composable
fun RainView(nowSeconds: Float) {
    val drops = remember {
        (0..75).map {
            RainDrop(
                x = Math.random().toFloat(),
                y = (Math.random() * 1.4 - 0.2).toFloat(),
                length = (14 + Math.random() * 18).toFloat(),
                speed = (35 + Math.random() * 22).toFloat(),
                opacity = (0.16 + Math.random() * 0.32).toFloat()
            )
        }
    }

    Canvas(modifier = Modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height

        drops.forEach { drop ->
            val elapsed = nowSeconds * drop.speed
            val currentY = ((drop.y * h + elapsed).mod(h + 60f)) - 30f
            val currentX = ((drop.x * w + elapsed * 0.12f).mod(w))

            drawLine(
                color = Color.White.copy(alpha = drop.opacity),
                start = Offset(currentX, currentY),
                end = Offset(currentX + 1.8f, currentY + drop.length),
                strokeWidth = 1.1.dp.toPx()
            )
        }
    }
}

data class RainDrop(
    val x: Float,
    val y: Float,
    val length: Float,
    val speed: Float,
    val opacity: Float
)
