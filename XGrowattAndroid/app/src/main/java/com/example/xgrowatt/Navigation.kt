package com.example.xgrowatt

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.xgrowatt.data.DailyBill
import com.example.xgrowatt.data.FirebaseManager
import com.example.xgrowatt.data.GrowattLiveStatus
import com.example.xgrowatt.data.GrowattSettings
import com.example.xgrowatt.data.TelemetryEntry
import com.example.xgrowatt.data.TodayStatsCalculator
import com.example.xgrowatt.data.WeatherInfo
import com.example.xgrowatt.data.WeatherManager
import com.example.xgrowatt.theme.BgDark
import com.example.xgrowatt.theme.CardBg
import com.example.xgrowatt.theme.SolarGold
import com.example.xgrowatt.theme.TextSecondary
import com.example.xgrowatt.ui.analytics.AnalyticsScreen
import com.example.xgrowatt.ui.components.AtmosphericBackground
import com.example.xgrowatt.ui.components.MascotDialog
import com.example.xgrowatt.ui.dashboard.DashboardScreen
import com.example.xgrowatt.ui.dashboard.MascotView
import com.example.xgrowatt.ui.planandbills.PlanAndBillsScreen
import com.example.xgrowatt.ui.settings.SettingsScreen

private data class TabItem(
    val label: String,
    val icon: ImageVector,
    val screen: @Composable () -> Unit,
)

