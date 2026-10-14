package com.example.xgrowatt.ui.dashboard

import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.animation.core.LinearEasing

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.keyframes
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.BorderStroke
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BatteryFull
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Surface
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.BatteryAlert
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.FlashOn
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.WbCloudy
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Grain
import androidx.compose.material.icons.filled.Thunderstorm
import androidx.compose.material.icons.filled.AcUnit
import com.example.xgrowatt.data.WeatherManager
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.MapStyleOptions
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapType
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import com.example.xgrowatt.ui.components.MascotDialog
import kotlin.math.sin
import kotlin.math.cos
import com.example.xgrowatt.data.FirebaseManager
import com.example.xgrowatt.data.ForecastHour
import com.example.xgrowatt.data.TodayStatsCalculator
import com.example.xgrowatt.theme.AlertRed
import com.example.xgrowatt.theme.BatteryGreen
import com.example.xgrowatt.theme.BgDark
import com.example.xgrowatt.theme.CardBg
import com.example.xgrowatt.theme.GridPurple
import com.example.xgrowatt.theme.LoadBlue
import com.example.xgrowatt.theme.SolarGold
import com.example.xgrowatt.theme.TextSecondary
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen() {
    val liveStatus by FirebaseManager.liveStatus.collectAsState()
    val status by FirebaseManager.status.collectAsState()
    val chargingPlan by FirebaseManager.chargingPlan.collectAsState()
    val telemetryHistory by FirebaseManager.telemetryHistory.collectAsState()
    val syncLogs by FirebaseManager.syncLogs.collectAsState()
    val forecastHours by FirebaseManager.forecastHours.collectAsState()
    val forecastIssuedAt by FirebaseManager.forecastIssuedAt.collectAsState()
    val settings by FirebaseManager.settings.collectAsState()
    val isSyncing by FirebaseManager.isSyncing.collectAsState()
    val dailyBills by FirebaseManager.dailyBills.collectAsState()
    val historicalBills by FirebaseManager.historicalBills.collectAsState()
    val priorityMode by FirebaseManager.inverterPriorityMode.collectAsState()
    val targetSoc by FirebaseManager.inverterTargetSoc.collectAsState()
    val powerRate by FirebaseManager.inverterPowerRate.collectAsState()

    var showMascotDialog by remember { mutableStateOf(false) }

    val weatherState by WeatherManager.weather.collectAsState()
    val isDayState by WeatherManager.isDay.collectAsState()


    val tz = settings?.timezone ?: "Australia/Sydney"
    val lat = settings?.latitude
    val lon = settings?.longitude

    androidx.compose.runtime.LaunchedEffect(tz, lat, lon) {
        WeatherManager.fetchIfNeeded(tz, lat, lon)
    }

    val live = liveStatus?.data
    val stats = TodayStatsCalculator.calculate(telemetryHistory)

    val socStr = live?.SOC ?: "—"
    val socVal = socStr.toIntOrNull() ?: 0
    val solarKw = live?.ppv?.toDoubleOrNull() ?: 0.0
    val chargeKw = live?.chargePower?.toDoubleOrNull() ?: 0.0
    val dischargeKw = live?.dischargePower?.toDoubleOrNull() ?: 0.0
    val loadKw = live?.localLoad?.toDoubleOrNull() ?: 0.0
    val gridExportKw = live?.gridExport?.toDoubleOrNull() ?: 0.0
    val gridImportKw = live?.gridImport?.toDoubleOrNull() ?: 0.0

    val pv1Kw = live?.ppv1?.toDoubleOrNull()?.let { it / 1000.0 }
    val pv2Kw = live?.ppv2?.toDoubleOrNull()?.let { it / 1000.0 }
    val vpv1 = live?.vpv1
    val vpv2 = live?.vpv2

    val epv1 = live?.epv1Today?.toDoubleOrNull()
    val epv2 = live?.epv2Today?.toDoubleOrNull()

    val showDriftBanner = status?.inverter_matches == false

    PullToRefreshBox(
        isRefreshing = isSyncing,
        onRefresh = {
            FirebaseManager.triggerGrowattSync(mode = "read") { _, _ -> }
            FirebaseManager.triggerPollTeslaStatus()
        },
        modifier = Modifier.fillMaxSize()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Transparent)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Header with Manual Sync Button
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "XGROWATT AUTO",
                        style = MaterialTheme.typography.labelSmall,
                        color = BatteryGreen,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.5.sp
                    )
                    Text(
                        text = "Dashboard",
                        style = MaterialTheme.typography.titleLarge,
                        color = Color.White,
                    )
                }

                IconButton(
                    onClick = { FirebaseManager.triggerGrowattSync(mode = "read") { _, _ -> } },
                    enabled = !isSyncing
                ) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = "Sync Now",
                        tint = if (isSyncing) TextSecondary else Color.White
                    )
                }
            }

            // Sync alert if inverter drift detected
            if (showDriftBanner) {
                Card(
                    colors = CardDefaults.cardColors(containerColor = AlertRed.copy(alpha = 0.25f)),
                    shape = RoundedCornerShape(16.dp),
                    border = BorderStroke(1.dp, AlertRed.copy(alpha = 0.4f)),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("⚠️", fontSize = 16.sp)
                        Spacer(modifier = Modifier.width(8.dp))
                        Column {
                            Text(
                                "Inverter schedule differs from app settings",
                                style = MaterialTheme.typography.bodyMedium,
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                "Inverter reports: ${status?.inverter_actual ?: "unknown"}. It will be overwritten before the next charge window.",
                                style = MaterialTheme.typography.bodySmall,
                                color = TextSecondary,
                            )
                        }
                    }
                }
            }

            val resolvedPriorityMode = when (live?.priorityChoose) {
                "0" -> "Load First"
                "1" -> "Battery First"
                "2" -> "Grid First"
                else -> priorityMode
            }

            // Hero Element: Animated energy flow
            EnergyFlowCard(
                solarKw = solarKw,
                chargeKw = chargeKw,
                dischargeKw = dischargeKw,
                loadKw = loadKw,
                gridExportKw = gridExportKw,
                gridImportKw = gridImportKw,
                socPct = socVal,
                pv1Kw = pv1Kw,
                pv2Kw = pv2Kw,
                weather = weatherState,
                priorityMode = resolvedPriorityMode,
                targetSoc = targetSoc,
                powerRate = powerRate,
                skin = settings?.mascot_skin ?: "slime",
                live = live,
                teslaStatus = FirebaseManager.teslaStatus.collectAsState().value,
                onMascotClick = { showMascotDialog = true }
            )



            // Today's Efficiency Banner (Self-Sufficiency & Self-Consumption)
            EfficiencyBanner(
                selfSufficiency = stats.selfSufficiency,
                selfConsumption = stats.selfConsumption,
                treesSaved = stats.treesSaved,
                co2Avoided = stats.co2Avoided
            )

            // Real-Time Cockpit & Today's Totals Side-by-Side (QuickStatsGrid)
            QuickStatsGrid(
                pvVal = solarKw,
                pv1Val = pv1Kw,
                pv2Val = pv2Kw,
                vpv1 = vpv1,
                vpv2 = vpv2,
                loadVal = loadKw,
                socVal = socVal,
                chgPower = chargeKw,
                dischPower = dischargeKw,
                gridImpVal = gridImportKw,
                gridExpVal = gridExportKw,
                // Totals
                totalSolar = stats.totalSolarKwh,
                totalLoad = stats.totalLoadKwh,
                totalImport = stats.totalImportKwh,
                totalExport = stats.totalExportKwh,
                totalCharge = stats.totalChargeKwh,
                totalDischarge = stats.totalDischargeKwh,
                epv1 = epv1,
                epv2 = epv2
            )

            // Inputs vs Outputs Energy Balance Card
            EnergyBalanceCard(
                totalInputs = stats.totalInputs,
                totalOutputs = stats.totalOutputs,
                totalSolar = stats.totalSolarKwh,
                totalDischarge = stats.totalDischargeKwh,
                totalImport = stats.totalImportKwh,
                totalLoad = stats.totalLoadKwh,
                totalCharge = stats.totalChargeKwh,
                totalExport = stats.totalExportKwh
            )

            // Tesla EV Live Charging Status Card
            TeslaEvLiveCard()


            // Weather Forecast Card (Next 24H)
            if (forecastHours.isNotEmpty()) {
                WeatherForecastCard(
                    hours = forecastHours,
                    issuedAt = forecastIssuedAt
                )
            }

            // Last Sync Status
            syncLogs.firstOrNull()?.let { log ->
                LastSyncCard(
                    status = log.status,
                    message = log.message,
                    timestamp = log.timestamp?.let {
                        SimpleDateFormat("d MMM HH:mm", Locale.getDefault()).format(it)
                    } ?: "—",
                )
            }

            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

// ---- Node Views ----

@Composable
fun NodeView(
    title: String,
    icon: ImageVector,
    valStr: String,
    color: Color,
    size: Dp = 56.dp,
    modifier: Modifier = Modifier
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = modifier
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(size)
        ) {
            Surface(
                shape = CircleShape,
                color = Color.White.copy(alpha = 0.12f),
                border = BorderStroke(1.5.dp, color.copy(alpha = 0.35f)),
                modifier = Modifier.fillMaxSize()
            ) {}
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(size * 0.45f)
            )
        }
        Text(
            text = title,
            style = MaterialTheme.typography.labelSmall,
            color = TextSecondary,
            fontSize = 8.sp,
            fontWeight = FontWeight.Medium
        )
        if (valStr.isNotEmpty()) {
            Text(
                text = valStr,
                style = MaterialTheme.typography.bodySmall,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 10.sp
            )
        }
    }
}

