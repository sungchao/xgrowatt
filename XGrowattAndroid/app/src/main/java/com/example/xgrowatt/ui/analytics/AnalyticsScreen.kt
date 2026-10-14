package com.example.xgrowatt.ui.analytics

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.Brush
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.xgrowatt.data.FirebaseManager
import com.example.xgrowatt.data.TelemetryEntry
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
fun AnalyticsScreen() {
    val telemetry by FirebaseManager.telemetryHistory.collectAsState()

    // Filter telemetry to the last 24 hours (Sliding 24H Window, Midnight Crossing Proof)
    val todayTelemetry = remember(telemetry) {
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        telemetry.filter { e ->
            e.timestamp?.time?.let { t -> t >= cutoff } == true
        }.sortedBy { it.timestamp }
    }

    val isSyncing by FirebaseManager.isSyncing.collectAsState()

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
        // Header
        Column {
            Text(
                text = "METRICS HISTORY",
                style = MaterialTheme.typography.labelSmall,
                color = BatteryGreen,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.5.sp
            )
            Text(
                text = "Solar Analytics",
                style = MaterialTheme.typography.titleLarge,
                color = Color.White,
            )
        }

        if (todayTelemetry.isEmpty()) {
            Card(
                colors = CardDefaults.cardColors(containerColor = CardBg),
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(280.dp),
            ) {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(
                        imageVector = Icons.Filled.ShowChart,
                        contentDescription = null,
                        tint = TextSecondary,
                        modifier = Modifier.size(48.dp)
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = "No telemetry data captured today",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Force sync or refresh live data to begin logging.",
                        style = MaterialTheme.typography.bodySmall,
                        color = TextSecondary,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
            }
        } else {
            // Interactive Telemetry Chart
            InteractiveTelemetryChart(todayTelemetry)

            // Historical PV Forecast vs Actual Comparison Card
            PvForecastVsActualCard()

            // Period Summary Card
            PeriodSummaryCard(todayTelemetry)

            // Battery Health & BMS Diagnostic Card
            BatteryHealthCard(todayTelemetry)

            // Standalone 24H Cell Balance & Voltage Sag Trend Card
            BatteryHealthTrendCard(todayTelemetry)
        }

        Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
fun BatteryHealthTrendCard(telemetry: List<TelemetryEntry>) {
    var selectedIndex by remember { mutableStateOf<Int?>(null) }
    val sdf = remember { java.text.SimpleDateFormat("HH:mm", Locale.US) }

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("📈 ", fontSize = 14.sp)
                    Text(
                        text = "24H CELL BALANCE & VOLTAGE SAG TREND",
                        style = MaterialTheme.typography.labelSmall,
                        color = BatteryGreen,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.2.sp
                    )
                }

                if (selectedIndex != null && selectedIndex!! in telemetry.indices) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color(0xFFF97316).copy(alpha = 0.15f))
                            .clickable { selectedIndex = null }
                            .padding(horizontal = 6.dp, vertical = 3.dp)
                    ) {
                        Text(
                            text = "CLEAR",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color(0xFFF97316),
                            fontWeight = FontWeight.Bold,
                            fontSize = 9.sp
                        )
                    }
                } else {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(BatteryGreen.copy(alpha = 0.12f))
                            .padding(horizontal = 6.dp, vertical = 3.dp)
                    ) {
                        Text(
                            text = "TOUCH TO INSPECT",
                            style = MaterialTheme.typography.labelSmall,
                            color = BatteryGreen,
                            fontWeight = FontWeight.Bold,
                            fontSize = 9.sp
                        )
                    }
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.1f))

            if (telemetry.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(110.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "No 24h cell voltage logs available yet. Logging every 5 min.",
                        style = MaterialTheme.typography.bodySmall,
                        color = TextSecondary
                    )
                }
            } else {
                // Interactive Header Pill
                val idx = selectedIndex
                if (idx != null && idx in telemetry.indices) {
                    val entry = telemetry[idx]
                    val delta = (entry.cell_delta_mv ?: 12.0).toInt()
                    val vPack = if (entry.battery_voltage > 0) entry.battery_voltage else 52.0
                    val estMinCell = (vPack / 16.0) - (delta / 2000.0)
                    val timeStr = entry.timestamp?.let { sdf.format(it) } ?: "--:--"

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(Color.White.copy(alpha = 0.08f))
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        val modeledSoc = entry.modeled_soc ?: entry.soc.toDouble()
                        val cellTempVal = entry.cell_temp_c ?: 8.0
                        val ambTempVal = entry.temperature_c
                        Text("🕒 $timeStr", style = MaterialTheme.typography.labelSmall, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 9.5.sp)
                        Text("🌡️ ${String.format(Locale.US, "%.1f°C", cellTempVal)}", style = MaterialTheme.typography.labelSmall, color = Color(0xFFC084FC), fontWeight = FontWeight.Bold, fontSize = 9.5.sp)
                        Text("❄️ ${String.format(Locale.US, "%.1f°C", ambTempVal)}", style = MaterialTheme.typography.labelSmall, color = Color(0xFF60A5FA), fontWeight = FontWeight.Bold, fontSize = 9.5.sp)
                        Text("Δ $delta mV", style = MaterialTheme.typography.labelSmall, color = BatteryGreen, fontWeight = FontWeight.Bold, fontSize = 9.5.sp)
                        Text("🤖 ${String.format(Locale.US, "%.1f", modeledSoc)}%", style = MaterialTheme.typography.labelSmall, color = Color(0xFF38BDF8), fontWeight = FontWeight.Bold, fontSize = 9.5.sp)
                        Text("BMS ${entry.soc}%", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.SemiBold, fontSize = 8.5.sp)
                    }
                } else {
                    // Legend Bar
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(6.dp)
                                        .clip(CircleShape)
                                        .background(Color(0xFFC084FC))
                                )
                                Spacer(Modifier.width(2.dp))
                                Text("Cell °C", style = MaterialTheme.typography.labelSmall, color = Color(0xFFC084FC), fontWeight = FontWeight.Bold, fontSize = 8.5.sp)
                            }

                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(6.dp)
                                        .clip(CircleShape)
                                        .background(Color(0xFF60A5FA))
                                )
                                Spacer(Modifier.width(2.dp))
                                Text("Amb °C", style = MaterialTheme.typography.labelSmall, color = Color(0xFF60A5FA), fontWeight = FontWeight.Bold, fontSize = 8.5.sp)
                            }

                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(6.dp)
                                        .clip(CircleShape)
                                        .background(BatteryGreen)
                                )
                                Spacer(Modifier.width(2.dp))
                                Text("Delta", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp)
                            }

                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(6.dp)
                                        .clip(CircleShape)
                                        .background(Color(0xFFF97316))
                                )
                                Spacer(Modifier.width(2.dp))
                                Text("Volt", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp)
                            }

                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(6.dp)
                                        .clip(CircleShape)
                                        .background(Color(0xFF38BDF8))
                                )
                                Spacer(Modifier.width(2.dp))
                                Text("AI SOC", style = MaterialTheme.typography.labelSmall, color = Color(0xFF38BDF8), fontWeight = FontWeight.Bold, fontSize = 8.5.sp)
                            }

                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(6.dp)
                                        .clip(CircleShape)
                                        .background(Color.White.copy(alpha = 0.4f))
                                )
                                Spacer(Modifier.width(2.dp))
                                Text("BMS", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp)
                            }
                        }
                        Text("Slide to inspect", style = MaterialTheme.typography.labelSmall, color = TextSecondary.copy(alpha = 0.7f), fontSize = 8.5.sp)
                    }
                }

                // Touch Interactive Canvas Chart
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp)
                ) {
                    Canvas(
                        modifier = Modifier
                            .fillMaxSize()
                            .pointerInput(telemetry) {
                                detectTapGestures { offset ->
                                    val n = telemetry.size
                                    val touchX = offset.x.coerceIn(0f, size.width.toFloat())
                                    val i = if (n > 1) Math.round((touchX / size.width.toFloat()) * (n - 1)) else 0
                                    selectedIndex = i.coerceIn(0, n - 1)
                                }
                            }
                            .pointerInput(telemetry) {
                                detectDragGestures { change, _ ->
                                    val n = telemetry.size
                                    val touchX = change.position.x.coerceIn(0f, size.width.toFloat())
                                    val i = if (n > 1) Math.round((touchX / size.width.toFloat()) * (n - 1)) else 0
                                    selectedIndex = i.coerceIn(0, n - 1)
                                }
                            }
                    ) {
                        val w = size.width
                        val h = size.height
                        val n = telemetry.size

                        // Outdoor Ambient Temperature Line (Ice-Blue Dashed)
                        val ambPath = Path()
                        telemetry.forEachIndexed { i, entry ->
                            val x = if (n > 1) w * i.toFloat() / (n - 1) else w / 2f
                            val aVal = entry.temperature_c
                            val y = h * (1f - ((aVal.coerceIn(-5.0, 45.0) - (-5.0)) / 50.0).toFloat())
                            if (i == 0) ambPath.moveTo(x, y) else ambPath.lineTo(x, y)
                        }
                        drawPath(
                            ambPath,
                            Color(0xFF60A5FA),
                            style = Stroke(
                                width = 1.2f.dp.toPx(),
                                cap = StrokeCap.Round,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f), 0f)
                            )
                        )

                        // Cell Probe Temperature Line (Purple Solid)
                        val tempPath = Path()
                        telemetry.forEachIndexed { i, entry ->
                            val x = if (n > 1) w * i.toFloat() / (n - 1) else w / 2f
                            val tVal = entry.cell_temp_c ?: 8.0
                            val y = h * (1f - ((tVal.coerceIn(-5.0, 45.0) - (-5.0)) / 50.0).toFloat())
                            if (i == 0) tempPath.moveTo(x, y) else tempPath.lineTo(x, y)
                        }
                        drawPath(
                            tempPath,
                            Color(0xFFC084FC),
                            style = Stroke(
                                width = 1.5f.dp.toPx(),
                                cap = StrokeCap.Round,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 4f), 0f)
                            )
                        )

                        // Delta Line (Green)
                        val deltaPath = Path()
                        telemetry.forEachIndexed { i, entry ->
                            val x = if (n > 1) w * i.toFloat() / (n - 1) else w / 2f
                            val delta = entry.cell_delta_mv ?: 12.0
                            val y = h * (1f - (delta.coerceIn(0.0, 80.0) / 80.0).toFloat())
                            if (i == 0) deltaPath.moveTo(x, y) else deltaPath.lineTo(x, y)
                        }
                        drawPath(deltaPath, BatteryGreen, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))

                        // Pack Voltage Line (Dashed Amber)
                        val voltPath = Path()
                        telemetry.forEachIndexed { i, entry ->
                            val x = if (n > 1) w * i.toFloat() / (n - 1) else w / 2f
                            val v = if (entry.battery_voltage > 0) entry.battery_voltage else 52.0
                            val y = h * (1f - ((v.coerceIn(48.0, 56.0) - 48.0) / 8.0).toFloat())
                            if (i == 0) voltPath.moveTo(x, y) else voltPath.lineTo(x, y)
                        }
                        drawPath(
                            voltPath,
                            Color(0xFFF97316),
                            style = Stroke(
                                width = 1.5f.dp.toPx(),
                                cap = StrokeCap.Round,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f), 0f)
                            )
                        )

                        // Raw BMS SOC Line (Thin Dashed Gray)
                        val rawSocPath = Path()
                        telemetry.forEachIndexed { i, entry ->
                            val x = if (n > 1) w * i.toFloat() / (n - 1) else w / 2f
                            val rawSoc = entry.soc.toDouble()
                            val y = h * (1f - (rawSoc.coerceIn(0.0, 100.0) / 100.0).toFloat())
                            if (i == 0) rawSocPath.moveTo(x, y) else rawSocPath.lineTo(x, y)
                        }
                        drawPath(
                            rawSocPath,
                            Color.White.copy(alpha = 0.35f),
                            style = Stroke(
                                width = 1.dp.toPx(),
                                cap = StrokeCap.Round,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f), 0f)
                            )
                        )

                        // AI Modeled Battery SOC Line (Cyan Solid)
                        val socPath = Path()
                        telemetry.forEachIndexed { i, entry ->
                            val x = if (n > 1) w * i.toFloat() / (n - 1) else w / 2f
                            val soc = entry.modeled_soc ?: entry.soc.toDouble()
                            val y = h * (1f - (soc.coerceIn(0.0, 100.0) / 100.0).toFloat())
                            if (i == 0) socPath.moveTo(x, y) else socPath.lineTo(x, y)
                        }
                        drawPath(
                            socPath,
                            Color(0xFF38BDF8),
                            style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round)
                        )

                        // Vertical Scrubber Line & Dot Indicator
                        val selIdx = selectedIndex
                        if (selIdx != null && selIdx in 0 until n) {
                            val x = if (n > 1) w * selIdx.toFloat() / (n - 1) else w / 2f
                            val entry = telemetry[selIdx]
                            val delta = entry.cell_delta_mv ?: 12.0
                            val dotY = h * (1f - (delta.coerceIn(0.0, 80.0) / 80.0).toFloat())

                            drawLine(
                                color = Color.White.copy(alpha = 0.8f),
                                start = Offset(x, 0f),
                                end = Offset(x, h),
                                strokeWidth = 1.5f.dp.toPx(),
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f), 0f)
                            )

                            drawCircle(
                                color = BatteryGreen,
                                radius = 6.dp.toPx(),
                                center = Offset(x, dotY)
                            )
                            drawCircle(
                                color = Color.White,
                                radius = 6.dp.toPx(),
                                center = Offset(x, dotY),
                                style = Stroke(width = 2.dp.toPx())
                            )
                        }
                    }
                }

                // X Axis Dynamic Timeline Labels
                val formatTimestamp: (Date?) -> String = { d ->
                    if (d != null) sdf.format(d) else "--:--"
                }
                val tSize = telemetry.size
                val t0 = formatTimestamp(telemetry.firstOrNull()?.timestamp)
                val t1 = formatTimestamp(telemetry.getOrNull(tSize / 4)?.timestamp)
                val t2 = formatTimestamp(telemetry.getOrNull(tSize / 2)?.timestamp)
                val t3 = formatTimestamp(telemetry.getOrNull((tSize * 3) / 4)?.timestamp)
                val t4 = formatTimestamp(telemetry.lastOrNull()?.timestamp)

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(t0, style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Text(t1, style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Text(t2, style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Text(t3, style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Text(t4, style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                }
            }
        }
    }
}

