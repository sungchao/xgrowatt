package com.example.xgrowatt.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.example.xgrowatt.data.DailyBill
import com.example.xgrowatt.data.FirebaseManager
import com.example.xgrowatt.data.MascotAiManager
import com.example.xgrowatt.data.MascotChatMessage
import com.example.xgrowatt.theme.SolarGold
import com.example.xgrowatt.theme.TextSecondary
import com.example.xgrowatt.ui.dashboard.MascotView
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MascotDialog(
    solarKw: Double,
    chargeKw: Double,
    dischargeKw: Double,
    loadKw: Double,
    gridExportKw: Double,
    gridImportKw: Double,
    socPct: Int,
    todaySolarKwh: Double = 0.0,
    todayLoadKwh: Double = 0.0,
    todayChargeKwh: Double = 0.0,
    todayDischargeKwh: Double = 0.0,
    todayImportKwh: Double = 0.0,
    todayExportKwh: Double = 0.0,
    tomorrowSolarKwh: Double = 0.0,
    tomorrowLoadKwh: Double = 0.0,
    selfSufficiency: Double = 0.0,
    selfConsumption: Double = 0.0,
    historicalBills: List<DailyBill> = emptyList(),
    weatherCondition: String,
    temperature: String,
    tariffInfo: String,
    currentSkin: String,
    onSkinSelected: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val settings = FirebaseManager.settings.value
    val hasApiKey = settings?.gemini_api_key?.isNotBlank() == true

    LaunchedEffect(hasApiKey) {
        MascotAiManager.initHistoryIfNeeded(hasApiKey)
    }

    val chatMessages = MascotAiManager.chatMessages
    var userInputText by remember { mutableStateOf("") }
    var isThinking by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    LaunchedEffect(chatMessages.size, isThinking) {
        if (chatMessages.isNotEmpty()) {
            listState.animateScrollToItem(chatMessages.size)
        }
    }

    fun sendMessage(text: String) {
        if (text.isBlank() || isThinking) return
        val userMsg = MascotChatMessage(sender = "user", text = text)
        chatMessages.add(userMsg)
        userInputText = ""
        isThinking = true

        scope.launch {
            val responseText = MascotAiManager.askMascot(
                userQuery = text,
                solarKw = solarKw,
                chargeKw = chargeKw,
                dischargeKw = dischargeKw,
                loadKw = loadKw,
                gridExportKw = gridExportKw,
                gridImportKw = gridImportKw,
                socPct = socPct,
                todaySolarKwh = todaySolarKwh,
                todayLoadKwh = todayLoadKwh,
                todayChargeKwh = todayChargeKwh,
                todayDischargeKwh = todayDischargeKwh,
                todayImportKwh = todayImportKwh,
                todayExportKwh = todayExportKwh,
                tomorrowSolarKwh = tomorrowSolarKwh,
                tomorrowLoadKwh = tomorrowLoadKwh,
                selfSufficiency = selfSufficiency,
                selfConsumption = selfConsumption,
                historicalBills = historicalBills,
                forecastHours = FirebaseManager.forecastHours.value,
                chargingPlan = FirebaseManager.chargingPlan.value,
                chargingPlanHistory = FirebaseManager.chargingPlanHistory.value,
                weatherCondition = weatherCondition,
                temperature = temperature,
                tariffInfo = tariffInfo,
                apiKey = FirebaseManager.settings.value?.gemini_api_key ?: ""
            )
            chatMessages.add(MascotChatMessage(sender = "mascot", text = responseText))
            isThinking = false
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.92f)
                .heightIn(max = 620.dp)
                .clip(RoundedCornerShape(24.dp))
                .border(1.dp, Color(0xFF334155), RoundedCornerShape(24.dp)),
            color = Color(0xFF0F172A)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp)
            ) {
                // Header with Mascot Avatar, Title & Close Button
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        MascotView(
                            solarKw = solarKw,
                            chargeKw = chargeKw,
                            dischargeKw = dischargeKw,
                            loadKw = loadKw,
                            gridExportKw = gridExportKw,
                            gridImportKw = gridImportKw,
                            socPct = socPct,
                            weatherIcon = weatherCondition,
                            skin = currentSkin,
                            modifier = Modifier.size(38.dp)
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        Column {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    "WattPet AI Assistant",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(if (hasApiKey) Color(0xFF10B981) else SolarGold)
                                        .padding(horizontal = 5.dp, vertical = 1.dp)
                                ) {
                                    Text(
                                        if (hasApiKey) "Gemini LLM" else "Base Mode",
                                        fontSize = 9.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.Black
                                    )
                                }
                            }
                            Text(
                                "Always here to assist with solar & energy queries",
                                style = MaterialTheme.typography.bodySmall,
                                color = TextSecondary
                            )
                        }
                    }

                    Row {
                        IconButton(onClick = { MascotAiManager.clearHistory(hasApiKey) }) {
                            Icon(
                                imageVector = Icons.Default.DeleteOutline,
                                contentDescription = "Clear History",
                                tint = TextSecondary
                            )
                        }
                        IconButton(onClick = onDismiss) {
                            Icon(
                                imageVector = Icons.Default.Close,
                                contentDescription = "Close",
                                tint = TextSecondary
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Chat Main Area
                Column(modifier = Modifier.weight(1f)) {
                    // Chat messages list with scrollable prompt chips at the top
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        // Quick prompt chips (scrolls away naturally as chat grows)
                        item {
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(bottom = 4.dp)
                            ) {
                                val chips = listOf(
                                    "⚡ Live Power Analysis",
                                    "☀️ Solar generated yesterday?",
                                    "🔮 Tomorrow solar forecast?",
                                    "🔋 Battery Charging Strategy"
                                )
                                chips.forEach { chipText ->
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(16.dp))
                                            .background(Color(0xFF334155))
                                            .clickable { sendMessage(chipText) }
                                            .padding(horizontal = 10.dp, vertical = 5.dp)
                                    ) {
                                        Text(
                                            chipText,
                                            fontSize = 12.sp,
                                            color = Color(0xFFE2E8F0)
                                        )
                                    }
                                }
                            }
                        }

                        items(chatMessages) { msg ->
                            ChatBubble(msg = msg, skin = currentSkin)
                        }

                        if (isThinking) {
                            item {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier.padding(start = 36.dp, top = 4.dp)
                                ) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(16.dp),
                                        color = SolarGold,
                                        strokeWidth = 2.dp
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        "WattPet is thinking...",
                                        fontSize = 12.sp,
                                        color = TextSecondary
                                    )
                                }
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    // Input Box
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OutlinedTextField(
                            value = userInputText,
                            onValueChange = { userInputText = it },
                            placeholder = { Text("Ask WattPet anything...", fontSize = 13.sp, color = TextSecondary) },
                            modifier = Modifier.weight(1f),
                            singleLine = true,
                            shape = RoundedCornerShape(20.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedContainerColor = Color(0xFF1E293B),
                                unfocusedContainerColor = Color(0xFF1E293B),
                                focusedBorderColor = SolarGold,
                                unfocusedBorderColor = Color(0xFF334155),
                                focusedTextColor = Color.White,
                                unfocusedTextColor = Color.White
                            )
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        IconButton(
                            onClick = { sendMessage(userInputText) },
                            modifier = Modifier
                                .size(44.dp)
                                .clip(CircleShape)
                                .background(SolarGold)
                        ) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.Send,
                                contentDescription = "Send",
                                tint = Color.Black,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ChatBubble(msg: MascotChatMessage, skin: String) {
    val isUser = msg.sender == "user"
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        if (!isUser) {
            MascotView(
                solarKw = 2.5,
                chargeKw = 0.0,
                dischargeKw = 0.0,
                loadKw = 1.0,
                gridExportKw = 1.5,
                gridImportKw = 0.0,
                socPct = 85,
                weatherIcon = "sunny",
                skin = skin,
                modifier = Modifier
                    .size(28.dp)
                    .align(Alignment.Top)
            )
            Spacer(modifier = Modifier.width(8.dp))
        }

        Box(
            modifier = Modifier
                .widthIn(max = 290.dp)
                .clip(
                    RoundedCornerShape(
                        topStart = 16.dp,
                        topEnd = 16.dp,
                        bottomStart = if (isUser) 16.dp else 4.dp,
                        bottomEnd = if (isUser) 4.dp else 16.dp
                    )
                )
                .background(if (isUser) SolarGold else Color(0xFF1E293B))
                .padding(horizontal = 12.dp, vertical = 9.dp)
        ) {
            SelectionContainer {
                Text(
                    text = msg.text,
                    color = if (isUser) Color.Black else Color.White,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                    softWrap = true
                )
            }
        }
    }
}