@Composable
fun BatteryNodeView(
    soc: Int,
    modeledSoc: Double? = null,
    chargeKw: Double,
    dischargeKw: Double,
    color: Color,
    size: Dp = 64.dp,
    modifier: Modifier = Modifier
) {
    val aiSoc = modeledSoc ?: soc.toDouble()
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = modifier
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(size)
        ) {
            Surface(
                shape = CircleShape,
                color = Color.White.copy(alpha = 0.12f),
                modifier = Modifier.fillMaxSize()
            ) {}
            // Outer Concentric Ring: Growatt Hardware BMS SOC (Gray/Lavender)
            Canvas(modifier = Modifier.fillMaxSize().padding(1.5.dp)) {
                drawArc(
                    color = Color(0xFF9CA3AF).copy(alpha = 0.75f),
                    startAngle = -90f,
                    sweepAngle = (soc / 100f) * 360f,
                    useCenter = false,
                    style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round)
                )
            }
            // Inner Concentric Ring: AI Modeled SOC (Cyan Blue #38BDF8)
            Canvas(modifier = Modifier.fillMaxSize().padding(6.dp)) {
                drawArc(
                    color = Color(0xFF38BDF8),
                    startAngle = -90f,
                    sweepAngle = ((aiSoc.coerceIn(0.0, 100.0) / 100.0) * 360.0).toFloat(),
                    useCenter = false,
                    style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round)
                )
            }
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = "🤖${String.format(Locale.US, "%.0f", aiSoc)}%",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color(0xFF38BDF8),
                    fontWeight = FontWeight.Black,
                    fontSize = 8.5.sp
                )
                Text(
                    text = "BMS $soc%",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color(0xFF9CA3AF),
                    fontWeight = FontWeight.Bold,
                    fontSize = 7.5.sp
                )
            }
        }
        Text(
            text = "Battery",
            style = MaterialTheme.typography.labelSmall,
            color = TextSecondary,
            fontSize = 8.sp,
            fontWeight = FontWeight.Medium
        )
        val powerText = when {
            chargeKw > 0.01 -> String.format("+%.2f kW", chargeKw)
            dischargeKw > 0.01 -> String.format("-%.2f kW", dischargeKw)
            else -> "Idle"
        }
        val powerColor = when {
            chargeKw > 0.01 -> color
            dischargeKw > 0.01 -> Color(0xFFF59E0B) // Orange
            else -> TextSecondary
        }
        Text(
            text = powerText,
            style = MaterialTheme.typography.bodySmall,
            color = powerColor,
            fontWeight = FontWeight.Bold,
            fontSize = 10.sp
        )
    }
}

@Composable
fun GridNodeView(
    importKw: Double,
    exportKw: Double,
    color: Color,
    size: Dp = 56.dp,
    modifier: Modifier = Modifier
) {
    val activeColor = when {
        importKw > 0.01 -> Color(0xFFF87171) // Red for importing
        exportKw > 0.01 -> Color(0xFFF59E0B) // Gold/Orange for exporting
        else -> TextSecondary.copy(alpha = 0.6f)
    }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = modifier
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(size)
        ) {
            Surface(
                shape = CircleShape,
                color = Color.White.copy(alpha = 0.12f),
                border = BorderStroke(1.5.dp, activeColor.copy(alpha = if (importKw > 0.01 || exportKw > 0.01) 0.8f else 0.25f)),
                modifier = Modifier.fillMaxSize()
            ) {}
            Icon(
                imageVector = Icons.Default.Bolt,
                contentDescription = null,
                tint = activeColor,
                modifier = Modifier.size(24.dp)
            )
        }
        Text(
            text = "Grid Utility",
            style = MaterialTheme.typography.labelSmall,
            color = TextSecondary,
            fontSize = 8.sp,
            fontWeight = FontWeight.Medium
        )
        val gridText = when {
            importKw > 0.01 -> String.format("Import %.2f kW", importKw)
            exportKw > 0.01 -> String.format("Export %.2f kW", exportKw)
            else -> "Balanced"
        }
        Text(
            text = gridText,
            style = MaterialTheme.typography.bodySmall,
            color = activeColor,
            fontWeight = FontWeight.Bold,
            fontSize = 9.sp
        )
    }
}

// ---- FlowNode Enum ----
enum class FlowNode {
    SOLAR, BATTERY, INVERTER, LOAD, GRID
}