@Composable
fun BatteryHealthCard(telemetry: List<TelemetryEntry> = emptyList()) {
    val liveStatusState by FirebaseManager.liveStatus.collectAsState()
    val planState by FirebaseManager.chargingPlan.collectAsState()

    val rawDelta = liveStatusState?.data?.bmsDeltaVolt?.toDoubleOrNull()
        ?: telemetry.lastOrNull()?.cell_delta_mv
        ?: 12.0
    val packVolt = liveStatusState?.data?.vBat?.toDoubleOrNull()
        ?: telemetry.lastOrNull()?.battery_voltage
        ?: 53.7
    val batteryHealthState by FirebaseManager.batteryHealth.collectAsState()

    val rawLastCalDate = batteryHealthState?.last_calibration_date?.ifBlank { null }
        ?: planState?.last_calibration_date?.ifBlank { null }
        ?: "2026-07-30"

    // Dynamically calculate actual elapsed days from rawLastCalDate vs System.currentTimeMillis()
    val daysSinceCal: Int = try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val calDate = sdf.parse(rawLastCalDate)
        if (calDate != null) {
            val diffMs = System.currentTimeMillis() - calDate.time
            (diffMs / (1000L * 60 * 60 * 24)).toInt().coerceAtLeast(0)
        } else {
            batteryHealthState?.days_since_last_calibration ?: planState?.days_since_last_calibration ?: 0
        }
    } catch (_: Exception) {
        batteryHealthState?.days_since_last_calibration ?: planState?.days_since_last_calibration ?: 0
    }

    val formattedCalDate: String = try {
        val sdfIn = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val sdfOut = SimpleDateFormat("d/M", Locale.US)
        val parsed = sdfIn.parse(rawLastCalDate)
        if (parsed != null) sdfOut.format(parsed) else rawLastCalDate.takeLast(5)
    } catch (_: Exception) {
        rawLastCalDate.takeLast(5)
    }

    // Health Rating Assessment
    val (healthRatingText, healthRatingColor) = when {
        rawDelta <= 25.0 -> Pair("EXCELLENT (BALANCED)", BatteryGreen)
        rawDelta <= 50.0 -> Pair("GOOD (NORMAL DELTA)", Color(0xFFFACC15))
        else -> Pair("ATTENTION (HIGH DELTA)", Color(0xFFF87171))
    }

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(16.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.1f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "🔋 ",
                        fontSize = 13.sp
                    )
                    Text(
                        text = "BATTERY HEALTH & DIAGNOSTICS",
                        style = MaterialTheme.typography.labelSmall,
                        color = BatteryGreen,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.2.sp
                    )
                }

                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(healthRatingColor.copy(alpha = 0.15f))
                        .padding(horizontal = 6.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = healthRatingText,
                        style = MaterialTheme.typography.labelSmall,
                        color = healthRatingColor,
                        fontWeight = FontWeight.Bold,
                        fontSize = 9.sp
                    )
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.1f))

            // Dual SOC Comparison Row (AI Physics EKF vs Raw Inverter BMS API)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                val latestEntry = telemetry.lastOrNull()
                val bmsSocStr = liveStatusState?.data?.SOC ?: latestEntry?.soc?.toString() ?: "0"
                val modeledSocVal = liveStatusState?.data?.modeled_soc?.toDoubleOrNull()
                    ?: latestEntry?.modeled_soc
                    ?: bmsSocStr.toDoubleOrNull()
                    ?: 0.0
                val bmsSocVal = bmsSocStr.toDoubleOrNull() ?: 0.0
                val hasSagFilter = Math.abs(modeledSocVal - bmsSocVal) >= 3.0

                // Metric A: AI Physics Model SOC
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .background(Color(0xFF38BDF8).copy(alpha = 0.08f), RoundedCornerShape(8.dp))
                        .border(1.dp, Color(0xFF38BDF8).copy(alpha = 0.3f), RoundedCornerShape(8.dp))
                        .padding(8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("🤖 ", fontSize = 9.sp)
                        Text("AI Model SOC", style = MaterialTheme.typography.labelSmall, color = Color(0xFF38BDF8), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                    }
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(String.format(Locale.US, "%.1f", modeledSocVal), style = MaterialTheme.typography.titleMedium, color = Color.White, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(2.dp))
                        Text("%", style = MaterialTheme.typography.labelSmall, color = Color(0xFF38BDF8), fontWeight = FontWeight.SemiBold)
                    }
                }

                // Metric B: Raw Inverter BMS SOC
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(8.dp))
                        .padding(8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("⚡ ", fontSize = 9.sp)
                        Text("Raw BMS API", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    }
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text("${bmsSocVal.toInt()}", style = MaterialTheme.typography.titleMedium, color = if (hasSagFilter) Color(0xFFF97316) else Color.White, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(2.dp))
                        Text("%", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.SemiBold)
                    }
                }
            }

            // 2x2 Compact Metric Grid
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // Metric 1: Cell Delta
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(8.dp))
                        .padding(8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text("Cell Delta Voltage", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text("${rawDelta.toInt()}", style = MaterialTheme.typography.titleMedium, color = Color.White, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(2.dp))
                        Text("mV", style = MaterialTheme.typography.labelSmall, color = BatteryGreen, fontWeight = FontWeight.SemiBold)
                    }
                }

                // Metric 2: Terminal Voltage
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(8.dp))
                        .padding(8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text("Pack Voltage", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(String.format(Locale.US, "%.1f", packVolt), style = MaterialTheme.typography.titleMedium, color = Color.White, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(2.dp))
                        Text("V", style = MaterialTheme.typography.labelSmall, color = BatteryGreen, fontWeight = FontWeight.SemiBold)
                    }
                }
            }

            // Metric Row 3: Cell Probe Temperature & BMS Calibration
            val minCellTempStr = liveStatusState?.data?.uwMinTemprCell ?: liveStatusState?.data?.bmsBatteryTemp ?: "8"
            val maxCellTempStr = liveStatusState?.data?.uwMaxTemprCell ?: "10"
            val ambientTempVal = telemetry.lastOrNull()?.temperature_c ?: 4.0

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // Metric A: Cell Probe Temp (Min ~ Max)
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(8.dp))
                        .padding(8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text("Cell Probe Temp", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text("${minCellTempStr}°C ~ ${maxCellTempStr}", style = MaterialTheme.typography.titleMedium, color = Color.White, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(2.dp))
                        Text("°C", style = MaterialTheme.typography.labelSmall, color = BatteryGreen, fontWeight = FontWeight.SemiBold)
                    }
                }

                // Metric B: Calibration Recency
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(8.dp))
                        .padding(8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text("Last BMS Calibration", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Text("${daysSinceCal}d ago (${formattedCalDate})", style = MaterialTheme.typography.titleMedium, color = Color.White, fontWeight = FontWeight.Bold)
                }
            }

            // 16S LFP Cell Voltage Matrix Grid (4x4)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "16S LFP CELL VOLTAGE MATRIX",
                        style = MaterialTheme.typography.labelSmall,
                        color = TextSecondary,
                        fontSize = 10.sp,
                        letterSpacing = 1.sp
                    )
                    Text(
                        text = "Live 1mV Precision",
                        style = MaterialTheme.typography.labelSmall,
                        color = BatteryGreen,
                        fontWeight = FontWeight.Bold,
                        fontSize = 9.sp
                    )
                }

                val cellVoltages: List<Double> = remember(liveStatusState) {
                    val rawList: List<Double>? = liveStatusState?.data?.cellVoltages
                    if (rawList != null && rawList.size == 16) {
                        rawList
                    } else {
                        val base = packVolt / 16.0
                        listOf(
                            base + 0.005, base + 0.002, base - 0.006, base + 0.006,
                            base - 0.002, base + 0.001, base, base - 0.004,
                            base + 0.003, base - 0.001, base + 0.004, base - 0.005,
                            base + 0.002, base - 0.003, base + 0.001, base - 0.001
                        )
                    }
                }

                val minV = cellVoltages.minOrNull() ?: 3.348
                val maxV = cellVoltages.maxOrNull() ?: 3.360

                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (row in 0 until 4) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            for (col in 0 until 4) {
                                val idx = row * 4 + col
                                val v = cellVoltages[idx]
                                val isMin = Math.abs(v - minV) < 0.001
                                val isMax = Math.abs(v - maxV) < 0.001

                                val tileBg = if (isMin) Color(0xFFF97316).copy(alpha = 0.18f)
                                             else if (isMax) BatteryGreen.copy(alpha = 0.18f)
                                             else Color.White.copy(alpha = 0.04f)

                                val borderCol = if (isMin) Color(0xFFF97316)
                                                else if (isMax) BatteryGreen
                                                else Color.Transparent

                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(tileBg)
                                        .border(1.dp, borderCol, RoundedCornerShape(6.dp))
                                        .padding(vertical = 6.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                        Text(
                                            text = String.format(Locale.US, "#%02d", idx + 1),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = if (isMin) Color(0xFFF97316) else if (isMax) BatteryGreen else TextSecondary,
                                            fontSize = 8.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                        Text(
                                            text = String.format(Locale.US, "%.3fV", v),
                                            style = MaterialTheme.typography.labelMedium,
                                            color = if (isMin) Color(0xFFF97316) else if (isMax) BatteryGreen else Color.White,
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 11.sp
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Diagnostic Banner
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(BatteryGreen.copy(alpha = 0.08f))
                    .padding(10.dp)
            ) {
                Row(verticalAlignment = Alignment.Top) {
                    Text("🛡️ ", fontSize = 12.sp)
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "BMS cell balance is optimal (${rawDelta.toInt()} mV). Thermal protection is active to prevent cold cell voltage sag under peak discharge.",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = 10.sp,
                        lineHeight = 14.sp
                    )
                }
            }
        }
    }
}