@Composable
fun MainNavigation() {
    val weatherState by WeatherManager.weather.collectAsState()
    val isDayState by WeatherManager.isDay.collectAsState()
    val settings by FirebaseManager.settings.collectAsState()
    val liveStatus by FirebaseManager.liveStatus.collectAsState()
    val telemetryHistory by FirebaseManager.telemetryHistory.collectAsState()
    val historicalBills by FirebaseManager.historicalBills.collectAsState()
    val dailyBills by FirebaseManager.dailyBills.collectAsState()
    val chargingPlan by FirebaseManager.chargingPlan.collectAsState()

    val tz = settings?.timezone ?: "Australia/Sydney"
    val lat = settings?.latitude
    val lon = settings?.longitude

    LaunchedEffect(tz, lat, lon) {
        WeatherManager.fetchIfNeeded(tz, lat, lon)
    }

    LaunchedEffect(Unit) {
        val cal = java.util.Calendar.getInstance()
        val end = cal.time
        cal.add(java.util.Calendar.DAY_OF_YEAR, -60)
        val start = cal.time
        FirebaseManager.listenToBillsRange(start, end)
    }

    val tabs = remember {
        listOf(
            TabItem("Dashboard", Icons.Filled.Dashboard) { DashboardScreen() },
            TabItem("Analytics", Icons.Filled.Analytics) { AnalyticsScreen() },
            TabItem("Plan & Bills", Icons.Filled.Receipt) { PlanAndBillsScreen() },
            TabItem("Settings", Icons.Filled.Settings) { SettingsScreen() },
        )
    }

    var selectedIndex by remember { mutableStateOf(0) }
    var isAppStarting by remember { mutableStateOf(true) }

    val dataLoaded = settings != null && weatherState.isRealData

    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(2000)
        isAppStarting = false
    }

    LaunchedEffect(dataLoaded) {
        if (dataLoaded) {
            kotlinx.coroutines.delay(500)
            isAppStarting = false
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(BgDark)) {
        if (isAppStarting) {
            // iOS Matching Premium Splash Screen
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                Spacer(modifier = Modifier.height(100.dp))
                
                // Central Glowing Bolt Logo Circle
                Box(
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .size(100.dp)
                            .background(
                                color = Color(0xFF10B981).copy(alpha = 0.12f),
                                shape = CircleShape
                            )
                    )
                    Box(
                        modifier = Modifier
                            .size(76.dp)
                            .background(
                                color = CardBg,
                                shape = CircleShape
                            )
                            .border(
                                width = 1.5.dp,
                                color = Color(0xFF10B981).copy(alpha = 0.40f),
                                shape = CircleShape
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "⚡",
                            fontSize = 36.sp
                        )
                    }
                }

                // App Branding Text
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "XGrowatt AI",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Text(
                        text = "Smart Solar & Battery Manager",
                        style = MaterialTheme.typography.bodyMedium,
                        color = TextSecondary
                    )
                }

                // Footer Version info
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(bottom = 40.dp)
                ) {
                    Text(
                        text = "v${BuildConfig.VERSION_NAME}",
                        style = MaterialTheme.typography.labelSmall,
                        color = TextSecondary.copy(alpha = 0.6f)
                    )
                }
            }
        } else {
            // Dynamic Weather Background matching iOS atmospheric visual experience
            AtmosphericBackground(weather = weatherState, isDay = isDayState)

            Scaffold(
                containerColor = Color.Transparent,
                bottomBar = {
                    NavigationBar(
                        containerColor = CardBg.copy(alpha = 0.85f),
                    ) {
                        tabs.forEachIndexed { index, tab ->
                            NavigationBarItem(
                                selected = selectedIndex == index,
                                onClick = { selectedIndex = index },
                                icon = {
                                    Icon(
                                        imageVector = tab.icon,
                                        contentDescription = tab.label,
                                    )
                                },
                                label = { Text(tab.label) },
                                colors = NavigationBarItemDefaults.colors(
                                    selectedIconColor = SolarGold,
                                    selectedTextColor = SolarGold,
                                    indicatorColor = SolarGold.copy(alpha = 0.12f),
                                    unselectedIconColor = TextSecondary,
                                    unselectedTextColor = TextSecondary,
                                ),
                            )
                        }
                    }
                },
            ) { innerPadding ->
                tabs[selectedIndex].screen.let {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                    ) {
                        it()

                        // Global Floating Mascot FAB Component (Floats gracefully across all 4 screens)
                        GlobalFloatingMascotFAB(
                            settings = settings,
                            liveStatus = liveStatus,
                            telemetryHistory = telemetryHistory,
                            weatherState = weatherState,
                            historicalBills = historicalBills,
                            dailyBills = dailyBills,
                            chargingPlan = chargingPlan
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun GlobalFloatingMascotFAB(
    settings: GrowattSettings?,
    liveStatus: GrowattLiveStatus?,
    telemetryHistory: List<TelemetryEntry>,
    weatherState: WeatherInfo,
    historicalBills: List<DailyBill>,
    dailyBills: List<DailyBill>,
    chargingPlan: com.example.xgrowatt.data.ChargingPlan?
) {
    var showMascotDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        val cal = java.util.Calendar.getInstance()
        val end = cal.time
        cal.add(java.util.Calendar.DAY_OF_YEAR, -30)
        val start = cal.time
        FirebaseManager.listenToBillsRange(start, end)
        if (historicalBills.size < 7) {
            FirebaseManager.triggerSyncNow()
            FirebaseManager.triggerBackfillBills()
        }
    }

    val infiniteTransition = rememberInfiniteTransition(label = "float")
    val bobbingY by infiniteTransition.animateFloat(
        initialValue = -3f,
        targetValue = 3f,
        animationSpec = infiniteRepeatable(
            animation = tween(1600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "bobbingY"
    )
    val glowAlpha by infiniteTransition.animateFloat(
        initialValue = 0.25f,
        targetValue = 0.60f,
        animationSpec = infiniteRepeatable(
            animation = tween(1600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "glowAlpha"
    )

    val solarKw = liveStatus?.data?.ppv?.toDoubleOrNull() ?: 0.0
    val chargeKw = liveStatus?.data?.chargePower?.toDoubleOrNull() ?: 0.0
    val dischargeKw = liveStatus?.data?.dischargePower?.toDoubleOrNull() ?: 0.0
    val loadKw = liveStatus?.data?.localLoad?.toDoubleOrNull() ?: 0.0
    val gridExportKw = liveStatus?.data?.gridExport?.toDoubleOrNull() ?: 0.0
    val gridImportKw = liveStatus?.data?.gridImport?.toDoubleOrNull() ?: 0.0
    val socVal = liveStatus?.data?.SOC?.toIntOrNull() ?: 80

    val stats = TodayStatsCalculator.calculate(telemetryHistory)
    val currentSkin = settings?.mascot_skin ?: "slime"

    val tomorrowSolarKwh = chargingPlan?.pv_forecast_kwh ?: 22.80
    val tomorrowLoadKwh = chargingPlan?.load_forecast_kwh ?: 15.50

    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(end = 16.dp, bottom = 16.dp),
        contentAlignment = Alignment.BottomEnd
    ) {
        Box(
            modifier = Modifier
                .offset(y = bobbingY.dp)
                .clip(CircleShape)
                .background(Color(0xFF0F172A).copy(alpha = 0.92f))
                .border(
                    1.5.dp,
                    SolarGold.copy(alpha = glowAlpha),
                    CircleShape
                )
                .clickable { showMascotDialog = true }
                .padding(8.dp),
            contentAlignment = Alignment.Center
        ) {
            MascotView(
                solarKw = solarKw,
                chargeKw = chargeKw,
                dischargeKw = dischargeKw,
                loadKw = loadKw,
                gridExportKw = gridExportKw,
                gridImportKw = gridImportKw,
                socPct = socVal,
                weatherIcon = weatherState.icon,
                skin = currentSkin,
                modifier = Modifier.size(46.dp)
            )
        }
    }

    if (showMascotDialog) {
        MascotDialog(
            solarKw = solarKw,
            chargeKw = chargeKw,
            dischargeKw = dischargeKw,
            loadKw = loadKw,
            gridExportKw = gridExportKw,
            gridImportKw = gridImportKw,
            socPct = socVal,
            todaySolarKwh = stats.totalSolarKwh,
            todayLoadKwh = stats.totalLoadKwh,
            todayChargeKwh = stats.totalChargeKwh,
            todayDischargeKwh = stats.totalDischargeKwh,
            todayImportKwh = stats.totalImportKwh,
            todayExportKwh = stats.totalExportKwh,
            tomorrowSolarKwh = tomorrowSolarKwh,
            tomorrowLoadKwh = tomorrowLoadKwh,
            selfSufficiency = stats.selfSufficiency,
            selfConsumption = stats.selfConsumption,
            historicalBills = historicalBills.ifEmpty { dailyBills },
            weatherCondition = weatherState.description,
            temperature = "${weatherState.temperature ?: 18.0}°C",
            tariffInfo = settings?.tariff?.let { "基础导入电价: $${it.fallbackImportRate}/kWh, 导出电价: $${it.fallbackExportRate}/kWh" } ?: "通用单费率方案",
            currentSkin = currentSkin,
            onSkinSelected = { selectedSkin ->
                val s = settings ?: GrowattSettings()
                val updated = s.copy(mascot_skin = selectedSkin)
                FirebaseManager.saveSettings(updated)
            },
            onDismiss = { showMascotDialog = false }
        )
    }
}