// ---- Mascot View (WattPet) ----
@Composable
fun MascotView(
    solarKw: Double,
    chargeKw: Double,
    dischargeKw: Double,
    loadKw: Double,
    gridExportKw: Double,
    gridImportKw: Double,
    socPct: Int,
    weatherIcon: String,
    skin: String = "slime",
    modifier: Modifier = Modifier
) {
    val infiniteTransition = rememberInfiniteTransition(label = "mascotAnim")

    val scaleY by infiniteTransition.animateFloat(
        initialValue = 0.96f,
        targetValue = 1.04f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "mascotScaleY"
    )
    val scaleX by infiniteTransition.animateFloat(
        initialValue = 1.04f,
        targetValue = 0.96f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "mascotScaleX"
    )

    val blinkProgress by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = keyframes {
                durationMillis = 3500
                0.0f at 0
                0.0f at 3300
                1.0f at 3400
                0.0f at 3500
            },
            repeatMode = RepeatMode.Restart
        ),
        label = "mascotBlink"
    )

    val bodyColor = when {
        socPct < 20 -> Color(0xFFEF4444)
        chargeKw > 0.05 -> Color(0xFF10B981)
        weatherIcon == "rainy" || weatherIcon == "stormy" || weatherIcon == "drizzle" -> Color(0xFF3B82F6)
        else -> Color(0xFFFBBF24)
    }

    Canvas(modifier = modifier.size(40.dp)) {
        val w = size.width
        val h = size.height
        val cx = w / 2f
        val cy = h / 2f

        val drawW = w * scaleX
        val drawH = h * scaleY
        val left = cx - drawW / 2f
        val top = cy - drawH / 2f

        // Shadow under pet
        drawCircle(
            color = Color.Black.copy(alpha = 0.22f),
            radius = drawW * 0.35f,
            center = Offset(cx, top + drawH - 1.dp.toPx())
        )

        when (skin) {
            "cyber_cat" -> {
                val headPath = Path().apply {
                    addRoundRect(
                        RoundRect(
                            rect = Rect(left, top + drawH * 0.15f, left + drawW, top + drawH * 0.95f),
                            cornerRadius = CornerRadius(10.dp.toPx())
                        )
                    )
                }
                drawPath(path = headPath, brush = Brush.verticalGradient(listOf(Color(0xFF334155), Color(0xFF0F172A))))
                drawPath(path = headPath, color = Color(0xFF06B6D4), style = Stroke(width = 1.5.dp.toPx()))

                val leftEar = Path().apply {
                    moveTo(left + drawW * 0.15f, top + drawH * 0.2f)
                    lineTo(left + drawW * 0.02f, top - drawH * 0.1f)
                    lineTo(left + drawW * 0.4f, top + drawH * 0.15f)
                    close()
                }
                val rightEar = Path().apply {
                    moveTo(left + drawW * 0.85f, top + drawH * 0.2f)
                    lineTo(left + drawW * 0.98f, top - drawH * 0.1f)
                    lineTo(left + drawW * 0.6f, top + drawH * 0.15f)
                    close()
                }
                drawPath(path = leftEar, color = Color(0xFF06B6D4))
                drawPath(path = rightEar, color = Color(0xFF06B6D4))

                val eyeY = top + drawH * 0.48f
                val eyeW = drawW * 0.22f
                val eyeH = drawH * 0.12f
                val eyeColor = if (socPct < 20) Color(0xFFEF4444) else Color(0xFF22D3EE)
                drawRoundRect(
                    color = eyeColor,
                    topLeft = Offset(cx - drawW * 0.3f, eyeY),
                    size = Size(eyeW, eyeH),
                    cornerRadius = CornerRadius(2.dp.toPx())
                )
                drawRoundRect(
                    color = eyeColor,
                    topLeft = Offset(cx + drawW * 0.3f - eyeW, eyeY),
                    size = Size(eyeW, eyeH),
                    cornerRadius = CornerRadius(2.dp.toPx())
                )

                val whiskerY = eyeY + eyeH + 2.dp.toPx()
                drawLine(Color(0xFF06B6D4), Offset(left + 2.dp.toPx(), whiskerY), Offset(cx - drawW * 0.2f, whiskerY), 1.dp.toPx())
                drawLine(Color(0xFF06B6D4), Offset(left + drawW - 2.dp.toPx(), whiskerY), Offset(cx + drawW * 0.2f, whiskerY), 1.dp.toPx())
            }

            "solar_star" -> {
                val outerR = drawW * 0.48f
                val innerR = drawW * 0.25f

                drawOval(
                    color = SolarGold.copy(alpha = 0.6f),
                    topLeft = Offset(cx - drawW * 0.58f, cy - drawH * 0.22f),
                    size = Size(drawW * 1.16f, drawH * 0.44f),
                    style = Stroke(width = 2.dp.toPx())
                )

                val starPath = Path()
                for (i in 0 until 10) {
                    val r = if (i % 2 == 0) outerR else innerR
                    val angle = Math.toRadians(i * 36.0 - 90.0)
                    val x = cx + (r * Math.cos(angle)).toFloat()
                    val y = cy + (r * Math.sin(angle)).toFloat()
                    if (i == 0) starPath.moveTo(x, y) else starPath.lineTo(x, y)
                }
                starPath.close()

                drawPath(path = starPath, brush = Brush.radialGradient(listOf(Color(0xFFFDE047), Color(0xFFF59E0B))))

                val eyeY = cy - 2.dp.toPx()
                drawCircle(Color(0xFF1E293B), radius = 2.5.dp.toPx(), center = Offset(cx - 5.dp.toPx(), eyeY))
                drawCircle(Color(0xFF1E293B), radius = 2.5.dp.toPx(), center = Offset(cx + 5.dp.toPx(), eyeY))

                val mouthPath = Path().apply {
                    moveTo(cx - 3.dp.toPx(), eyeY + 5.dp.toPx())
                    quadraticTo(cx, eyeY + 8.dp.toPx(), cx + 3.dp.toPx(), eyeY + 5.dp.toPx())
                }
                drawPath(path = mouthPath, color = Color(0xFF1E293B), style = Stroke(width = 1.5.dp.toPx()))
            }

            "battery_pal" -> {
                val battWidth = drawW * 0.65f
                val battHeight = drawH * 0.85f
                val battLeft = cx - battWidth / 2f
                val battTop = cy - battHeight / 2f + 2.dp.toPx()

                drawRoundRect(
                    color = Color(0xFF94A3B8),
                    topLeft = Offset(cx - battWidth * 0.25f, battTop - 3.5.dp.toPx()),
                    size = Size(battWidth * 0.5f, 4.dp.toPx()),
                    cornerRadius = CornerRadius(1.dp.toPx())
                )

                drawRoundRect(
                    color = Color(0xFF1E293B),
                    topLeft = Offset(battLeft, battTop),
                    size = Size(battWidth, battHeight),
                    cornerRadius = CornerRadius(6.dp.toPx())
                )
                drawRoundRect(
                    color = Color(0xFF64748B),
                    topLeft = Offset(battLeft, battTop),
                    size = Size(battWidth, battHeight),
                    cornerRadius = CornerRadius(6.dp.toPx()),
                    style = Stroke(width = 1.8.dp.toPx())
                )

                val fillRatio = (socPct.coerceIn(5, 100)) / 100f
                val fillH = (battHeight - 4.dp.toPx()) * fillRatio
                val fillTop = battTop + (battHeight - 2.dp.toPx()) - fillH
                val fillColor = when {
                    socPct < 20 -> Color(0xFFEF4444)
                    socPct < 50 -> Color(0xFFFBBF24)
                    else -> BatteryGreen
                }
                drawRoundRect(
                    color = fillColor.copy(alpha = 0.85f),
                    topLeft = Offset(battLeft + 2.dp.toPx(), fillTop),
                    size = Size(battWidth - 4.dp.toPx(), fillH),
                    cornerRadius = CornerRadius(4.dp.toPx())
                )

                val eyeY = battTop + battHeight * 0.38f
                drawCircle(Color.White, radius = 2.2.dp.toPx(), center = Offset(cx - 4.5.dp.toPx(), eyeY))
                drawCircle(Color.White, radius = 2.2.dp.toPx(), center = Offset(cx + 4.5.dp.toPx(), eyeY))
            }

            else -> {
                val bodyPath = Path().apply {
                    moveTo(cx, top + drawH * 0.12f)
                    cubicTo(
                        cx - drawW * 0.48f, top + drawH * 0.15f,
                        cx - drawW * 0.52f, top + drawH * 0.82f,
                        cx, top + drawH
                    )
                    cubicTo(
                        cx + drawW * 0.52f, top + drawH * 0.82f,
                        cx + drawW * 0.48f, top + drawH * 0.15f,
                        cx, top + drawH * 0.12f
                    )
                    close()
                }

                drawPath(path = bodyPath, color = bodyColor)
                drawPath(
                    path = bodyPath,
                    brush = Brush.radialGradient(
                        colors = listOf(Color.White.copy(alpha = 0.45f), Color.Transparent),
                        center = Offset(cx, top + drawH * 0.35f),
                        radius = drawW * 0.45f
                    )
                )

                val eyeY = top + drawH * 0.52f
                val eyeSpacing = drawW * 0.17f
                val eyeRadius = 3.dp.toPx()

                drawCircle(color = Color(0xFF1E293B), radius = eyeRadius, center = Offset(cx - eyeSpacing, eyeY))
                drawCircle(color = Color(0xFF1E293B), radius = eyeRadius, center = Offset(cx + eyeSpacing, eyeY))

                if (blinkProgress > 0.85f) {
                    drawRect(
                        color = bodyColor,
                        topLeft = Offset(cx - eyeSpacing - eyeRadius, eyeY - eyeRadius),
                        size = Size(eyeRadius * 2, eyeRadius)
                    )
                    drawLine(
                        color = Color(0xFF1E293B),
                        start = Offset(cx - eyeSpacing - eyeRadius, eyeY),
                        end = Offset(cx - eyeSpacing + eyeRadius, eyeY),
                        strokeWidth = 1.2.dp.toPx()
                    )
                    drawRect(
                        color = bodyColor,
                        topLeft = Offset(cx + eyeSpacing - eyeRadius, eyeY - eyeRadius),
                        size = Size(eyeRadius * 2, eyeRadius)
                    )
                    drawLine(
                        color = Color(0xFF1E293B),
                        start = Offset(cx + eyeSpacing - eyeRadius, eyeY),
                        end = Offset(cx + eyeSpacing + eyeRadius, eyeY),
                        strokeWidth = 1.2.dp.toPx()
                    )
                }

                val cheekY = eyeY + 3.5.dp.toPx()
                val cheekX = drawW * 0.28f
                drawCircle(color = Color(0xFFFCA5A5).copy(alpha = 0.8f), radius = 2.dp.toPx(), center = Offset(cx - cheekX, cheekY))
                drawCircle(color = Color(0xFFFCA5A5).copy(alpha = 0.8f), radius = 2.dp.toPx(), center = Offset(cx + cheekX, cheekY))

                val mouthPath = Path()
                if (socPct < 20) {
                    mouthPath.moveTo(cx - 3.dp.toPx(), eyeY + 7.dp.toPx())
                    mouthPath.quadraticTo(cx, eyeY + 4.5.dp.toPx(), cx + 3.dp.toPx(), eyeY + 7.dp.toPx())
                    drawPath(path = mouthPath, color = Color(0xFF1E293B), style = Stroke(width = 1.6.dp.toPx()))
                } else {
                    mouthPath.moveTo(cx - 3.dp.toPx(), eyeY + 5.5.dp.toPx())
                    mouthPath.quadraticTo(cx, eyeY + 8.dp.toPx(), cx + 3.dp.toPx(), eyeY + 5.5.dp.toPx())
                    drawPath(path = mouthPath, color = Color(0xFF1E293B), style = Stroke(width = 1.6.dp.toPx()))
                }

                if (weatherIcon == "sunny" || weatherIcon == "clear") {
                    val glassW = drawW * 0.22f
                    val glassH = drawH * 0.08f
                    drawRoundRect(
                        color = Color(0xFF1E293B),
                        topLeft = Offset(cx - eyeSpacing - glassW / 2, eyeY - glassH / 2),
                        size = Size(glassW, glassH),
                        cornerRadius = CornerRadius(2.dp.toPx())
                    )
                    drawRoundRect(
                        color = Color(0xFF1E293B),
                        topLeft = Offset(cx + eyeSpacing - glassW / 2, eyeY - glassH / 2),
                        size = Size(glassW, glassH),
                        cornerRadius = CornerRadius(2.dp.toPx())
                    )
                    drawLine(
                        color = Color(0xFF1E293B),
                        start = Offset(cx - eyeSpacing, eyeY),
                        end = Offset(cx + eyeSpacing, eyeY),
                        strokeWidth = 1.5.dp.toPx()
                    )
                }

                if (weatherIcon == "rainy" || weatherIcon == "stormy" || weatherIcon == "drizzle") {
                    val stemStartX = cx
                    val stemStartY = top + drawH * 0.12f
                    val stemEndX = cx - 4.dp.toPx()
                    val stemEndY = top - 7.dp.toPx()
                    drawLine(
                        color = Color(0xFF15803D),
                        start = Offset(stemStartX, stemStartY),
                        end = Offset(stemEndX, stemEndY),
                        strokeWidth = 1.5.dp.toPx()
                    )
                    val leafPath = Path().apply {
                        moveTo(stemEndX, stemEndY)
                        quadraticTo(stemEndX - 7.dp.toPx(), stemEndY - 6.dp.toPx(), stemEndX - 15.dp.toPx(), stemEndY - 3.dp.toPx())
                        quadraticTo(stemEndX - 7.dp.toPx(), stemEndY + 2.dp.toPx(), stemEndX, stemEndY)
                    }
                    drawPath(path = leafPath, color = Color(0xFF22C55E))
                }

                if (gridExportKw > 0.05) {
                    val coinX = cx + drawW * 0.36f
                    val coinY = top + drawH * 0.72f
                    drawCircle(color = Color(0xFFFBBF24), radius = 3.8.dp.toPx(), center = Offset(coinX, coinY))
                    drawCircle(color = Color(0xFFD97706), radius = 3.8.dp.toPx(), center = Offset(coinX, coinY), style = Stroke(width = 1.dp.toPx()))
                }
            }
        }
    }
}