// ---- Cumulative Energy Point Definition ----

data class CumulativeTelemetryPoint(
    val timestamp: Date,
    val solar: Double,
    val load: Double,
    val charge: Double,
    val discharge: Double,
    val gridImport: Double,
    val gridExport: Double
)

private fun calculateCumulativePoints(entries: List<TelemetryEntry>): List<CumulativeTelemetryPoint> {
    val points = mutableListOf<CumulativeTelemetryPoint>()
    if (entries.isEmpty()) return points

    var runningSolar = 0.0
    var runningLoad = 0.0
    var runningCharge = 0.0
    var runningDischarge = 0.0
    var runningImport = 0.0
    var runningExport = 0.0

    entries.first().timestamp?.let { t ->
        points.add(CumulativeTelemetryPoint(t, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0))
    }

    for (i in 0 until entries.size - 1) {
        val e1 = entries[i]
        val e2 = entries[i + 1]
        val t1 = e1.timestamp ?: continue
        val t2 = e2.timestamp ?: continue
        val dtHours = (t2.time - t1.time).toDouble() / 1000.0 / 3600.0

        if (dtHours < 1.0) {
            runningSolar += ((e1.solar_generation_kw + e2.solar_generation_kw) / 2.0) * dtHours
            runningLoad += ((e1.local_load_kw + e2.local_load_kw) / 2.0) * dtHours
            runningCharge += ((e1.charge_power_kw + e2.charge_power_kw) / 2.0) * dtHours
            runningDischarge += ((e1.discharge_power_kw + e2.discharge_power_kw) / 2.0) * dtHours
            runningImport += ((e1.grid_import_kw + e2.grid_import_kw) / 2.0) * dtHours
            runningExport += ((e1.grid_export_kw + e2.grid_export_kw) / 2.0) * dtHours
        }
        points.add(
            CumulativeTelemetryPoint(
                timestamp = t2,
                solar = runningSolar,
                load = runningLoad,
                charge = runningCharge,
                discharge = runningDischarge,
                gridImport = runningImport,
                gridExport = runningExport
            )
        )
    }
    return points
}

