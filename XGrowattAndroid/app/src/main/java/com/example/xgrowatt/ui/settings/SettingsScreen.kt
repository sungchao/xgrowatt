package com.example.xgrowatt.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.example.xgrowatt.BuildConfig
import com.example.xgrowatt.data.FirebaseManager
import com.example.xgrowatt.data.GrowattSettings
import com.example.xgrowatt.theme.BatteryGreen
import com.example.xgrowatt.theme.BgDark
import com.example.xgrowatt.theme.CardBg
import com.example.xgrowatt.theme.SolarGold
import com.example.xgrowatt.theme.TextSecondary

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen() {
    val settings by FirebaseManager.settings.collectAsState()

    var username by remember(settings) { mutableStateOf(settings?.username ?: "") }
    var password by remember(settings) { mutableStateOf(settings?.password ?: "") }
    var serverUrl by remember(settings) { mutableStateOf(settings?.server_url ?: "https://server.growatt.com") }
    var deviceSn by remember(settings) { mutableStateOf(settings?.device_sn ?: "") }
    var lat by remember(settings) { mutableStateOf(settings?.latitude?.toString() ?: "") }
    var lon by remember(settings) { mutableStateOf(settings?.longitude?.toString() ?: "") }
    var geminiApiKey by remember(settings) { mutableStateOf(settings?.gemini_api_key ?: "") }

    var showPassword by remember { mutableStateOf(false) }
    var showGeminiKey by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }
    var apiKeySaved by remember { mutableStateOf(false) }

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
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Title Header
            Column {
                Text(
                    text = "APP CONFIGURATION",
                    style = MaterialTheme.typography.labelSmall,
                    color = BatteryGreen,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.5.sp
                )
                Text(
                    text = "System Settings",
                    style = MaterialTheme.typography.titleLarge,
                    color = Color.White,
                )
            }

        // Credentials section (collapsed by default) — also hosts Location and Save,
        // since both only matter once you're editing the connection details.
        CollapsibleSettingsSection("Growatt Credentials", initiallyExpanded = false) {
            SettingsTextField(
                label = "Username",
                value = username,
                onValueChange = { username = it; saved = false },
            )
            SettingsTextField(
                label = "Password",
                value = password,
                onValueChange = { password = it; saved = false },
                visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                trailingContent = {
                    Text(
                        if (showPassword) "Hide" else "Show",
                        style = MaterialTheme.typography.labelMedium,
                        color = SolarGold,
                        modifier = Modifier.padding(end = 8.dp).let { it },
                    )
                },
            )
            SettingsTextField(
                label = "Server URL",
                value = serverUrl,
                onValueChange = { serverUrl = it; saved = false },
                keyboardType = KeyboardType.Uri,
            )
            SettingsTextField(
                label = "Device Serial Number",
                value = deviceSn,
                onValueChange = { deviceSn = it; saved = false },
            )

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

            Text(
                "LOCATION (FOR SOLAR FORECAST)",
                style = MaterialTheme.typography.labelSmall,
                color = TextSecondary,
                fontWeight = FontWeight.SemiBold,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SettingsTextField(
                    label = "Latitude",
                    value = lat,
                    onValueChange = { lat = it; saved = false },
                    keyboardType = KeyboardType.Decimal,
                    modifier = Modifier.weight(1f),
                )
                SettingsTextField(
                    label = "Longitude",
                    value = lon,
                    onValueChange = { lon = it; saved = false },
                    keyboardType = KeyboardType.Decimal,
                    modifier = Modifier.weight(1f),
                )
            }

            Button(
                onClick = {
                    val updated = (settings ?: GrowattSettings()).copy(
                        username = username,
                        password = password,
                        server_url = serverUrl,
                        device_sn = deviceSn,
                        latitude = lat.toDoubleOrNull(),
                        longitude = lon.toDoubleOrNull(),
                    )
                    FirebaseManager.saveSettings(updated)
                    saved = true
                },
                colors = ButtonDefaults.buttonColors(containerColor = SolarGold),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth().height(50.dp),
            ) {
                Text(if (saved) "✓ Saved" else "Save Changes", style = MaterialTheme.typography.titleMedium, color = Color.Black)
            }
        }

        // WattPet Mascot & AI Collapsible Card (collapsed by default)
        CollapsibleSettingsSection("WattPet Mascot & AI Assistant", initiallyExpanded = false) {
            Text(
                "🎨 换装皮肤 (MASCOT SKINS)",
                style = MaterialTheme.typography.labelSmall,
                color = TextSecondary,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "点击选择在首页仪表盘上跳动的电量小精灵形象：",
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.70f)
            )

            val currentSkin = settings?.mascot_skin ?: "slime"
            val skins = listOf(
                Pair("slime", "史莱姆"),
                Pair("cyber_cat", "赛博猫"),
                Pair("solar_star", "太阳星"),
                Pair("battery_pal", "电池人")
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                skins.forEach { (skinId, skinName) ->
                    val isSelected = currentSkin == skinId
                    Card(
                        onClick = {
                            val updated = (settings ?: GrowattSettings()).copy(mascot_skin = skinId)
                            FirebaseManager.saveSettings(updated)
                        },
                        colors = CardDefaults.cardColors(
                            containerColor = if (isSelected) Color(0xFF1E293B) else Color(0xFF0F172A)
                        ),
                        shape = RoundedCornerShape(12.dp),
                        border = if (isSelected) androidx.compose.foundation.BorderStroke(1.5.dp, SolarGold) else null,
                        modifier = Modifier.weight(1f)
                    ) {
                        Column(
                            modifier = Modifier.padding(8.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            com.example.xgrowatt.ui.dashboard.MascotView(
                                solarKw = 2.0, chargeKw = 0.0, dischargeKw = 0.0,
                                loadKw = 1.0, gridExportKw = 1.0, gridImportKw = 0.0,
                                socPct = 80, weatherIcon = "sunny", skin = skinId,
                                modifier = Modifier.size(32.dp)
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                skinName,
                                style = MaterialTheme.typography.labelSmall,
                                color = if (isSelected) SolarGold else Color.White,
                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                            )
                        }
                    }
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

            Text(
                "🔑 GEMINI AI API KEY",
                style = MaterialTheme.typography.labelSmall,
                color = TextSecondary,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "配置您的免费 Google Gemini Key，开启 100% 自然语言 LLM 智能问答：",
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.70f)
            )

            SettingsTextField(
                label = "Gemini API Key",
                value = geminiApiKey,
                onValueChange = { geminiApiKey = it; apiKeySaved = false },
                visualTransformation = if (showGeminiKey) VisualTransformation.None else PasswordVisualTransformation(),
                trailingContent = {
                    Text(
                        if (showGeminiKey) "Hide" else "Show",
                        style = MaterialTheme.typography.labelMedium,
                        color = SolarGold,
                        modifier = Modifier.padding(end = 8.dp).clickable { showGeminiKey = !showGeminiKey },
                    )
                }
            )

            Button(
                onClick = {
                    val updated = (settings ?: GrowattSettings()).copy(gemini_api_key = geminiApiKey.trim())
                    FirebaseManager.saveSettings(updated)
                    apiKeySaved = true
                },
                colors = ButtonDefaults.buttonColors(containerColor = BatteryGreen),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth().height(46.dp)
            ) {
                Text(
                    if (apiKeySaved) "✓ Gemini Key 已保存" else "保存 Gemini Key",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.Black,
                    fontWeight = FontWeight.Bold
                )
            }
        }


        // About section (collapsed by default) — mirrors the iOS app's About card.
        CollapsibleSettingsSection("About", initiallyExpanded = false) {
            Text(
                "XGrowatt is an AI-powered energy manager for Growatt hybrid inverters: it forecasts tomorrow's solar and load, plans the cheapest battery strategy under your time-of-use tariff, and executes it on the inverter — fully hands-off.",
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.85f),
            )

            HorizontalDivider(color = Color.White.copy(alpha = 0.06f))

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    "🔑 CORE PRINCIPLE",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    "Three self-expiring control layers: a permanent weekly baseline, a one-day AI plan generated nightly from fresh weather forecasts (auto-applied in AUTO mode), and instant in-window edits. Each layer falls back to the one below when it expires — no stale setting can ever linger.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.70f),
                )
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.06f))

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "💡 KEY FEATURES",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                    fontWeight = FontWeight.Bold,
                )

                AboutFeatureRow(
                    icon = Icons.Filled.Psychology,
                    title = "AI Charging Plan",
                    text = "Nightly full-day simulation: plane-of-array irradiance forecasts (panel tilt & azimuth aware), an hourly tree-shade calibration profile, EV-aware load learning, and free-window economics decide exactly how much off-peak charge tomorrow needs — with a whole-day bill estimate you can verify against actual bills.",
                )
                AboutFeatureRow(
                    icon = Icons.Filled.Schedule,
                    title = "Per-Window SoC Dispatch",
                    text = "The inverter has one global charge-stop SoC shared by all time windows. XGrowatt time-multiplexes it: each window's target is pushed 15 minutes before that window starts — overnight 55%, free midday window 100%, automatically.",
                )
                AboutFeatureRow(
                    icon = Icons.Filled.Security,
                    title = "Drift Detection & Self-Healing",
                    text = "Every 5 minutes the inverter's device-reported registers are compared against the intended schedule. External changes surface as a dashboard alert within minutes, and drift during an active charge window is corrected automatically. Writes are receipt-verified.",
                )
                AboutFeatureRow(
                    icon = Icons.Filled.TrendingUp,
                    title = "ML Data Flywheel",
                    text = "Telemetry is stored ML-ready: 5-minute readings joined with 19 weather variables, per-MPPT string data, archived forecast snapshots (with lead-time), and every AI plan vs. actual outcome — feeding a ridge-regression PV model that replaces the empirical formula once it provably wins.",
                )
                AboutFeatureRow(
                    icon = Icons.Filled.Bolt,
                    title = "Hardware-Gentle by Design",
                    text = "Cloud-side comparison skips identical writes to protect EEPROM, sync happens once before each window instead of high-frequency polling (no '507' account locks), and LFP battery care is built in: 90% daily cap with free-window 100% top-ups doubling as weekly cell balancing.",
                )
                AboutFeatureRow(
                    icon = Icons.Filled.AutoAwesome,
                    title = "Solar-First Interface",
                    text = "Live energy flow with per-string MPPT readings, interactive charts with per-series toggles, a 24h solar forecast card (irradiance, cloud and rain), and glassmorphic cards with dynamic weather backdrops.",
                )
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.06f))

            AboutRow("Version", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            AboutRow("Package", BuildConfig.APPLICATION_ID)
        }

        Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