// ---- Energy Flow Card ----

@Composable
fun EnergyFlowCard(
    solarKw: Double,
    chargeKw: Double,
    dischargeKw: Double,
    loadKw: Double,
    gridExportKw: Double,
    gridImportKw: Double,
    socPct: Int,
    pv1Kw: Double?,
    pv2Kw: Double?,
    weather: com.example.xgrowatt.data.WeatherInfo,
    priorityMode: String?,
    targetSoc: String?,
    powerRate: String?,
    skin: String = "slime",
    live: com.example.xgrowatt.data.LiveDataFields? = null,
    teslaStatus: com.example.xgrowatt.data.TeslaStatus? = null,
    onMascotClick: () -> Unit = {}
) {
    val infiniteTransition = rememberInfiniteTransition(label = "flow")
    val flowPhase by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1800, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "flowPhase",
    )

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier
            .fillMaxWidth()
            .height(340.dp),
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            SoCCardBackground(soc = socPct)

            BoxWithConstraints(modifier = Modifier.fillMaxSize().padding(12.dp)) {
                val w = maxWidth
                val h = maxHeight

                val sunPos = Offset(w.value * 0.5f, 48f)
                val gridPos = Offset(w.value * 0.5f, 262f)
                val battPos = Offset(48f, 155f)
                val housePos = Offset(w.value - 48f, 155f)
                val inverterPos = Offset(w.value * 0.5f, 155f)
                // Tesla node sits above the Load/House node
                val teslaConnected = teslaStatus?.is_connected == true
                val teslaCharging = teslaStatus?.charging_state == "Charging"
                val teslaKw = (teslaStatus?.charger_power_kw ?: 0.0).toFloat()
                val teslaPos = Offset(w.value - 48f, 30f)

                // Mascot Trajectory State
                var currentMascotNode by remember { mutableStateOf(FlowNode.INVERTER) }
                val jumpAnim = remember { Animatable(0f) }
                var prevPos by remember { mutableStateOf(inverterPos) }
                var targetPos by remember { mutableStateOf(inverterPos) }

                // Mascot hop controller loop
                LaunchedEffect(solarKw, chargeKw, dischargeKw, loadKw, gridExportKw, gridImportKw) {
                    while (true) {
                        delay(4500)
                        val activeOuterNodes = mutableListOf<FlowNode>()
                        if (solarKw > 0.05) activeOuterNodes.add(FlowNode.SOLAR)
                        if (chargeKw > 0.05 || dischargeKw > 0.05) activeOuterNodes.add(FlowNode.BATTERY)
                        if (loadKw > 0.05) activeOuterNodes.add(FlowNode.LOAD)
                        if (gridImportKw > 0.05 || gridExportKw > 0.05) activeOuterNodes.add(FlowNode.GRID)

                        if (currentMascotNode != FlowNode.INVERTER) {
                            currentMascotNode = FlowNode.INVERTER
                        } else {
                            if (activeOuterNodes.isNotEmpty()) {
                                currentMascotNode = activeOuterNodes.random()
                            } else {
                                currentMascotNode = FlowNode.entries.filter { it != FlowNode.INVERTER }.random()
                            }
                        }
                    }
                }

                // Trigger smooth hopping animation whenever target node changes
                LaunchedEffect(currentMascotNode) {
                    val newTarget = when (currentMascotNode) {
                        FlowNode.SOLAR -> sunPos
                        FlowNode.BATTERY -> battPos
                        FlowNode.INVERTER -> inverterPos
                        FlowNode.LOAD -> housePos
                        FlowNode.GRID -> gridPos
                    }
                    prevPos = targetPos
                    targetPos = newTarget
                    jumpAnim.snapTo(0f)
                    jumpAnim.animateTo(
                        targetValue = 1f,
                        animationSpec = tween(750, easing = FastOutSlowInEasing)
                    )
                }

                // Compute exact jumping coordinates
                val currentMascotX = prevPos.x + (targetPos.x - prevPos.x) * jumpAnim.value
                val currentMascotY = prevPos.y + (targetPos.y - prevPos.y) * jumpAnim.value
                // Bouncing arc parabola offset (rises in the air by 45dp at mid-jump)
                val jumpArcY = -sin(jumpAnim.value * Math.PI.toFloat()) * 45f

                // Squash and stretch scale values during jump
                val jumpScaleY = 1.0f - 0.15f * cos(jumpAnim.value * Math.PI.toFloat() * 2f)
                val jumpScaleX = 1.0f + 0.15f * cos(jumpAnim.value * Math.PI.toFloat() * 2f)

                Canvas(modifier = Modifier.fillMaxSize()) {
                    val sunCenter = Offset(sunPos.x.dp.toPx(), sunPos.y.dp.toPx())
                    val gridCenter = Offset(gridPos.x.dp.toPx(), gridPos.y.dp.toPx())
                    val battCenter = Offset(battPos.x.dp.toPx(), battPos.y.dp.toPx())
                    val houseCenter = Offset(housePos.x.dp.toPx(), housePos.y.dp.toPx())
                    val inverterCenter = Offset(inverterPos.x.dp.toPx(), inverterPos.y.dp.toPx())

                    fun drawFlowLine(from: Offset, to: Offset, active: Boolean, color: Color) {
                        val strokeW = 2.5f.dp.toPx()
                        if (!active) {
                            drawLine(
                                color = Color.White.copy(alpha = 0.04f),
                                start = from, end = to,
                                strokeWidth = 1.5f.dp.toPx(),
                                cap = StrokeCap.Round
                            )
                            return
                        }
                        drawLine(
                            color = color.copy(alpha = 0.25f),
                            start = from, end = to,
                            strokeWidth = strokeW,
                            cap = StrokeCap.Round
                        )
                        val dotX = from.x + (to.x - from.x) * flowPhase
                        val dotY = from.y + (to.y - from.y) * flowPhase
                        drawCircle(color = color, radius = 4.5f.dp.toPx(), center = Offset(dotX, dotY))
                    }

                    drawFlowLine(sunCenter, inverterCenter, solarKw > 0.05, SolarGold)
                    if (chargeKw > 0.05) {
                        drawFlowLine(inverterCenter, battCenter, true, BatteryGreen)
                    } else {
                        drawFlowLine(battCenter, inverterCenter, dischargeKw > 0.05, BatteryGreen)
                    }
                    drawFlowLine(inverterCenter, houseCenter, loadKw > 0.05, LoadBlue)
                    if (gridExportKw > 0.05) {
                        drawFlowLine(inverterCenter, gridCenter, true, GridPurple)
                    } else {
                        drawFlowLine(gridCenter, inverterCenter, gridImportKw > 0.05, GridPurple)
                    }
                    // Tesla: animated flow line from top of Load node upward to bottom of Tesla node
                    if (teslaConnected && teslaCharging) {
                        // Load top center: (w - 48, 127 - 28 = 99) -> Tesla bottom center: (w - 48, 30 + 28 = 58)
                        val lineStart = Offset(houseCenter.x, houseCenter.y - 28.dp.toPx())
                        val lineEnd = Offset(houseCenter.x, 30.dp.toPx() + 28.dp.toPx())
                        val teslaColor = Color(0xFFE31937)
                        drawLine(
                            color = teslaColor.copy(alpha = 0.35f),
                            start = lineStart, end = lineEnd,
                            strokeWidth = 2.5f.dp.toPx(),
                            cap = StrokeCap.Round
                        )
                        val dotX = lineStart.x + (lineEnd.x - lineStart.x) * flowPhase
                        val dotY = lineStart.y + (lineEnd.y - lineStart.y) * flowPhase
                        drawCircle(color = teslaColor, radius = 4.5f.dp.toPx(), center = Offset(dotX, dotY))
                    }
                }

                val solarIcon = when (weather.icon) {
                    "sunny", "clear" -> Icons.Default.WbSunny
                    "partly_cloudy" -> Icons.Default.WbCloudy
                    "cloudy" -> Icons.Default.Cloud
                    "foggy", "foggy_night" -> Icons.Default.Cloud
                    "drizzle", "rainy", "rainy_night" -> Icons.Default.Grain
                    "stormy", "stormy_night" -> Icons.Default.Thunderstorm
                    "snowy", "snowy_night" -> Icons.Default.AcUnit
                    "clear_night", "cloudy_night" -> Icons.Default.NightsStay
                    else -> Icons.Default.WbSunny
                }
                val solarColor = Color(weather.color)
                val solarTitle = weather.description

                NodeView(
                    title = solarTitle,
                    icon = solarIcon,
                    valStr = String.format(Locale.US, "%.2f kW", solarKw),
                    color = solarColor,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .offset(y = 20.dp)
                )

                BatteryNodeView(
                    soc = socPct,
                    modeledSoc = live?.modeled_soc?.toDoubleOrNull(),
                    chargeKw = chargeKw,
                    dischargeKw = dischargeKw,
                    color = BatteryGreen,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .offset(x = 20.dp, y = 127.dp)
                )

                NodeView(
                    title = "Inverter",
                    icon = Icons.Default.Shield,
                    valStr = "",
                    color = Color.White.copy(alpha = 0.85f),
                    size = 56.dp,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .offset(y = 127.dp)
                )

                // Tesla node — only visible when connected (56.dp size matching all other nodes)
                if (teslaConnected) {
                    val teslaBattPct = teslaStatus?.battery_level ?: 0
                    val teslaLabel = if (teslaCharging)
                        "⚡ ${String.format("%.1f", teslaKw)} kW"
                    else
                        "$teslaBattPct%"
                    val teslaInfinite = rememberInfiniteTransition(label = "teslaPulse")
                    val teslaPulse by teslaInfinite.animateFloat(
                        initialValue = 0.75f, targetValue = 1f,
                        animationSpec = infiniteRepeatable(
                            animation = tween(900, easing = FastOutSlowInEasing),
                            repeatMode = RepeatMode.Reverse
                        ), label = "teslaPulse"
                    )
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .offset(x = (-20).dp, y = 20.dp)
                            .alpha(if (teslaCharging) teslaPulse else 1f)
                    ) {
                        Box(
                            contentAlignment = Alignment.Center,
                            modifier = Modifier.size(56.dp)
                        ) {
                            Surface(
                                shape = CircleShape,
                                color = if (teslaCharging) Color(0xFF7F1D1D).copy(alpha = 0.4f) else Color.White.copy(alpha = 0.08f),
                                border = BorderStroke(
                                    1.5.dp,
                                    if (teslaCharging) Color(0xFFDC2626).copy(alpha = 0.6f) else Color.White.copy(alpha = 0.25f)
                                ),
                                modifier = Modifier.fillMaxSize()
                            ) {}
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center
                            ) {
                                Text(
                                    text = "$teslaBattPct%",
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (teslaCharging) Color(0xFFF87171) else Color.White.copy(alpha = 0.9f)
                                )
                            }
                        }
                        Text(
                            text = teslaStatus?.car_name ?: "Tesla",
                            style = MaterialTheme.typography.labelSmall,
                            color = TextSecondary,
                            fontSize = 8.sp,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            text = if (teslaCharging) "⚡ ${String.format(Locale.US, "%.1f kW", teslaKw)}" else "Standby",
                            style = MaterialTheme.typography.labelSmall,
                            color = if (teslaCharging) Color(0xFFF87171) else Color.White.copy(alpha = 0.45f),
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                NodeView(
                    title = "Load",
                    icon = Icons.Default.Home,
                    valStr = String.format("%.2f kW", loadKw),
                    color = LoadBlue,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = (-20).dp, y = 127.dp)
                )

                GridNodeView(
                    importKw = gridImportKw,
                    exportKw = gridExportKw,
                    color = GridPurple,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .offset(y = 234.dp)
                )



                // Bottom Left metadata display: Priority Mode, Target SoC, Power Rate
                Column(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(bottom = 4.dp, start = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    val modeText = priorityMode ?: "unknown"
                    val disCmd = FirebaseManager.disChargePowerCommand.collectAsState().value ?: live?.disChargePowerCommand ?: "100"
                    val chgCmd = FirebaseManager.chargePowerCommand.collectAsState().value ?: live?.chargePowerCommand ?: "100"
                    val isDisColdActive = (disCmd.toIntOrNull() ?: 100) < 100
                    val isChgColdActive = (chgCmd.toIntOrNull() ?: 100) < 100
                    Text(
                        text = modeText.uppercase(Locale.US),
                        color = Color.White.copy(alpha = 0.85f),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        fontSize = 9.sp
                    )
                    Text(
                        text = "⚡ Disch: $disCmd%",
                        color = if (isDisColdActive) Color(0xFFF97316) else TextSecondary,
                        style = MaterialTheme.typography.labelSmall,
                        fontSize = 8.5.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "🔌 Chg: $chgCmd%",
                        color = if (isChgColdActive) Color(0xFFF97316) else TextSecondary,
                        style = MaterialTheme.typography.labelSmall,
                        fontSize = 8.5.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                // Bottom Right metadata display: Next Sync countdown timer
                Column(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(bottom = 4.dp, end = 8.dp),
                    horizontalAlignment = Alignment.End
                ) {
                    var secondsRemaining by remember { mutableStateOf(300) }
                    LaunchedEffect(Unit) {
                        while (true) {
                            val now = Calendar.getInstance()
                            val min = now.get(Calendar.MINUTE)
                            val sec = now.get(Calendar.SECOND)
                            val elapsedSeconds = (min % 5) * 60 + sec
                            secondsRemaining = 300 - elapsedSeconds
                            delay(1000)
                        }
                    }
                    val m = secondsRemaining / 60
                    val s = secondsRemaining % 60
                    Text(
                        text = "NEXT SYNC",
                        color = Color.White.copy(alpha = 0.4f),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        fontSize = 8.sp
                    )
                    Text(
                        text = "${m}m ${s}s",
                        color = TextSecondary,
                        style = MaterialTheme.typography.labelSmall,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        }
    }
}

/// Ambient background for the LIVE energy flow card: a soft glow that rises from the
/// bottom of the card, taller and slightly stronger the higher the battery's SoC — colored
/// red/gold/green using the same 20% threshold used elsewhere for battery health. Has no
/// hard edge anywhere: rather than clipping a rect to a fill height (which reads as a
/// literal gauge with a visible waterline), the gradient's own end-Y moves with SoC, so
/// it's always a single smooth fade from the bottom to nothing — mood lighting, not a
/// level indicator. `Brush.verticalGradient` clamps beyond its stops by default, so nothing
/// extra is needed above that point; it's simply transparent.
@Composable
fun SoCCardBackground(soc: Int) {
    val fraction = (soc.coerceIn(0, 100) / 100f)
    val animatedFraction by animateFloatAsState(
        targetValue = fraction,
        animationSpec = tween(600),
        label = "socFill"
    )
    val tint = when {
        soc < 20 -> AlertRed
        soc < 50 -> SolarGold
        else -> BatteryGreen
    }

    Canvas(modifier = Modifier.fillMaxSize()) {
        drawRect(
            brush = Brush.verticalGradient(
                colors = listOf(tint.copy(alpha = 0.22f), tint.copy(alpha = 0f)),
                startY = size.height,
                endY = size.height * (1f - animatedFraction)
            )
        )
    }
}

// ---- Efficiency Banner ----

@Composable
fun EfficiencyBanner(
    selfSufficiency: Double,
    selfConsumption: Double,
    treesSaved: Double,
    co2Avoided: Double
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Filled.Eco,
                        contentDescription = null,
                        tint = BatteryGreen,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "TODAY'S EFFICIENCY",
                        style = MaterialTheme.typography.labelSmall,
                        color = BatteryGreen,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp
                    )
                }
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Column(modifier = Modifier.weight(1f)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Self-Sufficiency", style = MaterialTheme.typography.bodySmall, color = TextSecondary)
                        Text("${String.format("%.1f", selfSufficiency)}%", style = MaterialTheme.typography.bodySmall, color = Color.White, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(4.dp))
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(4.dp)
                            .background(Color.White.copy(alpha = 0.05f), RoundedCornerShape(2.dp))
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth(fraction = (selfSufficiency / 100.0).toFloat())
                                .fillMaxHeight()
                                .background(LoadBlue, RoundedCornerShape(2.dp))
                        )
                    }
                }

                Column(modifier = Modifier.weight(1f)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Self-Consumption", style = MaterialTheme.typography.bodySmall, color = TextSecondary)
                        Text("${String.format("%.1f", selfConsumption)}%", style = MaterialTheme.typography.bodySmall, color = Color.White, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(4.dp))
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(4.dp)
                            .background(Color.White.copy(alpha = 0.05f), RoundedCornerShape(2.dp))
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth(fraction = (selfConsumption / 100.0).toFloat())
                                .fillMaxHeight()
                                .background(SolarGold, RoundedCornerShape(2.dp))
                        )
                    }
                }
            }

            // Eco metrics
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.White.copy(alpha = 0.015f), RoundedCornerShape(8.dp))
                    .padding(8.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = String.format("🌲 Trees Saved: %.4f", treesSaved),
                    style = MaterialTheme.typography.labelSmall,
                    color = BatteryGreen
                )
                Text(
                    text = String.format("💨 CO₂ Avoided: %.1f kg", co2Avoided),
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary
                )
            }
        }
    }
}