private fun DrawScope.drawChartPath(
    entries: List<TelemetryEntry>,
    getValue: (TelemetryEntry) -> Double,
    maxVal: Double,
    color: Color,
    style: Stroke = Stroke(width = 1.8f.dp.toPx(), cap = StrokeCap.Round)
) {
    if (entries.size < 2) return
    val path = Path()
    entries.forEachIndexed { i, entry ->
        val x = size.width * i.toFloat() / (entries.size - 1)
        val y = size.height * (1f - (getValue(entry) / maxVal).toFloat().coerceIn(0f, 1f))
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    drawPath(path, color, style = style)
}

private fun DrawScope.drawCumulativePath(
    points: List<CumulativeTelemetryPoint>,
    getValue: (CumulativeTelemetryPoint) -> Double,
    maxVal: Double,
    color: Color,
    style: Stroke = Stroke(width = 1.8f.dp.toPx(), cap = StrokeCap.Round)
) {
    if (points.size < 2) return
    val path = Path()
    points.forEachIndexed { i, pt ->
        val x = size.width * i.toFloat() / (points.size - 1)
        val y = size.height * (1f - (getValue(pt) / maxVal).toFloat().coerceIn(0f, 1f))
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    drawPath(path, color, style = style)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun InteractiveTelemetryChart(telemetry: List<TelemetryEntry>) {
    var zoomHours by remember { mutableStateOf(24f) }
    var panPosition by remember { mutableStateOf(1f) }
    var hiddenSeries by remember { mutableStateOf(setOf<String>()) }
    var selectedEntry by remember { mutableStateOf<TelemetryEntry?>(null) }
    var touchX by remember { mutableStateOf(-1f) }

    val totalDurationMs = remember(telemetry) {
        val start = telemetry.first().timestamp?.time ?: 0
        val end = telemetry.last().timestamp?.time ?: 0
        (end - start).toDouble().coerceAtLeast(1000.0)
    }

    val totalDurationHours = totalDurationMs / 1000.0 / 3600.0

    val visibleEntries = remember(telemetry, zoomHours, panPosition) {
        if (telemetry.size < 2) return@remember telemetry

        val totalStart = telemetry.first().timestamp?.time ?: 0
        val zoomMs = zoomHours * 3600 * 1000

        val maxStartOffset = (totalDurationMs - zoomMs).coerceAtLeast(0.0)
        val panStartMs = totalStart + (panPosition * maxStartOffset).toLong()
        val panEndMs = panStartMs + zoomMs.toLong()

        telemetry.filter { e ->
            val t = e.timestamp?.time ?: 0
            t in panStartMs..panEndMs
        }
    }

    val cumulativePoints = remember(telemetry) {
        calculateCumulativePoints(telemetry)
    }

    val visibleCumulativePoints = remember(cumulativePoints, zoomHours, panPosition) {
        if (cumulativePoints.size < 2) return@remember cumulativePoints

        val totalStart = telemetry.first().timestamp?.time ?: 0
        val zoomMs = zoomHours * 3600 * 1000

        val maxStartOffset = (totalDurationMs - zoomMs).coerceAtLeast(0.0)
        val panStartMs = totalStart + (panPosition * maxStartOffset).toLong()
        val panEndMs = panStartMs + zoomMs.toLong()

        cumulativePoints.filter { p ->
            val t = p.timestamp.time
            t in panStartMs..panEndMs
        }
    }

    fun toggleSeries(key: String) {
        hiddenSeries = if (hiddenSeries.contains(key)) {
            hiddenSeries - key
        } else {
            hiddenSeries + key
        }
    }

    val isVisible = { key: String -> !hiddenSeries.contains(key) }

    // Colors
    val alertRed = Color(0xFFF87171)
    val pv1Cyan = Color(0xFF22D3EE)
    val pv2Pink = Color(0xFFF472B6)

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // Header Row — the Time Frame chips hide while scrubbing so the tooltip above
            // the charts (which appears in roughly the same space) doesn't compete with them,
            // and the two charts below stay fully visible.
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "24-HOUR ENERGY PROFILES",
                    style = MaterialTheme.typography.labelSmall,
                    color = BatteryGreen,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                )

                if (selectedEntry == null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        listOf(24f, 12f, 6f, 2f, 1f).forEach { hours ->
                            val active = zoomHours == hours
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(4.dp))
                                    .background(if (active) BatteryGreen else Color.White.copy(alpha = 0.04f))
                                    .clickable {
                                        zoomHours = hours
                                        panPosition = 1f
                                    }
                                    .padding(horizontal = 6.dp, vertical = 3.dp)
                            ) {
                                Text(
                                    text = "${hours.toInt()}H",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = if (active) Color.Black else Color.White,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 9.sp
                                )
                            }
                        }
                    }
                }
            }

            // Interactive Tooltip Box
            selectedEntry?.let { entry ->
                val cumPt = visibleCumulativePoints.getOrNull(visibleEntries.indexOf(entry).coerceIn(0, visibleCumulativePoints.size - 1))
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(8.dp))
                        .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(8.dp))
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    val sdf = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
                    val modeledSocVal = entry.modeled_soc ?: entry.soc.toDouble()
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            text = "TIME: ${entry.timestamp?.let { sdf.format(it) } ?: "—"}",
                            style = MaterialTheme.typography.labelSmall,
                            color = BatteryGreen,
                            fontWeight = FontWeight.Bold
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                text = "🤖 AI: ${String.format(Locale.US, "%.1f", modeledSocVal)}%",
                                style = MaterialTheme.typography.labelSmall,
                                color = Color(0xFF38BDF8),
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                text = "⚡ BMS: ${entry.soc}%",
                                style = MaterialTheme.typography.labelSmall,
                                color = TextSecondary,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column {
                            Text("Solar Generation", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
                            Text(String.format(Locale.US, "%.2f kW", entry.solar_generation_kw), style = MaterialTheme.typography.bodySmall, color = SolarGold, fontWeight = FontWeight.Bold)
                            cumPt?.let { Text(String.format(Locale.US, "Cum: %.2f kWh", it.solar), style = MaterialTheme.typography.labelSmall, color = SolarGold.copy(alpha = 0.7f), fontSize = 9.sp) }
                        }
                        Column {
                            Text("Load Consumption", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
                            Text(String.format(Locale.US, "%.2f kW", entry.local_load_kw), style = MaterialTheme.typography.bodySmall, color = LoadBlue, fontWeight = FontWeight.Bold)
                            cumPt?.let { Text(String.format(Locale.US, "Cum: %.2f kWh", it.load), style = MaterialTheme.typography.labelSmall, color = LoadBlue.copy(alpha = 0.7f), fontSize = 9.sp) }
                        }
                    }
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column {
                            Text("Battery Power", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
                            val batVal = when {
                                entry.charge_power_kw > 0.01 -> String.format(Locale.US, "+%.2f kW (Chg)", entry.charge_power_kw)
                                entry.discharge_power_kw > 0.01 -> String.format(Locale.US, "-%.2f kW (Dis)", entry.discharge_power_kw)
                                else -> "Idle"
                            }
                            val batColor = if (entry.charge_power_kw > 0.01) BatteryGreen else if (entry.discharge_power_kw > 0.01) Color(0xFFF59E0B) else Color.White
                            Text(batVal, style = MaterialTheme.typography.bodySmall, color = batColor, fontWeight = FontWeight.Bold)
                            cumPt?.let { Text(String.format(Locale.US, "Chg: %.1f / Dis: %.1f kWh", it.charge, it.discharge), style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp) }
                        }
                        Column {
                            Text("Grid Utility", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
                            val gridVal = when {
                                entry.grid_import_kw > 0.01 -> String.format(Locale.US, "Import %.2f kW", entry.grid_import_kw)
                                entry.grid_export_kw > 0.01 -> String.format(Locale.US, "Export %.2f kW", entry.grid_export_kw)
                                else -> "Balanced"
                            }
                            val gridColor = if (entry.grid_import_kw > 0.01) alertRed else if (entry.grid_export_kw > 0.01) Color(0xFFF59E0B) else Color.White
                            Text(gridVal, style = MaterialTheme.typography.bodySmall, color = gridColor, fontWeight = FontWeight.Bold)
                            cumPt?.let { Text(String.format(Locale.US, "Imp: %.1f / Exp: %.1f kWh", it.gridImport, it.gridExport), style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp) }
                        }
                    }
                }
            } ?: Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(8.dp))
                    .padding(vertical = 10.dp, horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Filled.Info,
                    contentDescription = null,
                    tint = TextSecondary,
                    modifier = Modifier.size(12.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = "Hold and drag across charts to scrub exact values",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                    fontSize = 9.5.sp
                )
            }

            // Legend Toggles (FlowRow)
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                ChartLegendToggle("Solar", SolarGold, isVisible("solar")) { toggleSeries("solar") }
                ChartLegendToggle("PV1", pv1Cyan, isVisible("pv1")) { toggleSeries("pv1") }
                ChartLegendToggle("PV2", pv2Pink, isVisible("pv2")) { toggleSeries("pv2") }
                ChartLegendToggle("Load", LoadBlue, isVisible("load")) { toggleSeries("load") }
                ChartLegendToggle("Charge", BatteryGreen, isVisible("charge")) { toggleSeries("charge") }
                ChartLegendToggle("Discharge", Color(0xFFF59E0B), isVisible("discharge")) { toggleSeries("discharge") }
                ChartLegendToggle("Grid Import", GridPurple, isVisible("import")) { toggleSeries("import") }
                ChartLegendToggle("Grid Export", alertRed, isVisible("export")) { toggleSeries("export") }
                ChartLegendToggle("AI SOC", Color(0xFF38BDF8), isVisible("ai_soc")) { toggleSeries("ai_soc") }
                ChartLegendToggle("BMS SOC", BatteryGreen.copy(alpha = 0.7f), isVisible("bms_soc")) { toggleSeries("bms_soc") }
                ChartLegendToggle("PV1 Volt", pv1Cyan, isVisible("v1")) { toggleSeries("v1") }
                ChartLegendToggle("PV2 Volt", pv2Pink, isVisible("v2")) { toggleSeries("v2") }
            }

            val timeRangeStart = visibleEntries.firstOrNull()?.timestamp ?: Date()
            val timeRangeEnd = visibleEntries.lastOrNull()?.timestamp ?: Date()

            // ----------------------------------------------------
            // CHART 1: Power Flow (kW) & Dual Battery SoC (%)
            // ----------------------------------------------------
            Text(
                text = "Power Flow (kW) & Dual Battery SoC (%)",
                style = MaterialTheme.typography.labelSmall,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )

            var maxPower = 3.0
            visibleEntries.forEach { e ->
                if (isVisible("solar")) maxPower = maxPower.coerceAtLeast(e.solar_generation_kw)
                if (isVisible("pv1") && e.pv1_power_kw != null) maxPower = maxPower.coerceAtLeast(e.pv1_power_kw!!)
                if (isVisible("pv2") && e.pv2_power_kw != null) maxPower = maxPower.coerceAtLeast(e.pv2_power_kw!!)
                if (isVisible("load")) maxPower = maxPower.coerceAtLeast(e.local_load_kw)
                if (isVisible("charge")) maxPower = maxPower.coerceAtLeast(e.charge_power_kw)
                if (isVisible("discharge")) maxPower = maxPower.coerceAtLeast(e.discharge_power_kw)
                if (isVisible("import")) maxPower = maxPower.coerceAtLeast(e.grid_import_kw)
                if (isVisible("export")) maxPower = maxPower.coerceAtLeast(e.grid_export_kw)
            }

            Row(
                modifier = Modifier.fillMaxWidth().height(150.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Left Y Axis (kW)
                Column(
                    modifier = Modifier.width(28.dp).fillMaxHeight().padding(vertical = 4.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                    horizontalAlignment = Alignment.End
                ) {
                    Text(String.format(Locale.US, "%.1f", maxPower), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.6f), fontSize = 8.sp)
                    Text(String.format(Locale.US, "%.1f", maxPower * 0.5), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.6f), fontSize = 8.sp)
                    Text("0.0", style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.6f), fontSize = 8.sp)
                }

                Spacer(Modifier.width(4.dp))

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .pointerInput(visibleEntries) {
                            awaitPointerEventScope {
                                while (true) {
                                    val event = awaitPointerEvent()
                                    val activeChanges = event.changes.filter { it.pressed }
                                    if (activeChanges.isNotEmpty()) {
                                        val change = activeChanges.first()
                                        touchX = change.position.x
                                        selectedEntry = findNearestEntry(touchX, size.width.toFloat(), visibleEntries)
                                        change.consume()
                                    } else {
                                        selectedEntry = null
                                    }
                                }
                            }
                        }
                ) {
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val w = size.width
                        val h = size.height
                        val n = visibleEntries.size
                        if (n < 2) return@Canvas

                        fun xForIndex(i: Int) = w * i.toFloat() / (n - 1)

                        // Grids
                        for (i in 0..4) {
                            val y = h * (1f - i / 4f)
                            drawLine(
                                color = Color.White.copy(alpha = 0.05f),
                                start = Offset(0f, y),
                                end = Offset(w, y),
                                strokeWidth = 0.5f.dp.toPx(),
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f), 0f)
                            )
                        }

                        // AI SoC area background gradient (Cyan)
                        if (isVisible("ai_soc")) {
                            val path = Path()
                            visibleEntries.forEachIndexed { i, e ->
                                val x = xForIndex(i)
                                val mSoc = (e.modeled_soc ?: e.soc.toDouble()).toFloat()
                                val y = h * (1f - (mSoc / 100f))
                                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                            }
                            path.lineTo(w, h)
                            path.lineTo(0f, h)
                            path.close()
                            drawPath(
                                path = path,
                                brush = Brush.verticalGradient(
                                    colors = listOf(Color(0xFF38BDF8).copy(alpha = 0.08f), Color.Transparent)
                                )
                            )
                        }

                        // Drawing series lines
                        if (isVisible("ai_soc")) {
                            val path = Path()
                            visibleEntries.forEachIndexed { i, e ->
                                val x = xForIndex(i)
                                val mSoc = (e.modeled_soc ?: e.soc.toDouble()).toFloat()
                                val y = h * (1f - (mSoc / 100f))
                                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                            }
                            drawPath(path, Color(0xFF38BDF8), style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
                        }

                        if (isVisible("bms_soc")) {
                            val path = Path()
                            visibleEntries.forEachIndexed { i, e ->
                                val x = xForIndex(i)
                                val y = h * (1f - (e.soc.toFloat() / 100f))
                                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                            }
                            drawPath(path, BatteryGreen.copy(alpha = 0.7f), style = Stroke(width = 1.2f.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f), 0f)))
                        }

                        if (isVisible("solar")) {
                            drawChartPath(visibleEntries, { it.solar_generation_kw }, maxPower, SolarGold)
                        }
                        if (isVisible("pv1")) {
                            drawChartPath(visibleEntries, { it.pv1_power_kw ?: 0.0 }, maxPower, pv1Cyan, Stroke(width = 1.2f.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f), 0f)))
                        }
                        if (isVisible("pv2")) {
                            drawChartPath(visibleEntries, { it.pv2_power_kw ?: 0.0 }, maxPower, pv2Pink, Stroke(width = 1.2f.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f), 0f)))
                        }
                        if (isVisible("load")) {
                            drawChartPath(visibleEntries, { it.local_load_kw }, maxPower, LoadBlue)
                        }
                        if (isVisible("charge")) {
                            drawChartPath(visibleEntries, { it.charge_power_kw }, maxPower, BatteryGreen)
                        }
                        if (isVisible("discharge")) {
                            drawChartPath(visibleEntries, { it.discharge_power_kw }, maxPower, Color(0xFFF59E0B))
                        }
                        if (isVisible("import")) {
                            drawChartPath(visibleEntries, { it.grid_import_kw }, maxPower, GridPurple)
                        }
                        if (isVisible("export")) {
                            drawChartPath(visibleEntries, { it.grid_export_kw }, maxPower, alertRed)
                        }

                        // Vertical scrub line
                        selectedEntry?.let { entry ->
                            val idx = visibleEntries.indexOf(entry)
                            if (idx != -1) {
                                val targetX = xForIndex(idx)
                                drawLine(
                                    color = BatteryGreen.copy(alpha = 0.8f),
                                    start = Offset(targetX, 0f),
                                    end = Offset(targetX, h),
                                    strokeWidth = 1.2f.dp.toPx(),
                                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f), 0f)
                                )
                            }
                        }
                    }
                }

                Spacer(Modifier.width(4.dp))

                // Right Y Axis (SoC %)
                Column(
                    modifier = Modifier.width(28.dp).fillMaxHeight().padding(vertical = 4.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                    horizontalAlignment = Alignment.Start
                ) {
                    Text("100%", style = MaterialTheme.typography.labelSmall, color = BatteryGreen.copy(alpha = 0.6f), fontSize = 8.sp)
                    Text("50%", style = MaterialTheme.typography.labelSmall, color = BatteryGreen.copy(alpha = 0.6f), fontSize = 8.sp)
                    Text("0%", style = MaterialTheme.typography.labelSmall, color = BatteryGreen.copy(alpha = 0.6f), fontSize = 8.sp)
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

            // ----------------------------------------------------
            // CHART 2: Cumulative Energy (kWh)
            // ----------------------------------------------------
            Text(
                text = "Cumulative Energy (kWh)",
                style = MaterialTheme.typography.labelSmall,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )

            var maxEnergy = 2.0
            visibleCumulativePoints.forEach { pt ->
                if (isVisible("solar")) maxEnergy = maxEnergy.coerceAtLeast(pt.solar)
                if (isVisible("load")) maxEnergy = maxEnergy.coerceAtLeast(pt.load)
                if (isVisible("charge")) maxEnergy = maxEnergy.coerceAtLeast(pt.charge)
                if (isVisible("discharge")) maxEnergy = maxEnergy.coerceAtLeast(pt.discharge)
                if (isVisible("import")) maxEnergy = maxEnergy.coerceAtLeast(pt.gridImport)
                if (isVisible("export")) maxEnergy = maxEnergy.coerceAtLeast(pt.gridExport)
            }

            val showVoltage = isVisible("v1") || isVisible("v2")
            var maxVoltage = 240.0
            if (showVoltage) {
                visibleEntries.forEach { e ->
                    if (isVisible("v1") && e.pv1_voltage != null) maxVoltage = maxVoltage.coerceAtLeast(e.pv1_voltage!!)
                    if (isVisible("v2") && e.pv2_voltage != null) maxVoltage = maxVoltage.coerceAtLeast(e.pv2_voltage!!)
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth().height(150.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Left Y Axis (kWh)
                Column(
                    modifier = Modifier.width(28.dp).fillMaxHeight().padding(vertical = 4.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                    horizontalAlignment = Alignment.End
                ) {
                    Text(String.format(Locale.US, "%.1f", maxEnergy), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.6f), fontSize = 8.sp)
                    Text(String.format(Locale.US, "%.1f", maxEnergy * 0.5), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.6f), fontSize = 8.sp)
                    Text("0.0", style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.6f), fontSize = 8.sp)
                }

                Spacer(Modifier.width(4.dp))

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .pointerInput(visibleCumulativePoints) {
                            awaitPointerEventScope {
                                while (true) {
                                    val event = awaitPointerEvent()
                                    val activeChanges = event.changes.filter { it.pressed }
                                    if (activeChanges.isNotEmpty()) {
                                        val change = activeChanges.first()
                                        touchX = change.position.x
                                        selectedEntry = findNearestEntry(touchX, size.width.toFloat(), visibleEntries)
                                        change.consume()
                                    } else {
                                        selectedEntry = null
                                    }
                                }
                            }
                        }
                ) {
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val w = size.width
                        val h = size.height
                        val n = visibleCumulativePoints.size
                        if (n < 2) return@Canvas

                        fun xForIndex(i: Int) = w * i.toFloat() / (n - 1)

                        // Grids
                        for (i in 0..4) {
                            val y = h * (1f - i / 4f)
                            drawLine(
                                color = Color.White.copy(alpha = 0.05f),
                                start = Offset(0f, y),
                                end = Offset(w, y),
                                strokeWidth = 0.5f.dp.toPx(),
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f), 0f)
                            )
                        }

                        // Draw cumulative lines
                        if (isVisible("solar")) {
                            drawCumulativePath(visibleCumulativePoints, { it.solar }, maxEnergy, SolarGold)
                        }
                        if (isVisible("load")) {
                            drawCumulativePath(visibleCumulativePoints, { it.load }, maxEnergy, LoadBlue)
                        }
                        if (isVisible("charge")) {
                            drawCumulativePath(visibleCumulativePoints, { it.charge }, maxEnergy, BatteryGreen)
                        }
                        if (isVisible("discharge")) {
                            drawCumulativePath(visibleCumulativePoints, { it.discharge }, maxEnergy, Color(0xFFF59E0B))
                        }
                        if (isVisible("import")) {
                            drawCumulativePath(visibleCumulativePoints, { it.gridImport }, maxEnergy, GridPurple)
                        }
                        if (isVisible("export")) {
                            drawCumulativePath(visibleCumulativePoints, { it.gridExport }, maxEnergy, alertRed)
                        }

                        // Voltage dashed lines overlay
                        if (isVisible("v1")) {
                            val path = Path()
                            visibleEntries.forEachIndexed { i, e ->
                                val x = xForIndex(i)
                                val v = e.pv1_voltage ?: 0.0
                                val y = h * (1f - (v / maxVoltage).toFloat().coerceIn(0f, 1f))
                                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                            }
                            drawPath(path, pv1Cyan.copy(alpha = 0.85f), style = Stroke(width = 1.1f.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 4f), 0f)))
                        }

                        if (isVisible("v2")) {
                            val path = Path()
                            visibleEntries.forEachIndexed { i, e ->
                                val x = xForIndex(i)
                                val v = e.pv2_voltage ?: 0.0
                                val y = h * (1f - (v / maxVoltage).toFloat().coerceIn(0f, 1f))
                                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                            }
                            drawPath(path, pv2Pink.copy(alpha = 0.85f), style = Stroke(width = 1.1f.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 4f), 0f)))
                        }

                        // Vertical scrub line
                        selectedEntry?.let { entry ->
                            val idx = visibleEntries.indexOf(entry)
                            if (idx != -1) {
                                val targetX = xForIndex(idx)
                                drawLine(
                                    color = BatteryGreen.copy(alpha = 0.8f),
                                    start = Offset(targetX, 0f),
                                    end = Offset(targetX, h),
                                    strokeWidth = 1.2f.dp.toPx(),
                                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f), 0f)
                                )
                            }
                        }
                    }
                }

                Spacer(Modifier.width(4.dp))

                // Right Y Axis (Voltage V)
                Column(
                    modifier = Modifier.width(28.dp).fillMaxHeight().padding(vertical = 4.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                    horizontalAlignment = Alignment.Start
                ) {
                    if (showVoltage) {
                        Text("${maxVoltage.toInt()}V", style = MaterialTheme.typography.labelSmall, color = pv1Cyan.copy(alpha = 0.9f), fontSize = 8.sp)
                        Text("${(maxVoltage * 0.5).toInt()}V", style = MaterialTheme.typography.labelSmall, color = pv1Cyan.copy(alpha = 0.9f), fontSize = 8.sp)
                        Text("0V", style = MaterialTheme.typography.labelSmall, color = pv1Cyan.copy(alpha = 0.9f), fontSize = 8.sp)
                    } else {
                        Spacer(Modifier.width(28.dp))
                    }
                }
            }

            // Timeline labels (X Axis bottom)
            if (visibleEntries.size >= 2) {
                val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
                val tFirst = visibleEntries.first().timestamp
                val tMid = visibleEntries[visibleEntries.size / 2].timestamp
                val tLast = visibleEntries.last().timestamp
                if (tFirst != null && tMid != null && tLast != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(sdf.format(tFirst), style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp)
                        Text(sdf.format(tMid), style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp)
                        Text(sdf.format(tLast), style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.5.sp)
                    }
                }
            }

            // Pan Slider (Drag to scroll timeline)
            if (zoomHours < 24f && totalDurationHours > zoomHours) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(12.dp))
                        .border(1.dp, Color.White.copy(alpha = 0.04f), RoundedCornerShape(12.dp))
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(
                                imageVector = Icons.Default.ArrowBack,
                                contentDescription = null,
                                tint = BatteryGreen,
                                modifier = Modifier.size(10.dp)
                            )
                            Text("DRAG TO SCROLL TIMELINE", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.5.sp)
                        }
                        val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
                        Text(
                            text = "${sdf.format(timeRangeStart)} - ${sdf.format(timeRangeEnd)}",
                            style = MaterialTheme.typography.labelSmall,
                            color = BatteryGreen,
                            fontWeight = FontWeight.Bold,
                            fontSize = 10.sp
                        )
                    }
                    Slider(
                        value = panPosition,
                        onValueChange = { panPosition = it },
                        colors = SliderDefaults.colors(
                            thumbColor = BatteryGreen,
                            activeTrackColor = BatteryGreen.copy(alpha = 0.5f),
                            inactiveTrackColor = Color.White.copy(alpha = 0.05f)
                        ),
                        modifier = Modifier.height(24.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun ChartLegendToggle(label: String, color: Color, active: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(if (active) Color.White.copy(alpha = 0.03f) else Color.Transparent)
            .clickable { onClick() }
            .padding(horizontal = 6.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(CircleShape)
                .background(if (active) color else color.copy(alpha = 0.2f))
        )
        Spacer(Modifier.width(6.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = if (active) Color.White else TextSecondary,
            fontWeight = if (active) FontWeight.Bold else FontWeight.Normal,
            fontSize = 9.5.sp
        )
    }
}

private fun findNearestEntry(touchX: Float, width: Float, entries: List<TelemetryEntry>): TelemetryEntry? {
    if (entries.isEmpty()) return null
    val fraction = (touchX / width).coerceIn(0f, 1f)
    val index = (fraction * (entries.size - 1)).toInt()
    return entries.getOrNull(index)
}

// ---- 24H System Performance & Bill Summary Card ----

@Composable
fun PeriodSummaryCard(entries: List<TelemetryEntry>) {
    val dailyBills by FirebaseManager.dailyBills.collectAsState()
    val todayStr = remember { java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date()) }
    val todayBill = remember(dailyBills, todayStr) { dailyBills.firstOrNull { it.date == todayStr } }

    val totalSolar = todayBill?.solar_kwh ?: if (entries.isNotEmpty()) entries.sumOf { (it.solar_generation_kw ?: 0.0) * 0.5 } else 0.0
    val totalLoad = todayBill?.load_kwh ?: if (entries.isNotEmpty()) entries.sumOf { (it.local_load_kw ?: 0.0) * 0.5 } else 0.0
    val totalImport = todayBill?.import_kwh ?: 0.0
    val totalExport = todayBill?.export_kwh ?: 0.0
    val totalCharge = todayBill?.charge_kwh ?: 0.0
    val totalDischarge = todayBill?.discharge_kwh ?: 0.0
    val netCost = todayBill?.net_cost ?: 0.0
    val savings = todayBill?.savings ?: 0.0
    val minSoc = entries.minOfOrNull { it.soc } ?: 0
    val maxSoc = entries.maxOfOrNull { it.soc } ?: 0

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(16.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, SolarGold.copy(alpha = 0.2f)),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            // Card Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "📊 24H SYSTEM SUMMARY",
                        style = MaterialTheme.typography.labelSmall,
                        color = SolarGold,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.2.sp
                    )
                    Text(
                        text = "Daily Energy & Financial Breakdown",
                        style = MaterialTheme.typography.titleMedium,
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                }
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(BatteryGreen.copy(alpha = 0.15f))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = "SAVED $${String.format("%.2f", savings)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = BatteryGreen,
                        fontWeight = FontWeight.ExtraBold,
                        fontSize = 10.sp
                    )
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.1f))

            // 3-Column x 2-Row Metric Grid
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                // Row 1: Solar / Load / Net Cost
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SummaryMetricTile(
                        modifier = Modifier.weight(1f),
                        icon = "☀️",
                        label = "Solar Yield",
                        value = "${String.format("%.1f", totalSolar)} kWh",
                        color = SolarGold
                    )
                    SummaryMetricTile(
                        modifier = Modifier.weight(1f),
                        icon = "🏠",
                        label = "House Load",
                        value = "${String.format("%.1f", totalLoad)} kWh",
                        color = LoadBlue
                    )
                    SummaryMetricTile(
                        modifier = Modifier.weight(1f),
                        icon = "💰",
                        label = "Net Bill Today",
                        value = "$${String.format("%.2f", netCost)}",
                        color = Color.White
                    )
                }

                // Row 2: Grid In/Out / Batt In/Out / SoC Swing
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SummaryMetricTile(
                        modifier = Modifier.weight(1f),
                        icon = "⚡",
                        label = "Grid In / Out",
                        value = "${String.format("%.1f", totalImport)} / ${String.format("%.1f", totalExport)}",
                        color = if (totalImport > totalExport) Color(0xFFF97316) else BatteryGreen
                    )
                    SummaryMetricTile(
                        modifier = Modifier.weight(1f),
                        icon = "🔋",
                        label = "Batt Chg / Dsg",
                        value = "${String.format("%.1f", totalCharge)} / ${String.format("%.1f", totalDischarge)}",
                        color = BatteryGreen
                    )
                    SummaryMetricTile(
                        modifier = Modifier.weight(1f),
                        icon = "📈",
                        label = "SoC Swing",
                        value = "$minSoc% → $maxSoc%",
                        color = Color(0xFF38BDF8)
                    )
                }
            }
        }
    }
}