fun SettingsTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    keyboardType: KeyboardType = KeyboardType.Text,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    trailingContent: @Composable (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label, style = MaterialTheme.typography.bodySmall) },
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        visualTransformation = visualTransformation,
        trailingIcon = trailingContent,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = SolarGold,
            unfocusedBorderColor = Color.White.copy(alpha = 0.15f),
            focusedLabelColor = SolarGold,
            unfocusedLabelColor = TextSecondary,
            cursorColor = SolarGold,
            focusedTextColor = Color.White,
            unfocusedTextColor = Color.White,
        ),
        shape = RoundedCornerShape(10.dp),
        modifier = modifier.fillMaxWidth(),
    )
}

/**
 * A settings card whose content can be collapsed/expanded by tapping the header.
 * Used for sections that are useful but shouldn't clutter the screen by default
 * (credentials, about info).
 */
@Composable
fun CollapsibleSettingsSection(
    title: String,
    initiallyExpanded: Boolean = false,
    content: @Composable () -> Unit,
) {
    var expanded by remember { mutableStateOf(initiallyExpanded) }

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded },
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, style = MaterialTheme.typography.titleMedium, color = SolarGold, fontWeight = FontWeight.SemiBold)
                Icon(
                    imageVector = if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                    contentDescription = if (expanded) "Collapse" else "Expand",
                    tint = TextSecondary,
                )
            }
            if (expanded) {
                Spacer(modifier = Modifier.height(10.dp))
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    content()
                }
            }
        }
    }
}

@Composable
fun AboutRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = TextSecondary)
        Text(value, style = MaterialTheme.typography.bodyMedium, color = Color.White)
    }
}

@Composable
fun AboutFeatureRow(icon: ImageVector, title: String, text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = BatteryGreen,
            modifier = Modifier
                .padding(top = 2.dp)
                .size(16.dp),
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = Color.White, fontWeight = FontWeight.Bold)
            Text(text, style = MaterialTheme.typography.bodySmall, color = Color.White.copy(alpha = 0.60f))
        }
    }
}