// ---- Quick Stats Grid (LIVE FLOW & TODAY TOTALS) ----

@Composable
fun QuickStatsGrid(
    pvVal: Double,
    pv1Val: Double?,
    pv2Val: Double?,
    vpv1: String?,
    vpv2: String?,
    loadVal: Double,
    socVal: Int,
    chgPower: Double,
    dischPower: Double,
    gridImpVal: Double,
    gridExpVal: Double,
    // Totals
    totalSolar: Double,
    totalLoad: Double,
    totalImport: Double,
    totalExport: Double,
    totalCharge: Double,
    totalDischarge: Double,
    epv1: Double?,
    epv2: Double?
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Left Column: Live Flow
        Card(
            colors = CardDefaults.cardColors(containerColor = CardBg),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.weight(1f)
        ) {
            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "LIVE FLOW",
                    style = MaterialTheme.typography.labelSmall,
                    color = BatteryGreen,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                )

                // Solar Row
                FlowRowItem(icon = Icons.Filled.WbSunny, iconColor = SolarGold, label = "Solar PV", value = String.format("%.2f kW", pvVal))
                if (pv1Val != null && pv2Val != null) {
                    MpptRowItem("PV1", String.format("%.2f kW", pv1Val), vpv1)
                    MpptRowItem("PV2", String.format("%.2f kW", pv2Val), vpv2)
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.05f))
                FlowRowItem(icon = Icons.Filled.Home, iconColor = LoadBlue, label = "Home Load", value = String.format("%.2f kW", loadVal))
                HorizontalDivider(color = Color.White.copy(alpha = 0.05f))

                // Battery Row
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Filled.BatteryChargingFull,
                        contentDescription = null,
                        tint = BatteryGreen,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("Battery", style = MaterialTheme.typography.bodySmall, color = TextSecondary)
                    Spacer(Modifier.weight(1f))
                    Text("$socVal%", style = MaterialTheme.typography.bodySmall, color = Color.White, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(4.dp))
                    val bFlow = when {
                        chgPower > 0.05 -> "(+${String.format("%.1f", chgPower)})"
                        dischPower > 0.05 -> "(-${String.format("%.1f", dischPower)})"
                        else -> "(idle)"
                    }
                    val bFlowColor = if (chgPower > 0.05) BatteryGreen else if (dischPower > 0.05) Color(0xFFF97316) else TextSecondary
                    Text(bFlow, style = MaterialTheme.typography.labelSmall, color = bFlowColor, fontSize = 9.sp)
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.05f))

                // Grid Row
                val netGrid = gridImpVal - gridExpVal
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Filled.FlashOn,
                        contentDescription = null,
                        tint = if (netGrid > 0.05) AlertRed else if (netGrid < -0.05) SolarGold else TextSecondary,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("Grid Power", style = MaterialTheme.typography.bodySmall, color = TextSecondary)
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = when {
                            netGrid > 0.05 -> "+${String.format("%.2f kW", netGrid)}"
                            netGrid < -0.05 -> "-${String.format("%.2f kW", Math.abs(netGrid))}"
                            else -> "0.00 kW"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = if (netGrid > 0.05) AlertRed else if (netGrid < -0.05) SolarGold else Color.White,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        // Right Column: Today's Cumulative Totals
        Card(
            colors = CardDefaults.cardColors(containerColor = CardBg),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.weight(1f)
        ) {
            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "TODAY TOTALS",
                    style = MaterialTheme.typography.labelSmall,
                    color = SolarGold,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                )

                // Solar Yield Row
                FlowRowItem(icon = Icons.Filled.WbSunny, iconColor = SolarGold, label = "Solar Yield", value = String.format("%.2f kWh", totalSolar))
                if (epv1 != null && epv2 != null) {
                    MpptRowItem("PV1", String.format("%.1f kWh", epv1))
                    MpptRowItem("PV2", String.format("%.1f kWh", epv2))
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.05f))
                FlowRowItem(icon = Icons.Filled.Home, iconColor = LoadBlue, label = "Load Cons", value = String.format("%.2f kWh", totalLoad))
                HorizontalDivider(color = Color.White.copy(alpha = 0.05f))

                // Battery cycle
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Filled.BatteryChargingFull,
                        contentDescription = null,
                        tint = BatteryGreen,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("Batt Chg/Dis", style = MaterialTheme.typography.bodySmall, color = TextSecondary)
                    Spacer(Modifier.weight(1f))
                    Text(
                        String.format("%.1f/%.1f", totalCharge, totalDischarge),
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.05f))

                // Grid cycle
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Filled.FlashOn,
                        contentDescription = null,
                        tint = GridPurple,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("Grid Imp/Exp", style = MaterialTheme.typography.bodySmall, color = TextSecondary)
                    Spacer(Modifier.weight(1f))
                    Text(
                        String.format("%.1f/%.1f", totalImport, totalExport),
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

@Composable
fun FlowRowItem(icon: androidx.compose.ui.graphics.vector.ImageVector, iconColor: Color, label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(imageVector = icon, contentDescription = null, tint = iconColor, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(6.dp))
        Text(label, style = MaterialTheme.typography.bodySmall, color = TextSecondary)
        Spacer(Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodySmall, color = Color.White, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun MpptRowItem(label: String, value: String, voltage: String? = null) {
    Row(
        modifier = Modifier.padding(start = 18.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("└ $label", style = MaterialTheme.typography.labelSmall, color = TextSecondary.copy(alpha = 0.7f), fontSize = 9.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        if (voltage != null && voltage.toDoubleOrNull() ?: 0.0 > 1.0) {
            Text("${voltage.substringBefore(".")}V", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
            Spacer(Modifier.width(4.dp))
        }
        Text(value, style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.85f), fontSize = 9.5.sp, fontWeight = FontWeight.Bold)
    }
}

// ---- Energy Balance Card ----

@Composable
fun EnergyBalanceCard(
    totalInputs: Double,
    totalOutputs: Double,
    totalSolar: Double,
    totalDischarge: Double,
    totalImport: Double,
    totalLoad: Double,
    totalCharge: Double,
    totalExport: Double
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Filled.RotateRight,
                    contentDescription = null,
                    tint = BatteryGreen,
                    modifier = Modifier.size(14.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    "ENERGY BALANCE (TODAY)",
                    style = MaterialTheme.typography.labelSmall,
                    color = BatteryGreen,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Left Bar: Inputs
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .background(Color.White.copy(alpha = 0.015f), RoundedCornerShape(10.dp))
                        .border(1.dp, Color.White.copy(alpha = 0.03f), RoundedCornerShape(10.dp))
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                        Text("INPUTS", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)
                        Text(String.format("%.2f kWh", totalInputs), style = MaterialTheme.typography.labelSmall, color = BatteryGreen, fontWeight = FontWeight.Bold)
                    }

                    // Segmented input bar
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .clip(RoundedCornerShape(3.dp)),
                        horizontalArrangement = Arrangement.spacedBy(1.5.dp)
                    ) {
                        if (totalInputs > 0.05) {
                            val wSolar = (totalSolar / totalInputs).toFloat()
                            val wDisch = (totalDischarge / totalInputs).toFloat()
                            val wImport = (totalImport / totalInputs).toFloat()
                            if (wSolar > 0.01f) Box(Modifier.fillMaxHeight().weight(wSolar).background(SolarGold))
                            if (wDisch > 0.01f) Box(Modifier.fillMaxHeight().weight(wDisch).background(Color(0xFFF97316)))
                            if (wImport > 0.01f) Box(Modifier.fillMaxHeight().weight(wImport).background(GridPurple))
                        } else {
                            Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.05f)))
                        }
                    }

                    // Sinks
                    BalanceItemRow("Solar", totalSolar, totalInputs, SolarGold)
                    BalanceItemRow("Bat Dis", totalDischarge, totalInputs, Color(0xFFF97316))
                    BalanceItemRow("Grid Imp", totalImport, totalInputs, GridPurple)
                }

                // Right Bar: Outputs
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .background(Color.White.copy(alpha = 0.015f), RoundedCornerShape(10.dp))
                        .border(1.dp, Color.White.copy(alpha = 0.03f), RoundedCornerShape(10.dp))
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                        Text("OUTPUTS", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)
                        Text(String.format("%.2f kWh", totalOutputs), style = MaterialTheme.typography.labelSmall, color = SolarGold, fontWeight = FontWeight.Bold)
                    }

                    // Segmented output bar
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .clip(RoundedCornerShape(3.dp)),
                        horizontalArrangement = Arrangement.spacedBy(1.5.dp)
                    ) {
                        if (totalOutputs > 0.05) {
                            val wLoad = (totalLoad / totalOutputs).toFloat()
                            val wChg = (totalCharge / totalOutputs).toFloat()
                            val wExport = (totalExport / totalOutputs).toFloat()
                            if (wLoad > 0.01f) Box(Modifier.fillMaxHeight().weight(wLoad).background(LoadBlue))
                            if (wChg > 0.01f) Box(Modifier.fillMaxHeight().weight(wChg).background(BatteryGreen))
                            if (wExport > 0.01f) Box(Modifier.fillMaxHeight().weight(wExport).background(AlertRed))
                        } else {
                            Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.05f)))
                        }
                    }

                    // Sources
                    val teslaState = FirebaseManager.teslaStatus.collectAsState().value
                    val teslaKwh = teslaState?.charge_energy_added_kwh ?: 0.0
                    val houseKwh = maxOf(0.0, totalLoad - teslaKwh)

                    if (teslaKwh > 0.1) {
                        BalanceItemRow("House Load", houseKwh, totalOutputs, LoadBlue)
                        BalanceItemRow("Tesla EV", teslaKwh, totalOutputs, Color(0xFFCC0000))
                    } else {
                        BalanceItemRow("Load", totalLoad, totalOutputs, LoadBlue)
                    }
                    BalanceItemRow("Bat Chg", totalCharge, totalOutputs, BatteryGreen)
                    BalanceItemRow("Grid Exp", totalExport, totalOutputs, AlertRed)
                }
            }

            // Tesla Tariff Sub-Metering & Savings Badge
            val teslaState = FirebaseManager.teslaStatus.collectAsState().value
            val teslaKwh = teslaState?.charge_energy_added_kwh ?: 0.0
            if (teslaKwh > 0.1) {
                val estCost = teslaKwh * 0.11
                val estSavings = teslaKwh * (0.35 - 0.11)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(BatteryGreen.copy(alpha = 0.1f))
                        .border(1.dp, BatteryGreen.copy(alpha = 0.25f), RoundedCornerShape(8.dp))
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("🚘", fontSize = 11.sp)
                        Text(
                            text = "Tesla Tariff Matched: ${String.format(Locale.US, "%.1f", teslaKwh)} kWh ($${String.format(Locale.US, "%.2f", estCost)})",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize = 9.5.sp
                        )
                    }
                    Text(
                        text = "Saved $${String.format(Locale.US, "%.2f", estSavings)} (Off-Peak)",
                        style = MaterialTheme.typography.labelSmall,
                        color = BatteryGreen,
                        fontWeight = FontWeight.ExtraBold,
                        fontSize = 9.5.sp
                    )
                }
            }
        }
    }
}