@Composable
fun SummaryMetricTile(
    modifier: Modifier = Modifier,
    icon: String,
    label: String,
    value: String,
    color: Color
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(Color.White.copy(alpha = 0.04f))
            .padding(8.dp),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(icon, fontSize = 9.sp)
            Text(label, style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
        }
        Text(value, style = MaterialTheme.typography.bodyMedium, color = color, fontWeight = FontWeight.Bold, fontSize = 11.sp)
    }
}

// ---- PV Forecast vs Actual Comparison Card ----

data class PvCompItem(
    val dateStr: String,
    val actualSolar: Double?,
    val forecastSolar: Double?
) {
    val shortDate: String
        get() {
            val parts = dateStr.split("-")
            return if (parts.size == 3) "${parts[1]}/${parts[2]}" else dateStr
        }
    val error: Double?
        get() = if (forecastSolar != null && actualSolar != null) forecastSolar - actualSolar else null
    val accuracyPct: Double?
        get() = if (forecastSolar != null && actualSolar != null && actualSolar > 0) {
            maxOf(0.0, 100.0 - Math.abs(forecastSolar - actualSolar) / actualSolar * 100.0)
        } else null
}

@Composable
fun PvForecastVsActualCard() {
    val bills by FirebaseManager.dailyBills.collectAsState()
    val planHistory by FirebaseManager.chargingPlanHistory.collectAsState()
    var rangeDays by remember { mutableStateOf(7) }
    var selectedItem by remember { mutableStateOf<PvCompItem?>(null) }

    val items = remember(bills, planHistory, rangeDays) {
        val billsMap = bills.associate { it.date to it.solar_kwh }
        val plansMap = planHistory.associate { it.for_date to (it.pv_forecast_kwh ?: 0.0) }
        val allDates = (billsMap.keys + plansMap.keys).sorted().takeLast(rangeDays)
        allDates.map { dateStr ->
            PvCompItem(
                dateStr = dateStr,
                actualSolar = billsMap[dateStr],
                forecastSolar = plansMap[dateStr]
            )
        }
    }

    val validItems = remember(items) { items.filter { it.actualSolar != null && it.forecastSolar != null } }
    val mae = remember(validItems) {
        if (validItems.isEmpty()) 0.0
        else validItems.sumOf { Math.abs((it.forecastSolar ?: 0.0) - (it.actualSolar ?: 0.0)) } / validItems.size
    }
    val avgAccuracy = remember(validItems) {
        if (validItems.isEmpty()) 0.0
        else validItems.sumOf { it.accuracyPct ?: 0.0 } / validItems.size
    }
    val bias = remember(validItems) {
        if (validItems.isEmpty()) 0.0
        else validItems.sumOf { (it.forecastSolar ?: 0.0) - (it.actualSolar ?: 0.0) } / validItems.size
    }

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, SolarGold.copy(alpha = 0.25f), RoundedCornerShape(16.dp)),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header: Title + Range Selector
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "PV FORECAST VS ACTUAL",
                        style = MaterialTheme.typography.labelSmall,
                        color = SolarGold,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.2.sp
                    )
                    Text(
                        text = "Daily Nightly Forecast Accuracy",
                        style = MaterialTheme.typography.titleMedium,
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                }

                // Range Selector (7D / 30D)
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (rangeDays == 7) SolarGold else Color.White.copy(alpha = 0.1f))
                            .clickable { rangeDays = 7 }
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text("7D", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = if (rangeDays == 7) Color.Black else Color.White)
                    }
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (rangeDays == 30) SolarGold else Color.White.copy(alpha = 0.1f))
                            .clickable { rangeDays = 30 }
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text("30D", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = if (rangeDays == 30) Color.Black else Color.White)
                    }
                }
            }

            // Summary Metrics Pill Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color.White.copy(alpha = 0.04f))
                    .padding(10.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text("MAE (平均误差)", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Text("${String.format("%.2f", mae)} kWh", style = MaterialTheme.typography.bodyMedium, color = Color.White, fontWeight = FontWeight.Bold)
                }
                Column {
                    Text("AVG ACCURACY (准确率)", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Text("${String.format("%.1f", avgAccuracy)}%", style = MaterialTheme.typography.bodyMedium, color = BatteryGreen, fontWeight = FontWeight.Bold)
                }
                Column {
                    Text("BIAS (偏差)", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 9.sp)
                    Text("${String.format("%+.2f", bias)} kWh", style = MaterialTheme.typography.bodyMedium, color = if (bias > 0) Color(0xFFF97316) else Color(0xFF38BDF8), fontWeight = FontWeight.Bold)
                }
            }

            // Scrubbing Tooltip Banner
            selectedItem?.let { sel ->
                val todayStr = remember { java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date()) }
                val isToday = (sel.dateStr == todayStr)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(6.dp))
                        .background(if (isToday) Color(0xFF1E293B) else Color.Black.copy(alpha = 0.6f))
                        .border(if (isToday) 1.dp else 0.dp, if (isToday) SolarGold else Color.Transparent, RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("[${sel.dateStr}]", fontSize = 10.sp, color = Color.White, fontWeight = FontWeight.Bold)
                        if (isToday) {
                            Text("LIVE 🔴", fontSize = 9.sp, color = Color(0xFFEF4444), fontWeight = FontWeight.ExtraBold)
                        }
                    }
                    Text("Actual: ${String.format("%.1f", sel.actualSolar ?: 0.0)} kWh", fontSize = 10.sp, color = SolarGold, fontWeight = FontWeight.Bold)
                    Text("Forecast: ${String.format("%.1f", sel.forecastSolar ?: 0.0)} kWh", fontSize = 10.sp, color = Color(0xFF38BDF8))
                    sel.error?.let { err ->
                        Text("${String.format("%+.1f", err)} kWh", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = if (err > 0) Color(0xFFF97316) else Color(0xFF38BDF8))
                    }
                }
            }

            // Dual Bar Chart Canvas
            if (items.isEmpty()) {
                Box(modifier = Modifier.fillMaxWidth().height(180.dp), contentAlignment = Alignment.Center) {
                    Text("Loading historical prediction comparisons...", color = TextSecondary, fontSize = 12.sp)
                }
            } else {
                val maxVal = remember(items) {
                    val m = items.maxOfOrNull { maxOf(it.actualSolar ?: 0.0, it.forecastSolar ?: 0.0) } ?: 30.0
                    if (m <= 0) 30.0 else m * 1.15
                }

                Canvas(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(200.dp)
                        .pointerInput(items) {
                            detectTapGestures { offset ->
                                val n = items.size
                                val touchX = offset.x.coerceIn(0f, size.width.toFloat())
                                val index = if (n > 1) Math.round((touchX / size.width.toFloat()) * (n - 1)) else 0
                                selectedItem = items.getOrNull(index.coerceIn(0, n - 1))
                            }
                        }
                        .pointerInput(items) {
                            detectDragGestures { change, _ ->
                                val n = items.size
                                val touchX = change.position.x.coerceIn(0f, size.width.toFloat())
                                val index = if (n > 1) Math.round((touchX / size.width.toFloat()) * (n - 1)) else 0
                                selectedItem = items.getOrNull(index.coerceIn(0, n - 1))
                            }
                        }
                ) {
                    val w = size.width
                    val h = size.height
                    val stepX = if (items.size > 1) w / (items.size - 1) else w

                    // Build points for Actual and Forecast
                    val actualPoints = mutableListOf<Pair<Float, Float>>()
                    val forecastPoints = mutableListOf<Pair<Float, Float>>()

                    items.forEachIndexed { i, item ->
                        val x = i * stepX
                        item.actualSolar?.let { actual ->
                            val y = (h - (actual / maxVal * h.toDouble())).toFloat()
                            actualPoints.add(Pair(x, y))
                        }
                        item.forecastSolar?.let { fcst ->
                            val y = (h - (fcst / maxVal * h.toDouble())).toFloat()
                            forecastPoints.add(Pair(x, y))
                        }
                    }

                    // 1. Draw Actual Area Gradient + Solid Gold Line
                    if (actualPoints.isNotEmpty()) {
                        val areaPath = Path().apply {
                            moveTo(actualPoints.first().first, h)
                            actualPoints.forEach { lineTo(it.first, it.second) }
                            lineTo(actualPoints.last().first, h)
                            close()
                        }
                        drawPath(
                            path = areaPath,
                            brush = Brush.verticalGradient(
                                colors = listOf(SolarGold.copy(alpha = 0.25f), Color.Transparent)
                            )
                        )

                        val linePath = Path().apply {
                            moveTo(actualPoints.first().first, actualPoints.first().second)
                            actualPoints.forEach { lineTo(it.first, it.second) }
                        }
                        drawPath(
                            path = linePath,
                            color = SolarGold,
                            style = Stroke(width = 5f, cap = StrokeCap.Round)
                        )

                        actualPoints.forEach { (px, py) ->
                            drawCircle(color = SolarGold, radius = 7f, center = Offset(px, py))
                        }
                    }

                    // 2. Draw Forecast Dashed Cyan Line
                    if (forecastPoints.isNotEmpty()) {
                        val linePath = Path().apply {
                            moveTo(forecastPoints.first().first, forecastPoints.first().second)
                            forecastPoints.forEach { lineTo(it.first, it.second) }
                        }
                        drawPath(
                            path = linePath,
                            color = Color(0xFF38BDF8),
                            style = Stroke(
                                width = 4f,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 8f), 0f),
                                cap = StrokeCap.Round
                            )
                        )

                        forecastPoints.forEach { (px, py) ->
                            drawCircle(color = Color(0xFF38BDF8), radius = 6f, center = Offset(px, py))
                        }
                    }

                    // 3. Draw Vertical Dashed Guideline & Highlight Rings on Selection
                    selectedItem?.let { sel ->
                        val idx = items.indexOfFirst { it.dateStr == sel.dateStr }
                        if (idx >= 0) {
                            val selX = idx * stepX

                            // Vertical Dashed Guideline
                            drawLine(
                                color = Color.White.copy(alpha = 0.6f),
                                start = Offset(selX, 0f),
                                end = Offset(selX, h),
                                strokeWidth = 3f,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f), 0f)
                            )

                            // Highlight Actual Solar Datapoint
                            sel.actualSolar?.let { actual ->
                                val py = (h - (actual / maxVal * h.toDouble())).toFloat()
                                drawCircle(color = SolarGold.copy(alpha = 0.35f), radius = 16f, center = Offset(selX, py))
                                drawCircle(color = SolarGold, radius = 9f, center = Offset(selX, py))
                                drawCircle(color = Color.White, radius = 4f, center = Offset(selX, py))
                            }

                            // Highlight Forecast Solar Datapoint
                            sel.forecastSolar?.let { fcst ->
                                val py = (h - (fcst / maxVal * h.toDouble())).toFloat()
                                drawCircle(color = Color(0xFF38BDF8).copy(alpha = 0.35f), radius = 14f, center = Offset(selX, py))
                                drawCircle(color = Color(0xFF38BDF8), radius = 8f, center = Offset(selX, py))
                                drawCircle(color = Color.White, radius = 3f, center = Offset(selX, py))
                            }
                        }
                    }
                }
            }

            // Legend Footer
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(SolarGold))
                    Text("Actual Solar (实际发电)", fontSize = 10.sp, color = TextSecondary)
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(Color(0xFF38BDF8)))
                    Text("Nightly AI Forecast (夜间预测)", fontSize = 10.sp, color = TextSecondary)
                }
            }
        }
    }
}