@Composable
fun BalanceItemRow(label: String, value: Double, total: Double, color: Color) {
    val pct = if (total > 0) (value / total * 100.0) else 0.0
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Box(
            Modifier
                .size(6.dp)
                .clip(CircleShape)
                .background(color))
        Spacer(Modifier.width(6.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
        Spacer(Modifier.weight(1f))
        Text(
            text = String.format("%.1f kWh (%.0f%%)", value, pct),
            style = MaterialTheme.typography.labelSmall,
            color = Color.White,
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

// ---- Weather Forecast Card ----

@Composable
fun WeatherForecastCard(
    hours: List<ForecastHour>,
    issuedAt: Date?
) {
    val now = Date()
    val next24 = hours.filter { (it.time?.time ?: 0) >= now.time - 1800 * 1000 }.take(24)
    if (next24.isEmpty()) return

    val maxGti = next24.mapNotNull { it.gti }.maxOrNull()?.coerceAtLeast(100.0) ?: 100.0
    val rainTotal = next24.mapNotNull { it.precipMm }.sum()
    val gtiTotal = next24.mapNotNull { it.gti }.sum() / 1000.0

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Filled.Cloud,
                        contentDescription = null,
                        tint = SolarGold,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "24H SOLAR FORECAST",
                        style = MaterialTheme.typography.labelSmall,
                        color = SolarGold,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp
                    )
                }
                issuedAt?.let {
                    val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
                    Text(
                        text = "issued ${sdf.format(it)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = TextSecondary,
                        fontSize = 8.5.sp
                    )
                }
            }

            // Legend
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                WeatherLegendItem("Irradiance", SolarGold, dashed = false)
                WeatherLegendItem("Cloud %", TextSecondary, dashed = true)
                if (rainTotal > 0.05) {
                    WeatherLegendItem("Rain", LoadBlue, dashed = false)
                }
            }

            // Custom Canvas Chart (Irradiance & Cloud Cover)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(110.dp)
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val w = size.width
                    val h = size.height
                    val n = next24.size

                    fun xForIndex(i: Int) = w * i.toFloat() / (n - 1)

                    // Draw grid lines
                    for (i in 0..3) {
                        val y = h * (1f - i / 3f)
                        drawLine(
                            color = Color.White.copy(alpha = 0.05f),
                            start = Offset(0f, y),
                            end = Offset(w, y),
                            strokeWidth = 1.dp.toPx(),
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f), 0f)
                        )
                    }

                    // 1. Draw Irradiance Bars
                    val barWidth = (w / n) * 0.7f
                    next24.forEachIndexed { i, hour ->
                        val gti = hour.gti ?: 0.0
                        val precip = hour.precipMm ?: 0.0
                        val barHeight = (gti / maxGti).toFloat() * h
                        val barColor = if (precip > 0.2) LoadBlue.copy(alpha = 0.6f) else SolarGold.copy(alpha = 0.8f)

                        drawRect(
                            color = barColor,
                            topLeft = Offset(xForIndex(i) - barWidth / 2, h - barHeight),
                            size = Size(barWidth, barHeight)
                        )
                    }

                    // 2. Draw Cloud Cover Dashed Line
                    val cloudPath = Path()
                    next24.forEachIndexed { i, hour ->
                        val cloud = hour.cloudPct ?: 0.0
                        val x = xForIndex(i)
                        val y = h * (1f - (cloud / 100.0).toFloat())
                        if (i == 0) cloudPath.moveTo(x, y) else cloudPath.lineTo(x, y)
                    }
                    drawPath(
                        path = cloudPath,
                        color = Color.Gray.copy(alpha = 0.8f),
                        style = Stroke(
                            width = 1.5.dp.toPx(),
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f), 0f)
                        )
                    )
                }
            }

            // 1b. Rain Forecast Mini-Chart (hidden on dry days)
            if (rainTotal > 0.05) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(36.dp)
                ) {
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val w = size.width
                        val h = size.height
                        val n = next24.size
                        val maxRain = next24.mapNotNull { it.precipMm }.maxOrNull()?.coerceAtLeast(1.0) ?: 1.0

                        fun xForIndex(i: Int) = w * i.toFloat() / (n - 1)

                        // Draw dashed middle axis line for scale reference
                        val yMid = h * 0.5f
                        drawLine(
                            color = Color.White.copy(alpha = 0.06f),
                            start = Offset(0f, yMid),
                            end = Offset(w, yMid),
                            strokeWidth = 0.5f.dp.toPx(),
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f), 0f)
                        )

                        // Draw Rain Bars
                        val barWidth = (w / n) * 0.7f
                        next24.forEachIndexed { i, hour ->
                            val precip = hour.precipMm ?: 0.0
                            if (precip > 0.0) {
                                val barHeight = (precip / maxRain).toFloat() * h
                                drawRect(
                                    color = LoadBlue.copy(alpha = 0.8f),
                                    topLeft = Offset(xForIndex(i) - barWidth / 2, h - barHeight),
                                    size = Size(barWidth, barHeight)
                                )
                            }
                        }
                    }
                }
            }

            // Time Labels
            if (next24.size >= 2) {
                val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
                val tFirst = next24.first().time
                val tMid = next24[next24.size / 2].time
                val tLast = next24.last().time
                if (tFirst != null && tMid != null && tLast != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(sdf.format(tFirst), style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp)
                        Text(sdf.format(tMid), style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp)
                        Text(sdf.format(tLast), style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp)
                    }
                }
            }

            // 3-Hourly strip
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(8.dp))
                    .padding(vertical = 6.dp),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                for (i in 0 until next24.size step 3) {
                    val hour = next24[i]
                    val timeStr = hour.time?.let { SimpleDateFormat("HH", Locale.getDefault()).format(it) } ?: ""
                    val icon = getWeatherIcon(hour.weatherCode, hour.isDay)
                    val tempStr = hour.tempC?.let { String.format("%.0f°", it) } ?: "–"
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(timeStr, style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp, fontWeight = FontWeight.Bold)
                        Text(icon, fontSize = 11.sp)
                        Text(tempStr, style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.85f), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            // One-line summary
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                IconTextLabel(icon = "☀️", text = String.format("GTI %.1f kWh/m²", gtiTotal))
                if (rainTotal > 0.05) {
                    IconTextLabel(icon = "💧", text = String.format("Rain %.1f mm", rainTotal))
                }
                val temps = next24.mapNotNull { it.tempC }
                if (temps.isNotEmpty()) {
                    val minT = temps.minOrNull() ?: 0.0
                    val maxT = temps.maxOrNull() ?: 0.0
                    IconTextLabel(icon = "🌡️", text = String.format("%.0f°/%.0f°", minT, maxT))
                }
            }
        }
    }
}

@Composable
fun WeatherLegendItem(label: String, color: Color, dashed: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Canvas(modifier = Modifier.size(width = 12.dp, height = 4.dp)) {
            drawLine(
                color = color,
                start = Offset(0f, size.height / 2),
                end = Offset(size.width, size.height / 2),
                strokeWidth = 2.dp.toPx(),
                pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(4f, 4f), 0f) else null
            )
        }
        Spacer(Modifier.width(4.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, color = color, fontSize = 8.5.sp)
    }
}

@Composable
fun IconTextLabel(icon: String, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(icon, fontSize = 10.sp)
        Spacer(Modifier.width(4.dp))
        Text(text, style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp, fontWeight = FontWeight.Bold)
    }
}

private fun getWeatherIcon(code: Int?, isDay: Boolean): String {
    return when (code ?: -1) {
        0 -> if (isDay) "☀️" else "🌙"
        1, 2 -> if (isDay) "🌤️" else "☁️"
        3 -> "☁️"
        45, 48 -> "🌫️"
        in 51..57 -> "🌧️"
        in 61..67 -> "🌧️"
        in 71..77 -> "❄️"
        in 80..82 -> "🌧️"
        in 95..99 -> "⛈️"
        else -> "❓"
    }
}


@Composable
fun LastSyncCard(
    status: String,
    message: String,
    timestamp: String
) {
    val statusColor = when (status.lowercase()) {
        "success" -> BatteryGreen
        "error", "failure" -> AlertRed
        else -> TextSecondary
    }
    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(statusColor)
            )
            Spacer(Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Last Sync: $timestamp",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                    fontWeight = FontWeight.Bold
                )
                if (message.isNotEmpty()) {
                    Text(
                        text = message,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.85f)
                    )
                }
            }
        }
    }
}

fun formatTeslaLastUpdated(isoTimeStr: String): String {
    if (isoTimeStr.isEmpty()) return ""
    return try {
        val cleanStr = if (isoTimeStr.endsWith("Z")) isoTimeStr else isoTimeStr.replace(Regex("\\+00:00$"), "Z")
        val instant = java.time.Instant.parse(cleanStr)
        val now = java.time.Instant.now()
        val diffSec = java.time.Duration.between(instant, now).seconds
        when {
            diffSec < 45 -> "Updated just now"
            diffSec < 3600 -> "Updated ${diffSec / 60}m ago"
            diffSec < 86400 -> "Updated ${diffSec / 3600}h ago"
            else -> {
                val zdt = instant.atZone(java.time.ZoneId.systemDefault())
                "Updated ${zdt.format(java.time.format.DateTimeFormatter.ofPattern("HH:mm"))}"
            }
        }
    } catch (_: Exception) {
        "Updated recently"
    }
}

@Composable
fun TeslaEvLiveCard() {
    val teslaState by FirebaseManager.teslaStatus.collectAsState()
    val tesla = teslaState ?: return
    val isCharging = tesla.charging_state == "Charging"

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            // Header: Tesla Icon + Car Name & Last Updated + Connection Badge
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("🚘", fontSize = 16.sp)
                    Column {
                        Text(
                            text = tesla.car_name.uppercase(),
                            style = MaterialTheme.typography.labelSmall,
                            color = BatteryGreen,
                            fontWeight = FontWeight.ExtraBold,
                            letterSpacing = 1.2.sp
                        )
                        val lastUpdatedText = formatTeslaLastUpdated(tesla.last_updated)
                        if (lastUpdatedText.isNotEmpty()) {
                            Text(
                                text = lastUpdatedText,
                                style = MaterialTheme.typography.labelSmall,
                                color = TextSecondary,
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Normal
                            )
                        }
                    }
                }

                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    var isWaking by remember { mutableStateOf(false) }
                    
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (isCharging) BatteryGreen.copy(alpha = 0.15f) else Color.White.copy(alpha = 0.08f))
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            if (isCharging) {
                                Text("⚡", fontSize = 10.sp)
                            }
                            Text(
                                text = if (isWaking) "WAKING UP..." else tesla.charging_state.uppercase(),
                                style = MaterialTheme.typography.labelSmall,
                                color = if (isWaking) BatteryGreen else (if (isCharging) BatteryGreen else TextSecondary),
                                fontWeight = FontWeight.Bold,
                                fontSize = 9.sp
                            )
                        }
                    }

                    // 🔄 Wake & Sync Button
                    IconButton(
                        onClick = {
                            isWaking = true
                            FirebaseManager.triggerWakeUpTeslaNow { success, note ->
                                isWaking = false
                            }
                        },
                        enabled = !isWaking,
                        modifier = Modifier.size(26.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Refresh,
                            contentDescription = "Wake up & Sync Tesla",
                            tint = if (isWaking) BatteryGreen else TextSecondary,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.1f))

            // Two-column Split: Left metrics (55%), Right live map (45%)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(155.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                // Left Column: Smart Context-Aware Metrics
                Column(
                    modifier = Modifier
                        .weight(1.1f)
                        .fillMaxHeight(),
                    verticalArrangement = Arrangement.SpaceBetween
                ) {
                    val isDriving = tesla.location_name.contains("Driving")
                    
                    // Card 1: Battery Level & Target / Est Range
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.White.copy(alpha = 0.04f))
                            .padding(horizontal = 8.dp, vertical = 5.dp)
                    ) {
                        Text("Battery Level", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
                        Row(verticalAlignment = Alignment.Bottom) {
                            Text("${tesla.battery_level}", style = MaterialTheme.typography.titleMedium, color = Color.White, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.width(2.dp))
                            Text("%", style = MaterialTheme.typography.labelSmall, color = BatteryGreen, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.width(4.dp))
                            if (isCharging) {
                                Text("(${tesla.charge_limit_soc}% Max)", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
                            } else {
                                val estKm = (tesla.battery_level * 4.35).toInt()
                                Text("(~${estKm} km)", style = MaterialTheme.typography.labelSmall, color = BatteryGreen.copy(alpha = 0.85f), fontSize = 8.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }

                    // Card 2: Dynamic Context (Charger Power when Charging, Status/Speed when Parked or Driving)
                    if (isCharging) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(BatteryGreen.copy(alpha = 0.08f))
                                .border(1.dp, BatteryGreen.copy(alpha = 0.3f), RoundedCornerShape(10.dp))
                                .padding(horizontal = 8.dp, vertical = 5.dp)
                        ) {
                            Text("Charger Power", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
                            Row(verticalAlignment = Alignment.Bottom) {
                                Text(String.format(Locale.US, "%.1f", tesla.charger_power_kw), style = MaterialTheme.typography.titleMedium, color = BatteryGreen, fontWeight = FontWeight.Bold)
                                Spacer(Modifier.width(2.dp))
                                Text("kW", style = MaterialTheme.typography.labelSmall, color = BatteryGreen, fontWeight = FontWeight.Bold)
                                Spacer(Modifier.width(5.dp))
                                Text("${tesla.charger_voltage}V/${tesla.charger_actual_current}A", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 7.5.sp)
                            }
                        }
                    } else {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color.White.copy(alpha = 0.04f))
                                .padding(horizontal = 8.dp, vertical = 5.dp)
                        ) {
                            Text(if (isDriving) "Vehicle Speed" else "Vehicle Status", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
                            Row(verticalAlignment = Alignment.Bottom) {
                                Text(
                                    text = if (isDriving) "45" else "Locked",
                                    style = MaterialTheme.typography.titleMedium,
                                    color = Color.White,
                                    fontWeight = FontWeight.Bold
                                )
                                Spacer(Modifier.width(3.dp))
                                Text(
                                    text = if (isDriving) "mph" else "🔒 Sentry Off",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = if (isDriving) BatteryGreen else TextSecondary,
                                    fontSize = 8.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }

                    // Card 3: Dynamic Footer (Added Energy & Time when Charging, Location when Standby/Driving)
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(Color.White.copy(alpha = 0.03f))
                            .padding(horizontal = 8.dp, vertical = 5.dp)
                    ) {
                        if (isCharging) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Column {
                                    Text("Added Energy", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 7.5.sp)
                                    Text("+${tesla.charge_energy_added_kwh} kWh", style = MaterialTheme.typography.labelSmall, color = BatteryGreen, fontWeight = FontWeight.Bold, fontSize = 9.sp)
                                }
                                if (tesla.minutes_to_full_charge > 0) {
                                    Column(horizontalAlignment = Alignment.End) {
                                        Text("Time Left", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 7.5.sp)
                                        Text("${tesla.minutes_to_full_charge} min", style = MaterialTheme.typography.labelSmall, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 9.sp)
                                    }
                                }
                            }
                        } else {
                            Text("📍 ${tesla.location_name}", style = MaterialTheme.typography.labelSmall, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 9.sp, maxLines = 1)
                            Text("${String.format(Locale.US, "%.3f, %.3f", tesla.latitude, tesla.longitude)} · Today +${tesla.charge_energy_added_kwh} kWh", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 7.5.sp, maxLines = 1)
                        }
                    }
                }

                // Right Column: Native Google Maps with Live Tesla Marker
                Box(
                    modifier = Modifier
                        .weight(0.9f)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color(0xFF0D131D))
                        .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                ) {
                    val lat = tesla.latitude
                    val lng = tesla.longitude
                    val carLocation = remember(lat, lng) { LatLng(lat, lng) }
                    
                    val cameraPositionState = rememberCameraPositionState {
                        position = CameraPosition.Builder()
                            .target(carLocation)
                            .zoom(16.5f)
                            .tilt(35f)
                            .build()
                    }

                    // Force camera update whenever vehicle location changes
                    LaunchedEffect(lat, lng) {
                        cameraPositionState.position = CameraPosition.Builder()
                            .target(LatLng(lat, lng))
                            .zoom(16.5f)
                            .tilt(35f)
                            .build()
                    }

                    GoogleMap(
                        modifier = Modifier.fillMaxSize(),
                        cameraPositionState = cameraPositionState,
                        properties = MapProperties(
                            mapType = MapType.HYBRID,
                            isMyLocationEnabled = false
                        ),
                        uiSettings = MapUiSettings(
                            zoomControlsEnabled = false,
                            compassEnabled = false,
                            myLocationButtonEnabled = false,
                            mapToolbarEnabled = false,
                            rotationGesturesEnabled = true,
                            tiltGesturesEnabled = true,
                            zoomGesturesEnabled = true,
                            scrollGesturesEnabled = true
                        )
                    ) {
                        Marker(
                            state = MarkerState(position = carLocation),
                            title = tesla.car_name,
                            snippet = tesla.location_name
                        )
                    }

                    // Map Overlay Status Badges
                    Column(
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(6.dp)
                    ) {
                        Text(
                            text = "GOOGLE MAPS GPS",
                            style = MaterialTheme.typography.labelSmall,
                            color = BatteryGreen,
                            fontSize = 7.sp,
                            fontWeight = FontWeight.Black,
                            letterSpacing = 1.sp
                        )
                    }

                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(6.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color.Black.copy(alpha = 0.75f))
                            .padding(horizontal = 5.dp, vertical = 2.5.dp)
                    ) {
                        Text(
                            text = if (tesla.location_name.contains("Driving")) "MOVING" else "PARKED",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White.copy(alpha = 0.9f),
                            fontSize = 7.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

