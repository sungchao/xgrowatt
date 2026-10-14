package com.example.xgrowatt.ui.planandbills

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.ElectricCar
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.PlusOne
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.material3.TextButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.foundation.shape.CircleShape
import com.example.xgrowatt.data.DailyBill
import com.example.xgrowatt.data.ElectricityTariffPlan
import com.example.xgrowatt.data.FirebaseManager
import com.example.xgrowatt.data.GeneratedBillResult
import com.example.xgrowatt.data.GrowattSettings
import com.example.xgrowatt.data.GrowattTask
import com.example.xgrowatt.data.TariffRule
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
import java.util.UUID

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun PlanAndBillsScreen() {
    val settings by FirebaseManager.settings.collectAsState()
    val chargingPlan by FirebaseManager.chargingPlan.collectAsState()
    val dailyBills by FirebaseManager.dailyBills.collectAsState()
    val historicalBills by FirebaseManager.historicalBills.collectAsState()
    val isSyncing by FirebaseManager.isSyncing.collectAsState()

    val currentTasks = settings?.tasks ?: emptyList()
    val appliedFor = settings?.ai_plan_applied_for ?: ""

    // Section Collapsible States
    var schedulerExpanded by remember { mutableStateOf(false) }
    var tariffExpanded by remember { mutableStateOf(false) }
    var billGenExpanded by remember { mutableStateOf(false) }

    // Task Editor State
    var activeTaskDialog by remember { mutableStateOf<GrowattTask?>(null) }
    var activeTariffDialog by remember { mutableStateOf<TariffRule?>(null) }

    // Calendar month offset
    var calendarMonth by remember { mutableStateOf(Calendar.getInstance()) }
    var selectedCalendarDate by remember { mutableStateOf<Date?>(null) }

    // Statement dates
    val context = LocalContext.current
    var billStartDate by remember {
        mutableStateOf(
            Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -7) }.time
        )
    }
    var billEndDate by remember { mutableStateOf(Date()) }

    // Hook listeners for bill generator & calendar month
    LaunchedEffect(billStartDate, billEndDate) {
        FirebaseManager.listenToBillsRange(billStartDate, billEndDate)
    }

    LaunchedEffect(calendarMonth) {
        val c = Calendar.getInstance().apply { time = calendarMonth.time }
        c.set(Calendar.DAY_OF_MONTH, 1)
        c.add(Calendar.DAY_OF_MONTH, -7)
        val start = c.time
        c.time = calendarMonth.time
        c.set(Calendar.DAY_OF_MONTH, c.getActualMaximum(Calendar.DAY_OF_MONTH))
        c.add(Calendar.DAY_OF_MONTH, 7)
        val end = c.time
        FirebaseManager.listenToBillsRange(start, end)
    }

    val generatedBillResult by remember(historicalBills, billStartDate, billEndDate) {
        derivedStateOf {
            calculateInvoiceSum(historicalBills, billStartDate, billEndDate)
        }
    }

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
        // Title Header
        Column {
            Text(
                text = "PLANNING & FINANCE",
                style = MaterialTheme.typography.labelSmall,
                color = BatteryGreen,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.5.sp
            )
            Text(
                text = "Plan & Bills",
                style = MaterialTheme.typography.titleLarge,
                color = Color.White,
            )
        }

        // 1. AI Charging Plan Advisory Card
        chargingPlan?.let { plan ->
            AiPlanCard(
                plan = plan,
                settings = settings,
                isSyncing = isSyncing
            )
        }

        // 2. COLLAPSIBLE SCHEDULER SECTION
        Card(
            colors = CardDefaults.cardColors(containerColor = CardBg),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(14.dp)) {
                // Header
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { schedulerExpanded = !schedulerExpanded }
                ) {
                    Icon(
                        imageVector = Icons.Filled.CalendarMonth,
                        contentDescription = null,
                        tint = BatteryGreen,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "INVERTER SCHEDULE",
                            style = MaterialTheme.typography.labelSmall,
                            color = BatteryGreen,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.sp
                        )
                        if (!schedulerExpanded) {
                            val tomorrow = Date(System.currentTimeMillis() + 86400000)
                            Text(
                                text = getScheduleSummary(currentTasks, Date(), appliedFor, "Today"),
                                style = MaterialTheme.typography.bodySmall,
                                color = TextSecondary,
                                fontSize = 10.5.sp
                            )
                            Text(
                                text = getScheduleSummary(currentTasks, tomorrow, appliedFor, "Tomorrow"),
                                style = MaterialTheme.typography.bodySmall,
                                color = TextSecondary.copy(alpha = 0.75f),
                                fontSize = 10.5.sp
                            )
                        }
                    }
                    if (schedulerExpanded) {
                        IconButton(
                            onClick = { activeTaskDialog = GrowattTask(id = UUID.randomUUID().toString()) },
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = "Add Task", tint = BatteryGreen, modifier = Modifier.size(16.dp))
                        }
                        Spacer(Modifier.width(8.dp))
                    }
                    Icon(
                        imageVector = if (schedulerExpanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                        contentDescription = null,
                        tint = TextSecondary,
                        modifier = Modifier.size(16.dp)
                    )
                }

                // Collapsible Contents
                AnimatedVisibility(
                    visible = schedulerExpanded,
                    enter = expandVertically() + fadeIn(),
                    exit = shrinkVertically() + fadeOut()
                ) {
                    Column(
                        modifier = Modifier.padding(top = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        HorizontalDivider(color = Color.White.copy(alpha = 0.05f))

                        // Resolved 24h timeline
                        Text(
                            "24H RESOLVED TIMELINE PREVIEW (TODAY)",
                            style = MaterialTheme.typography.labelSmall,
                            color = TextSecondary,
                            fontWeight = FontWeight.Bold,
                            fontSize = 8.5.sp
                        )
                        TimelinePreview(currentTasks)

                        Spacer(Modifier.height(4.dp))

                        // Tasks list
                        if (currentTasks.isEmpty()) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 12.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("No manual tasks configured.", color = TextSecondary, style = MaterialTheme.typography.bodySmall)
                            }
                        } else {
                            currentTasks.forEach { task ->
                                TaskRow(
                                    task = task,
                                    onToggle = {
                                        val updated = currentTasks.map { t ->
                                            if (t.id == task.id) t.copy(enabled = !t.enabled) else t
                                        }
                                        saveTasksAndSync(updated)
                                    },
                                    onEdit = { activeTaskDialog = task },
                                    onDelete = {
                                        val updated = currentTasks.filter { t -> t.id != task.id }
                                        saveTasksAndSync(updated)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }

        // 3. COLLAPSIBLE TARIFF PLAN EDITOR
        Card(
            colors = CardDefaults.cardColors(containerColor = CardBg),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(14.dp)) {
                // Header
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { tariffExpanded = !tariffExpanded }
                ) {
                    Icon(
                        imageVector = Icons.Filled.CalendarMonth,
                        contentDescription = null,
                        tint = SolarGold,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "TARIFF PLAN & RULES",
                            style = MaterialTheme.typography.labelSmall,
                            color = SolarGold,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.sp
                        )
                        if (!tariffExpanded) {
                            settings?.tariff?.let { plan ->
                                Text(
                                    text = "Base Import: $${plan.fallbackImportRate}/kWh • Supply: $${plan.dailySupplyCharge}/day",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = TextSecondary,
                                    fontSize = 10.5.sp
                                )
                            }
                        }
                    }
                    if (tariffExpanded) {
                        IconButton(
                            onClick = { activeTariffDialog = TariffRule(id = UUID.randomUUID().toString()) },
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = "Add Rule", tint = SolarGold, modifier = Modifier.size(16.dp))
                        }
                        Spacer(Modifier.width(8.dp))
                    }
                    Icon(
                        imageVector = if (tariffExpanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                        contentDescription = null,
                        tint = TextSecondary,
                        modifier = Modifier.size(16.dp)
                    )
                }

                // Collapsible Contents
                AnimatedVisibility(
                    visible = tariffExpanded,
                    enter = expandVertically() + fadeIn(),
                    exit = shrinkVertically() + fadeOut()
                ) {
                    settings?.tariff?.let { plan ->
                        Column(
                            modifier = Modifier.padding(top = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            HorizontalDivider(color = Color.White.copy(alpha = 0.05f))

                            // Base Tariffs Inputs
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                BaseRateInput(
                                    label = "Supply / Day ($)",
                                    value = plan.dailySupplyCharge.toString(),
                                    modifier = Modifier.weight(1f)
                                ) { valD ->
                                    saveTariffPlan(plan.copy(dailySupplyCharge = valD))
                                }
                                BaseRateInput(
                                    label = "Base Imp ($/kWh)",
                                    value = plan.fallbackImportRate.toString(),
                                    modifier = Modifier.weight(1f)
                                ) { valD ->
                                    saveTariffPlan(plan.copy(fallbackImportRate = valD))
                                }
                                BaseRateInput(
                                    label = "Base Exp ($/kWh)",
                                    value = plan.fallbackExportRate.toString(),
                                    modifier = Modifier.weight(1f)
                                ) { valD ->
                                    saveTariffPlan(plan.copy(fallbackExportRate = valD))
                                }
                            }

                            // Rules list
                            Text(
                                text = "CUSTOM RULES",
                                style = MaterialTheme.typography.labelSmall,
                                color = TextSecondary,
                                fontWeight = FontWeight.Bold,
                                fontSize = 8.5.sp
                            )
                            if (plan.rules.isEmpty()) {
                                Text(
                                    text = "No custom rules configured. Base rates will apply 24/7.",
                                    color = TextSecondary,
                                    style = MaterialTheme.typography.bodySmall
                                )
                            } else {
                                plan.rules.forEach { rule ->
                                    TariffRuleRow(
                                        rule = rule,
                                        onToggle = {
                                            val rulesUpdated = plan.rules.map { r ->
                                                if (r.id == rule.id) r.copy(enabled = !r.enabled) else r
                                            }
                                            saveTariffPlan(plan.copy(rules = rulesUpdated))
                                        },
                                        onEdit = { activeTariffDialog = rule },
                                        onDelete = {
                                            val rulesUpdated = plan.rules.filter { r -> r.id != rule.id }
                                            saveTariffPlan(plan.copy(rules = rulesUpdated))
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // 4. BILLING CALENDAR & DAILY VIEW
        Card(
            colors = CardDefaults.cardColors(containerColor = CardBg),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "BILLING CALENDAR",
                    style = MaterialTheme.typography.labelSmall,
                    color = BatteryGreen,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                )

                // Calendar Paging Toolbar
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val sdfM = SimpleDateFormat("MMMM yyyy", Locale.getDefault())
                    Text(
                        text = sdfM.format(calendarMonth.time),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                    Row {
                        IconButton(onClick = {
                            val c = Calendar.getInstance().apply {
                                time = calendarMonth.time
                                add(Calendar.MONTH, -1)
                            }
                            calendarMonth = c
                        }) {
                            Icon(Icons.Filled.ChevronLeft, contentDescription = "Prev", tint = Color.White)
                        }
                        IconButton(onClick = {
                            val c = Calendar.getInstance().apply {
                                time = calendarMonth.time
                                add(Calendar.MONTH, 1)
                            }
                            calendarMonth = c
                        }) {
                            Icon(Icons.Filled.ChevronRight, contentDescription = "Next", tint = Color.White)
                        }
                    }
                }

                // Merge real-time daily bills with historical range query
                val allBills = remember(dailyBills, historicalBills) {
                    val map = historicalBills.associateBy { it.date }.toMutableMap()
                    dailyBills.forEach { map[it.date] = it }
                    map.values.sortedBy { it.date }
                }

                // Month Calendar Grid
                MonthCalendarView(
                    monthCal = calendarMonth,
                    selectedDate = selectedCalendarDate,
                    dailyBills = allBills,
                    onSelectDate = { selectedCalendarDate = it }
                )

                // Selected Date Bill Details Card
                selectedCalendarDate?.let { sDate ->
                    val sdfD = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
                    val dateKey = sdfD.format(sDate)
                    val matchedBill = allBills.find { it.date == dateKey }

                    HorizontalDivider(color = Color.White.copy(alpha = 0.04f))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        val displayFmt = SimpleDateFormat("EEEE, d MMMM yyyy", Locale.US)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                text = displayFmt.format(sDate).uppercase(),
                                style = MaterialTheme.typography.labelSmall,
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 9.sp
                            )
                            Text(
                                text = "Daily Balance Sheet Summary",
                                style = MaterialTheme.typography.bodySmall,
                                color = TextSecondary,
                                fontWeight = FontWeight.Bold,
                                fontSize = 11.sp
                            )
                        }

                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            matchedBill?.let { b ->
                                val isCredit = b.net_cost <= 0
                                val pillBg = if (isCredit) BatteryGreen.copy(alpha = 0.1f) else AlertRed.copy(alpha = 0.1f)
                                val pillColor = if (isCredit) BatteryGreen else AlertRed
                                val netCostAbs = if (b.net_cost < 0) -b.net_cost else b.net_cost
                                Box(
                                    modifier = Modifier
                                        .background(pillBg, shape = RoundedCornerShape(6.dp))
                                        .padding(horizontal = 10.dp, vertical = 4.dp)
                                ) {
                                    Text(
                                        text = "${if (b.net_cost < 0) "-" else ""}$${String.format(Locale.US, "%.2f", netCostAbs)}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = pillColor,
                                        fontWeight = FontWeight.Black,
                                        fontSize = 13.sp
                                    )
                                }
                            }

                            IconButton(onClick = { selectedCalendarDate = null }, modifier = Modifier.size(20.dp)) {
                                Icon(Icons.Filled.Close, contentDescription = null, tint = TextSecondary, modifier = Modifier.size(14.dp))
                            }
                        }
                    }

                    if (matchedBill != null && (matchedBill.solar_kwh > 0 || matchedBill.load_kwh > 0)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            AuditItem(
                                label = "Solar PV",
                                value = String.format(Locale.US, "%.1f kWh", matchedBill.solar_kwh),
                                color = SolarGold,
                                modifier = Modifier.weight(1f)
                            )
                            AuditItem(
                                label = "Home Load",
                                value = String.format(Locale.US, "%.1f kWh", matchedBill.load_kwh),
                                color = LoadBlue,
                                modifier = Modifier.weight(1f)
                            )
                            AuditItem(
                                label = "Grid Imp",
                                value = String.format(Locale.US, "%.1f kWh", matchedBill.import_kwh),
                                color = Color(0xFFF59E0B),
                                modifier = Modifier.weight(1f)
                            )
                            AuditItem(
                                label = "Grid Exp",
                                value = String.format(Locale.US, "%.1f kWh", matchedBill.export_kwh),
                                color = BatteryGreen,
                                modifier = Modifier.weight(1f)
                            )
                        }

                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(Color.White.copy(alpha = 0.02f), shape = RoundedCornerShape(8.dp))
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text("Fixed Grid Supply Charge", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 12.sp)
                                Text(String.format(Locale.US, "$%.2f", matchedBill.daily_supply_charge), style = MaterialTheme.typography.bodySmall, color = Color.White, fontSize = 12.sp)
                            }
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text("Gross Grid Import Cost", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 12.sp)
                                Text(String.format(Locale.US, "$%.2f", matchedBill.import_cost ?: 0.0), style = MaterialTheme.typography.bodySmall, color = Color.White, fontSize = 12.sp)
                            }
                            
                            // Slices breakdown
                            val pK = matchedBill.peak_kwh ?: (matchedBill.import_kwh * 0.50)
                            val pC = matchedBill.peak_cost ?: (pK * (settings?.tariff?.fallbackImportRate ?: 0.30))
                            val fK = matchedBill.free_kwh ?: (matchedBill.import_kwh * 0.15)
                            val opK = matchedBill.off_peak_kwh ?: (matchedBill.import_kwh * 0.35)
                            val opC = matchedBill.off_peak_cost ?: maxOf(0.0, (matchedBill.import_cost ?: 0.0) - pC)

                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 12.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text("  • Peak Period (${String.format(Locale.US, "%.1f", pK)} kWh)", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 10.sp)
                                    Text(String.format(Locale.US, "$%.2f", pC), style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 10.sp)
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text("  • Off-Peak Period (${String.format(Locale.US, "%.1f", opK)} kWh)", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 10.sp)
                                    Text(String.format(Locale.US, "$%.2f", opC), style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 10.sp)
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text("  • Free Power Period (${String.format(Locale.US, "%.1f", fK)} kWh)", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 10.sp)
                                    Text("$0.00", style = MaterialTheme.typography.bodySmall, color = BatteryGreen, fontSize = 10.sp)
                                }
                            }
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text("Gross Solar Export Credit", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 12.sp)
                                Text(String.format(Locale.US, "-$%.2f", matchedBill.export_credit ?: 0.0), style = MaterialTheme.typography.bodySmall, color = BatteryGreen, fontSize = 12.sp)
                            }

                            HorizontalDivider(color = Color.White.copy(alpha = 0.04f))

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text("Calculated Financial Savings", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 12.sp)
                                Text(String.format(Locale.US, "$%.2f Saved", matchedBill.savings), style = MaterialTheme.typography.bodySmall, color = BatteryGreen, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                            }
                        }
                    } else {
                        Text(
                            text = "No billing data recorded for this date.",
                            style = MaterialTheme.typography.bodySmall,
                            color = TextSecondary,
                            modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )
                    }
                }
            }
        }

        // 5. COLLAPSIBLE STATEMENT/BILL GENERATOR
        Card(
            colors = CardDefaults.cardColors(containerColor = CardBg),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(14.dp)) {
                // Header
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { billGenExpanded = !billGenExpanded }
                ) {
                    Icon(
                        imageVector = Icons.Filled.CalendarMonth,
                        contentDescription = null,
                        tint = SolarGold,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "CUSTOM STATEMENT BUILDER",
                            style = MaterialTheme.typography.labelSmall,
                            color = SolarGold,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.sp
                        )
                        if (!billGenExpanded) {
                            val sdf = SimpleDateFormat("d MMM", Locale.getDefault())
                            Text(
                                text = "Period: ${sdf.format(billStartDate)} to ${sdf.format(billEndDate)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = TextSecondary,
                                fontSize = 10.5.sp
                            )
                        }
                    }
                    Icon(
                        imageVector = if (billGenExpanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                        contentDescription = null,
                        tint = TextSecondary,
                        modifier = Modifier.size(16.dp)
                    )
                }

                // Collapsible contents
                AnimatedVisibility(
                    visible = billGenExpanded,
                    enter = expandVertically() + fadeIn(),
                    exit = shrinkVertically() + fadeOut()
                ) {
                    Column(
                        modifier = Modifier.padding(top = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        HorizontalDivider(color = Color.White.copy(alpha = 0.05f))

                        // Date Pickers row
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            val sdf = SimpleDateFormat("dd/MM/yyyy", Locale.getDefault())

                            // Start Date
                            Column(modifier = Modifier.weight(1f)) {
                                Text("Start Date", style = MaterialTheme.typography.labelSmall, color = TextSecondary)
                                Spacer(Modifier.height(4.dp))
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(8.dp))
                                        .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(8.dp))
                                        .clickable {
                                            val c = Calendar.getInstance().apply { time = billStartDate }
                                            DatePickerDialog(
                                                context,
                                                { _, yy, mm, dd ->
                                                    val res = Calendar.getInstance().apply { set(yy, mm, dd) }
                                                    billStartDate = res.time
                                                },
                                                c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH)
                                            ).show()
                                        }
                                        .padding(10.dp),
                                    contentAlignment = Alignment.CenterStart
                                ) {
                                    Text(sdf.format(billStartDate), color = Color.White, style = MaterialTheme.typography.bodySmall)
                                }
                            }

                            // End Date
                            Column(modifier = Modifier.weight(1f)) {
                                Text("End Date", style = MaterialTheme.typography.labelSmall, color = TextSecondary)
                                Spacer(Modifier.height(4.dp))
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(8.dp))
                                        .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(8.dp))
                                        .clickable {
                                            val c = Calendar.getInstance().apply { time = billEndDate }
                                            DatePickerDialog(
                                                context,
                                                { _, yy, mm, dd ->
                                                    val res = Calendar.getInstance().apply { set(yy, mm, dd) }
                                                    billEndDate = res.time
                                                },
                                                c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH)
                                            ).show()
                                        }
                                        .padding(10.dp),
                                    contentAlignment = Alignment.CenterStart
                                ) {
                                    Text(sdf.format(billEndDate), color = Color.White, style = MaterialTheme.typography.bodySmall)
                                }
                            }
                        }

                        // Generated Invoice display
                        generatedBillResult?.let { result ->
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(Color.White.copy(alpha = 0.015f), RoundedCornerShape(12.dp))
                                    .border(1.dp, Color.White.copy(alpha = 0.03f), RoundedCornerShape(12.dp))
                                    .padding(12.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        Text("XGROWATT ENERGY ACCOUNT", style = MaterialTheme.typography.labelSmall, color = BatteryGreen, fontWeight = FontWeight.Bold, fontSize = 9.sp)
                                        Text("Electricity Account Statement", style = MaterialTheme.typography.bodyMedium, color = Color.White, fontWeight = FontWeight.Black)
                                    }
                                    Icon(
                                        imageVector = Icons.Filled.Bolt,
                                        contentDescription = null,
                                        tint = BatteryGreen,
                                        modifier = Modifier.size(24.dp)
                                    )
                                }
                                
                                val sdfRange = SimpleDateFormat("d MMM yyyy", Locale.US)
                                Text(
                                    text = "${sdfRange.format(result.startDate)} - ${sdfRange.format(result.endDate)}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = TextSecondary,
                                    fontSize = 10.sp
                                )
                                
                                HorizontalDivider(color = Color.White.copy(alpha = 0.05f))

                                InvoiceSummaryRow("Grid Import Energy", String.format(Locale.US, "%.1f kWh", result.totalImportKwh))
                                InvoiceSummaryRow("Grid Export Energy", String.format(Locale.US, "%.1f kWh", result.totalExportKwh))
                                InvoiceSummaryRow("Solar Self-Consumption", String.format(Locale.US, "%.1f kWh", result.totalSolarKwh))
                                InvoiceSummaryRow("Total Home Power Load", String.format(Locale.US, "%.1f kWh", result.totalLoadKwh))
                                
                                HorizontalDivider(color = Color.White.copy(alpha = 0.04f))
                                
                                InvoiceSummaryRow("Daily Network Connection Fee (Supply)", String.format(Locale.US, "$%.2f", result.dailySupplyChargeTotal))
                                InvoiceSummaryRow("Gross Electricity Purchase Cost", String.format(Locale.US, "$%.2f", result.grossImportCost))
                                
                                // Peak / Off-Peak / Free breakdown
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(start = 12.dp),
                                    verticalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text("  • Peak Period (${String.format(Locale.US, "%.1f", result.totalPeakKwh)} kWh)", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 9.5.sp)
                                        Text(String.format(Locale.US, "$%.2f", result.totalPeakCost), style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 9.5.sp)
                                    }
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text("  • Off-Peak Period (${String.format(Locale.US, "%.1f", result.totalOffPeakKwh)} kWh)", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 9.5.sp)
                                        Text(String.format(Locale.US, "$%.2f", result.totalOffPeakCost), style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 9.5.sp)
                                    }
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text("  • Free Power Period (${String.format(Locale.US, "%.1f", result.totalFreeKwh)} kWh)", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 9.5.sp)
                                        Text("$0.00", style = MaterialTheme.typography.bodySmall, color = BatteryGreen, fontSize = 9.5.sp)
                                    }
                                }
                                
                                InvoiceSummaryRow("Solar Feed-in Credit Rebates", String.format(Locale.US, "-$%.2f", result.grossExportCredit), color = BatteryGreen)
                                
                                HorizontalDivider(color = Color.White.copy(alpha = 0.06f))
                                
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text("NET BILL AMOUNT DUE", style = MaterialTheme.typography.bodySmall, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 11.sp)
                                    val netAmountAbs = if (result.netBillAmount < 0) -result.netBillAmount else result.netBillAmount
                                    val netColor = if (result.netBillAmount <= 0) BatteryGreen else AlertRed
                                    Text(
                                        text = "${if (result.netBillAmount < 0) "-" else ""}$${String.format(Locale.US, "%.2f", netAmountAbs)}",
                                        style = MaterialTheme.typography.titleMedium,
                                        color = netColor,
                                        fontWeight = FontWeight.Black,
                                        fontSize = 16.sp
                                    )
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text("Total Financial Savings & Benefits Realized", style = MaterialTheme.typography.bodySmall, color = TextSecondary, fontSize = 9.sp)
                                    Text(
                                        text = String.format(Locale.US, "$%.2f Saved", result.totalSavings),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = BatteryGreen,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 9.sp
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))
        }
    }

    // Task Editor Dialog
    activeTaskDialog?.let { task ->
        TaskEditDialog(
            task = task,
            onDismiss = { activeTaskDialog = null },
            onSave = { updatedTask ->
                val alreadyExists = currentTasks.any { it.id == updatedTask.id }
                val updatedList = if (alreadyExists) {
                    currentTasks.map { if (it.id == updatedTask.id) updatedTask else it }
                } else {
                    currentTasks + updatedTask
                }
                saveTasksAndSync(updatedList)
                activeTaskDialog = null
            }
        )
    }

    // Tariff Rule Editor Dialog
    activeTariffDialog?.let { rule ->
        settings?.tariff?.let { plan ->
            TariffRuleEditDialog(
                rule = rule,
                onDismiss = { activeTariffDialog = null },
                onSave = { updatedRule ->
                    val alreadyExists = plan.rules.any { it.id == updatedRule.id }
                    val updatedRules = if (alreadyExists) {
                        plan.rules.map { if (it.id == updatedRule.id) updatedRule else it }
                    } else {
                        plan.rules + updatedRule
                    }
                    saveTariffPlan(plan.copy(rules = updatedRules))
                    activeTariffDialog = null
                }
            )
        }
    }
}

@Composable
fun AuditItem(
    label: String,
    value: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .background(Color.White.copy(alpha = 0.02f), shape = RoundedCornerShape(6.dp))
            .padding(6.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = TextSecondary,
            fontSize = 8.sp
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            color = color,
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp
        )
    }
}

// ---- Helpers and Calculations ----

private fun getScheduleSummary(tasks: List<GrowattTask>, date: Date, appliedFor: String, label: String): String {
    val dayName = SimpleDateFormat("EEE", Locale.US).format(date)
    val dateStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(date)
    
    val aiActive = appliedFor.isNotEmpty() 
            && appliedFor == dateStr 
            && tasks.any { it.name.startsWith("AI Plan") }
            
    val dayTasks = tasks.filter {
        it.enabled && it.days.contains(dayName) && (it.name.startsWith("AI Plan") == aiActive)
    }
    
    if (dayTasks.isEmpty()) {
        val cal = Calendar.getInstance().apply { time = date }
        val isWeekend = cal.get(Calendar.DAY_OF_WEEK) == Calendar.SATURDAY || cal.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY
        return if (isWeekend) "$label: 00:00-06:00, 12:00-14:00 (Default)" else "$label: 00:00-06:00 (Default)"
    }
    
    val sortedTasks = dayTasks.sortedBy { it.start_time }
    val tag = if (aiActive) " ✨AI" else ""
    return "$label$tag: " + sortedTasks.joinToString(", ") { "${it.start_time}-${it.end_time} → SoC ${it.soc}%" }
}

private fun calculateInvoiceSum(bills: List<DailyBill>, start: Date, end: Date): GeneratedBillResult? {
    val calendar = Calendar.getInstance()
    val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())

    val startCal = Calendar.getInstance().apply {
        time = start
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    val endCal = Calendar.getInstance().apply {
        time = end
        set(Calendar.HOUR_OF_DAY, 23)
        set(Calendar.MINUTE, 59)
        set(Calendar.SECOND, 59)
        set(Calendar.MILLISECOND, 999)
    }

    val filtered = bills.filter { bill ->
        val billDate = try { sdf.parse(bill.date) } catch (e: Exception) { null } ?: return@filter false
        val dayCal = Calendar.getInstance().apply { time = billDate }
        dayCal.timeInMillis in startCal.timeInMillis..endCal.timeInMillis
    }

    if (filtered.isEmpty()) return null

    var solar = 0.0
    var load = 0.0
    var gridImport = 0.0
    var gridExport = 0.0
    var charge = 0.0
    var discharge = 0.0
    var supplyCharge = 0.0
    var grossImportCost = 0.0
    var grossExportCredit = 0.0
    var netCost = 0.0
    var savings = 0.0
    var arbitrage = 0.0

    var peakKwh = 0.0
    var peakCost = 0.0
    var offPeakKwh = 0.0
    var offPeakCost = 0.0
    var freeKwh = 0.0
    var freeCost = 0.0

    val fallbackRate = FirebaseManager.settings.value?.tariff?.fallbackImportRate ?: 0.30

    filtered.forEach { bill ->
        solar += bill.solar_kwh
        load += bill.load_kwh
        gridImport += bill.import_kwh
        gridExport += bill.export_kwh
        charge += bill.charge_kwh
        discharge += bill.discharge_kwh
        supplyCharge += bill.daily_supply_charge
        grossImportCost += bill.import_cost ?: 0.0
        grossExportCredit += bill.export_credit ?: 0.0
        netCost += bill.net_cost
        savings += bill.savings
        arbitrage += bill.arbitrage

        if (bill.peak_kwh != null && bill.peak_cost != null &&
            bill.off_peak_kwh != null && bill.off_peak_cost != null &&
            bill.free_kwh != null && bill.free_cost != null) {
            peakKwh += bill.peak_kwh!!
            peakCost += bill.peak_cost!!
            offPeakKwh += bill.off_peak_kwh!!
            offPeakCost += bill.off_peak_cost!!
            freeKwh += bill.free_kwh!!
            freeCost += bill.free_cost!!
        } else {
            val pK = bill.import_kwh * 0.50
            val pC = pK * fallbackRate
            val fK = bill.import_kwh * 0.15
            val fC = 0.0
            val opK = bill.import_kwh * 0.35
            val opC = maxOf(0.0, (bill.import_cost ?: 0.0) - pC)

            peakKwh += pK
            peakCost += pC
            offPeakKwh += opK
            offPeakCost += opC
            freeKwh += fK
            freeCost += fC
        }
    }

    return GeneratedBillResult(
        startDate = start,
        endDate = end,
        totalSolarKwh = solar,
        totalLoadKwh = load,
        totalImportKwh = gridImport,
        totalExportKwh = gridExport,
        totalChargeKwh = charge,
        totalDischargeKwh = discharge,
        dailySupplyChargeTotal = supplyCharge,
        grossImportCost = grossImportCost,
        grossExportCredit = grossExportCredit,
        netBillAmount = netCost,
        totalSavings = savings,
        totalArbitrage = arbitrage,
        totalPeakKwh = peakKwh,
        totalPeakCost = peakCost,
        totalOffPeakKwh = offPeakKwh,
        totalOffPeakCost = offPeakCost,
        totalFreeKwh = freeKwh,
        totalFreeCost = freeCost
    )
}

private fun saveTasksAndSync(tasks: List<GrowattTask>) {
    FirebaseManager.saveTasks(tasks)
}

private fun saveTariffPlan(tariff: ElectricityTariffPlan) {
    val settings = FirebaseManager.settings.value ?: GrowattSettings()
    val updated = settings.copy(tariff = tariff)
    FirebaseManager.saveSettings(updated)
}

// ---- Subcomponents ----

data class PreviewSegment(
    val startMin: Int,
    val endMin: Int,
    val isCharging: Boolean,
    val soc: Int = 100,
    val isAi: Boolean = false,
    val taskId: String = ""
)

@Composable
fun TimelinePreview(tasks: List<GrowattTask>) {
    val dayName = SimpleDateFormat("EEE", Locale.US).format(Date())
    val todayTasks = tasks.filter { it.enabled && it.days.contains(dayName) }

    // 1. Grid of 1440 minutes, storing Triple(soc, isAi, taskId)
    val grid = Array<Triple<Int, Boolean, String>?>(1440) { null }
    for (task in todayTasks) {
        val startStr = task.start_time
        val endStr = task.end_time
        val socVal = task.soc.toIntOrNull() ?: 100
        val isAi = task.name.startsWith("AI Plan")
        try {
            val partsStart = startStr.split(":")
            val partsEnd = endStr.split(":")
            val startMin = partsStart[0].toInt() * 60 + partsStart[1].toInt()
            val endMin = partsEnd[0].toInt() * 60 + partsEnd[1].toInt()
            if (endMin > startMin) {
                for (m in startMin until endMin) {
                    grid[m] = Triple(socVal, isAi, task.id)
                }
            }
        } catch (e: Exception) {
            // ignore parsing failures
        }
    }

    // 2. Group into contiguous segments
    val segments = mutableListOf<PreviewSegment>()
    var currentStart = 0
    var currentVal = grid[0]
    for (m in 1 until 1440) {
        val valAtM = grid[m]
        val match = (currentVal == null && valAtM == null) || 
                    (currentVal != null && valAtM != null && currentVal.third == valAtM.third)
        if (!match) {
            segments.add(
                PreviewSegment(
                    startMin = currentStart,
                    endMin = m,
                    isCharging = currentVal != null,
                    soc = currentVal?.first ?: 100,
                    isAi = currentVal?.second ?: false,
                    taskId = currentVal?.third ?: ""
                )
            )
            currentStart = m
            currentVal = valAtM
        }
    }
    // Add final segment
    segments.add(
        PreviewSegment(
            startMin = currentStart,
            endMin = 1440,
            isCharging = currentVal != null,
            soc = currentVal?.first ?: 100,
            isAi = currentVal?.second ?: false,
            taskId = currentVal?.third ?: ""
        )
    )

    // 3. Render segments in a weight-based Row
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(20.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(Color.White.copy(alpha = 0.03f))
            .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(4.dp)),
        horizontalArrangement = Arrangement.Start
    ) {
        for (seg in segments) {
            val duration = seg.endMin - seg.startMin
            val isAiTask = seg.isAi
            val accentColor = if (isAiTask) SolarGold else BatteryGreen
            
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .weight(duration.toFloat())
                    .background(
                        if (seg.isCharging) accentColor else Color.Transparent
                    ),
                contentAlignment = Alignment.Center
            ) {
                // Show SOC text if it fits (duration >= 45 minutes)
                if (seg.isCharging && duration >= 45) {
                    Text(
                        text = "${seg.soc}%",
                        color = Color.White,
                        fontWeight = FontWeight.Black,
                        fontSize = 8.sp,
                        maxLines = 1,
                        style = TextStyle(
                            platformStyle = PlatformTextStyle(
                                includeFontPadding = false
                            )
                        )
                    )
                }
            }
            
            if (seg != segments.last()) {
                Spacer(
                    modifier = Modifier
                        .fillMaxHeight()
                        .width(1.dp)
                        .background(Color.White.copy(alpha = 0.08f))
                )
            }
        }
    }

    // Timeline ticks
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text("00:00", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
        Text("06:00", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
        Text("12:00", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
        Text("18:00", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
        Text("24:00", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontSize = 8.sp)
    }
}

@Composable
fun TaskRow(
    task: GrowattTask,
    onToggle: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val isAiTask = task.name.startsWith("AI Plan")
    val accentColor = if (isAiTask) SolarGold else BatteryGreen
    val daysStr = task.days.joinToString(", ")

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg.copy(alpha = 0.6f)),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onEdit() }
            .border(1.dp, Color.White.copy(alpha = 0.02f), RoundedCornerShape(10.dp))
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .width(3.dp)
                    .height(34.dp)
                    .clip(RoundedCornerShape(1.5.dp))
                    .background(accentColor)
            )
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = task.name.ifBlank { "Charge Window" },
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "${task.start_time} - ${task.end_time}  •  SoC ${task.soc}%  •  $daysStr",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                    fontSize = 9.5.sp
                )
            }
            Switch(
                checked = task.enabled,
                onCheckedChange = { onToggle() },
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = BatteryGreen,
                    uncheckedThumbColor = TextSecondary,
                    uncheckedTrackColor = CardBg
                )
            )
            IconButton(onClick = onEdit, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Filled.Edit, contentDescription = "Edit", tint = TextSecondary, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.width(6.dp))
            IconButton(onClick = onDelete, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Filled.Delete, contentDescription = "Delete", tint = AlertRed.copy(alpha = 0.8f), modifier = Modifier.size(20.dp))
            }
        }
    }
}

@Composable
fun TariffRuleRow(
    rule: TariffRule,
    onToggle: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val daysStr = rule.days.joinToString(", ")
    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg.copy(alpha = 0.6f)),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onEdit() }
            .border(1.dp, Color.White.copy(alpha = 0.02f), RoundedCornerShape(10.dp))
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .width(3.dp)
                    .height(34.dp)
                    .clip(RoundedCornerShape(1.5.dp))
                    .background(SolarGold)
            )
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = rule.name.ifBlank { "Rate Window" },
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "${rule.start_time} - ${rule.end_time}  •  Imp $${rule.import_rate}/Exp $${rule.export_rate}  •  $daysStr",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                    fontSize = 9.5.sp
                )
            }
            Switch(
                checked = rule.enabled,
                onCheckedChange = { onToggle() },
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = SolarGold,
                    uncheckedThumbColor = TextSecondary,
                    uncheckedTrackColor = CardBg
                )
            )
            IconButton(onClick = onEdit, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Filled.Edit, contentDescription = "Edit", tint = TextSecondary, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.width(6.dp))
            IconButton(onClick = onDelete, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Filled.Delete, contentDescription = "Delete", tint = AlertRed.copy(alpha = 0.8f), modifier = Modifier.size(20.dp))
            }
        }
    }
}

@Composable
fun BaseRateInput(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    onSave: (Double) -> Unit
) {
    var textVal by remember(value) { mutableStateOf(value) }
    OutlinedTextField(
        value = textVal,
        onValueChange = {
            textVal = it
            it.toDoubleOrNull()?.let { d -> onSave(d) }
        },
        label = { Text(label, fontSize = 9.sp) },
        textStyle = MaterialTheme.typography.bodySmall.copy(fontSize = 11.sp, color = Color.White),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        singleLine = true,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = SolarGold,
            unfocusedBorderColor = Color.White.copy(alpha = 0.08f),
            focusedLabelColor = SolarGold,
            unfocusedLabelColor = TextSecondary
        ),
        modifier = modifier
    )
}

@Composable
fun MonthCalendarView(
    monthCal: Calendar,
    selectedDate: Date?,
    dailyBills: List<DailyBill>,
    onSelectDate: (Date) -> Unit
) {
    val calendar = remember(monthCal) {
        Calendar.getInstance().apply {
            time = monthCal.time
            set(Calendar.DAY_OF_MONTH, 1)
        }
    }

    val daysInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
    val firstDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK) // 1 = Sun, 2 = Mon ...

    // Shift to let Monday be index 0
    val offset = when (firstDayOfWeek) {
        Calendar.MONDAY -> 0
        Calendar.TUESDAY -> 1
        Calendar.WEDNESDAY -> 2
        Calendar.THURSDAY -> 3
        Calendar.FRIDAY -> 4
        Calendar.SATURDAY -> 5
        Calendar.SUNDAY -> 6
        else -> 0
    }

    val totalCells = daysInMonth + offset
    val rowsCount = (totalCells + 6) / 7

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        // Weekdays Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 6.dp)
        ) {
            listOf("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN").forEach { day ->
                Text(
                    text = day,
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.40f),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.5.sp,
                    modifier = Modifier.weight(1f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }
        }

        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())

        // Days Grid
        for (r in 0 until rowsCount) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                for (c in 0 until 7) {
                    val cellIdx = r * 7 + c
                    val dayNum = cellIdx - offset + 1
                    if (dayNum in 1..daysInMonth) {
                        val currentCellDate = Calendar.getInstance().apply {
                            time = monthCal.time
                            set(Calendar.DAY_OF_MONTH, dayNum)
                        }.time

                        val isSelected = selectedDate?.let {
                            val c1 = Calendar.getInstance().apply { time = it }
                            val c2 = Calendar.getInstance().apply { time = currentCellDate }
                            c1.get(Calendar.YEAR) == c2.get(Calendar.YEAR) && c1.get(Calendar.DAY_OF_YEAR) == c2.get(Calendar.DAY_OF_YEAR)
                        } == true

                        val isToday = remember(currentCellDate) {
                            val today = Calendar.getInstance()
                            val cellCal = Calendar.getInstance().apply { time = currentCellDate }
                            today.get(Calendar.YEAR) == cellCal.get(Calendar.YEAR) &&
                                    today.get(Calendar.DAY_OF_YEAR) == cellCal.get(Calendar.DAY_OF_YEAR)
                        }

                        val dateKey = sdf.format(currentCellDate)
                        val rawBill = dailyBills.find { it.date == dateKey }
                        val hasTelemetry = rawBill != null && (rawBill.solar_kwh > 0 || rawBill.load_kwh > 0 || rawBill.import_kwh > 0 || rawBill.export_kwh > 0)
                        val bill = if (hasTelemetry) rawBill else null
                        val isProfit = bill != null && bill.net_cost <= 0.0

                        // Aesthetic glassmorphic styling
                        val cellBg = when {
                            isSelected -> BatteryGreen.copy(alpha = 0.22f)
                            isToday -> Color.White.copy(alpha = 0.08f)
                            isProfit -> Color(0xFF003820).copy(alpha = 0.45f)
                            bill != null -> Color(0xFF131A24).copy(alpha = 0.50f)
                            else -> Color.White.copy(alpha = 0.02f)
                        }

                        val cellBorder = when {
                            isSelected -> BatteryGreen
                            isToday -> BatteryGreen.copy(alpha = 0.6f)
                            isProfit -> Color(0xFF00E676).copy(alpha = 0.25f)
                            else -> Color.White.copy(alpha = 0.04f)
                        }

                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(46.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(cellBg)
                                .border(
                                    width = if (isSelected) 1.5.dp else 1.dp,
                                    color = cellBorder,
                                    shape = RoundedCornerShape(10.dp)
                                )
                                .clickable { onSelectDate(currentCellDate) },
                            contentAlignment = Alignment.Center
                        ) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center,
                                modifier = Modifier.fillMaxSize().padding(vertical = 4.dp)
                            ) {
                                // Day Number with optional Today badge ring
                                Box(
                                    contentAlignment = Alignment.Center,
                                    modifier = if (isToday && !isSelected) {
                                        Modifier
                                            .size(22.dp)
                                            .background(BatteryGreen.copy(alpha = 0.20f), CircleShape)
                                            .border(1.dp, BatteryGreen, CircleShape)
                                    } else Modifier
                                ) {
                                    Text(
                                        text = dayNum.toString(),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = when {
                                            isToday -> BatteryGreen
                                            isSelected -> Color.White
                                            else -> Color.White.copy(alpha = 0.90f)
                                        },
                                        fontWeight = if (isToday || isSelected) FontWeight.Bold else FontWeight.Medium,
                                        fontSize = 12.sp
                                    )
                                }

                                Spacer(modifier = Modifier.height(2.dp))

                                // Aesthetic Financial Indicator: Glowing Emerald Gem or Minimalist Net Amount
                                if (bill != null) {
                                    val prefix = if (bill.net_cost < 0.0) "-" else ""
                                    val formattedCost = String.format(Locale.US, "%s$%.1f", prefix, kotlin.math.abs(bill.net_cost))

                                    if (isProfit) {
                                        // Highlight Net Profit with Emerald Badge
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.Center,
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(3.dp))
                                                .background(Color(0xFF00E676).copy(alpha = 0.20f))
                                                .padding(horizontal = 3.dp, vertical = 0.5.dp)
                                        ) {
                                            Text(
                                                text = formattedCost,
                                                style = MaterialTheme.typography.labelSmall,
                                                color = Color(0xFF00E676),
                                                fontWeight = FontWeight.ExtraBold,
                                                fontSize = 8.5.sp,
                                                maxLines = 1
                                            )
                                        }
                                    } else {
                                        // Subtle Slate Net Cost
                                        Text(
                                            text = formattedCost,
                                            style = MaterialTheme.typography.labelSmall,
                                            color = Color.White.copy(alpha = 0.45f),
                                            fontWeight = FontWeight.Medium,
                                            fontSize = 8.5.sp,
                                            maxLines = 1
                                        )
                                    }
                                } else {
                                    // Subtle Dot placeholder to maintain pristine grid symmetry
                                    Box(
                                        modifier = Modifier
                                            .size(2.5.dp)
                                            .background(Color.White.copy(alpha = 0.10f), CircleShape)
                                    )
                                }
                            }
                        }
                    } else {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
fun InvoiceSummaryRow(label: String, value: String, color: Color = Color.White) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = TextSecondary)
        Text(value, style = MaterialTheme.typography.bodySmall, color = color, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun TaskEditDialog(
    task: GrowattTask,
    onDismiss: () -> Unit,
    onSave: (GrowattTask) -> Unit
) {
    var name by remember { mutableStateOf(task.name) }
    var startTime by remember { mutableStateOf(task.start_time) }
    var endTime by remember { mutableStateOf(task.end_time) }
    var soc by remember { mutableStateOf(task.soc) }
    var selectedDays by remember { mutableStateOf(task.days.toSet()) }
    var power by remember { mutableStateOf(task.power.toIntOrNull() ?: 100) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(BgDark.copy(alpha = 0.98f))
        ) {
            Column(
                modifier = Modifier.fillMaxSize()
            ) {
                // Header Bar matching iOS sheet header style
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.White.copy(alpha = 0.02f))
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("Cancel", color = AlertRed, fontWeight = FontWeight.Medium, fontSize = 15.sp)
                    }
                    Text(
                        text = if (task.name.isBlank()) "Add Task" else "Edit Task",
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp
                    )
                    TextButton(
                        onClick = {
                            onSave(
                                task.copy(
                                    name = name,
                                    start_time = startTime,
                                    end_time = endTime,
                                    soc = soc,
                                    power = power.toString(),
                                    days = selectedDays.toList()
                                )
                            )
                        },
                        enabled = name.isNotBlank() && selectedDays.isNotEmpty()
                    ) {
                        Text(
                            text = "Save",
                            color = if (name.isNotBlank() && selectedDays.isNotEmpty()) BatteryGreen else TextSecondary,
                            fontWeight = FontWeight.Bold,
                            fontSize = 15.sp
                        )
                    }
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.04f))

                // Scrollable Content
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp)
                ) {
                    // Section 1: Task Info
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("TASK INFO", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)
                        OutlinedTextField(
                            value = name,
                            onValueChange = { name = it },
                            placeholder = { Text("Task Name (e.g. Peak Charging)", color = TextSecondary) },
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = Color.White.copy(alpha = 0.1f),
                                unfocusedBorderColor = Color.White.copy(alpha = 0.04f),
                                focusedContainerColor = Color.White.copy(alpha = 0.03f),
                                unfocusedContainerColor = Color.White.copy(alpha = 0.03f)
                            ),
                            shape = RoundedCornerShape(8.dp),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }

                    // Section 2: Time Window Picker
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("TIME WINDOW", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            TimePickerButton(
                                timeStr = startTime,
                                onTimeSelected = { startTime = it },
                                modifier = Modifier.weight(1f)
                            )
                            Text("to", color = TextSecondary, style = MaterialTheme.typography.bodySmall)
                            TimePickerButton(
                                timeStr = endTime,
                                onTimeSelected = { endTime = it },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }

                    // Section 3: Days Active (Circleday design)
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("DAYS ACTIVE", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            val allDays = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
                            allDays.forEach { day ->
                                val isSel = selectedDays.contains(day)
                                Box(
                                    modifier = Modifier
                                        .size(36.dp)
                                        .clip(CircleShape)
                                        .background(if (isSel) BatteryGreen else Color.White.copy(alpha = 0.03f))
                                        .clickable {
                                            selectedDays = if (isSel) selectedDays - day else selectedDays + day
                                        },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = day.take(1),
                                        color = if (isSel) Color.Black else TextSecondary,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 12.sp
                                    )
                                }
                            }
                        }
                    }

                    // Section 4: Limits (SoC and Power Sliders)
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("LIMITS", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)

                        // Stop Charge SoC Limit
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                text = "Stop Charge SoC Limit: $soc%",
                                color = Color.White,
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.Bold
                            )
                            val socVal = soc.toFloatOrNull() ?: 100f
                            Slider(
                                value = socVal,
                                onValueChange = { soc = it.toInt().toString() },
                                valueRange = 10f..100f,
                                colors = SliderDefaults.colors(
                                    thumbColor = BatteryGreen,
                                    activeTrackColor = BatteryGreen
                                ),
                                modifier = Modifier.fillMaxWidth()
                            )
                        }

                        HorizontalDivider(color = Color.White.copy(alpha = 0.04f))

                        // Charging Power Rate
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                text = "Charging Power Rate: $power%",
                                color = Color.White,
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.Bold
                            )
                            val powerVal = power.toFloat()
                            Slider(
                                value = powerVal,
                                onValueChange = { power = it.toInt() },
                                valueRange = 10f..100f,
                                colors = SliderDefaults.colors(
                                    thumbColor = BatteryGreen,
                                    activeTrackColor = BatteryGreen
                                ),
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TariffRuleEditDialog(
    rule: TariffRule,
    onDismiss: () -> Unit,
    onSave: (TariffRule) -> Unit
) {
    var name by remember { mutableStateOf(rule.name) }
    var startTime by remember { mutableStateOf(rule.start_time) }
    var endTime by remember { mutableStateOf(rule.end_time) }
    var importCents by remember { mutableStateOf(String.format(Locale.US, "%.0f", rule.import_rate * 100)) }
    var exportCents by remember { mutableStateOf(String.format(Locale.US, "%.0f", rule.export_rate * 100)) }
    var selectedDays by remember { mutableStateOf(rule.days.toSet()) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(BgDark.copy(alpha = 0.98f))
        ) {
            Column(
                modifier = Modifier.fillMaxSize()
            ) {
                // Header Bar matching iOS sheet header style
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.White.copy(alpha = 0.02f))
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("Cancel", color = AlertRed, fontWeight = FontWeight.Medium, fontSize = 15.sp)
                    }
                    Text(
                        text = if (rule.name.isBlank()) "Add Tariff Rule" else "Edit Tariff Rule",
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp
                    )
                    TextButton(
                        onClick = {
                            val impVal = (importCents.toDoubleOrNull() ?: 30.0) / 100.0
                            val expVal = (exportCents.toDoubleOrNull() ?: 8.0) / 100.0
                            onSave(
                                rule.copy(
                                    name = name,
                                    start_time = startTime,
                                    end_time = endTime,
                                    import_rate = impVal,
                                    export_rate = expVal,
                                    days = selectedDays.toList()
                                )
                            )
                        },
                        enabled = name.isNotBlank() && selectedDays.isNotEmpty()
                    ) {
                        Text(
                            text = "Save",
                            color = if (name.isNotBlank() && selectedDays.isNotEmpty()) SolarGold else TextSecondary,
                            fontWeight = FontWeight.Bold,
                            fontSize = 15.sp
                        )
                    }
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.04f))

                // Scrollable Content
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp)
                ) {
                    // Section 1: Rule Details
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("RULE DETAILS", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)
                        OutlinedTextField(
                            value = name,
                            onValueChange = { name = it },
                            placeholder = { Text("Rule Name (e.g. Peak ToU)", color = TextSecondary) },
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = Color.White.copy(alpha = 0.1f),
                                unfocusedBorderColor = Color.White.copy(alpha = 0.04f),
                                focusedContainerColor = Color.White.copy(alpha = 0.03f),
                                unfocusedContainerColor = Color.White.copy(alpha = 0.03f)
                            ),
                            shape = RoundedCornerShape(8.dp),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }

                    // Section 2: Time Window Picker
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("TIME WINDOW", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            TimePickerButton(
                                timeStr = startTime,
                                onTimeSelected = { startTime = it },
                                modifier = Modifier.weight(1f)
                            )
                            Text("to", color = TextSecondary, style = MaterialTheme.typography.bodySmall)
                            TimePickerButton(
                                timeStr = endTime,
                                onTimeSelected = { endTime = it },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }

                    // Section 3: Days Active (Circleday design)
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("DAYS ACTIVE", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            val allDays = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
                            allDays.forEach { day ->
                                val isSel = selectedDays.contains(day)
                                Box(
                                    modifier = Modifier
                                        .size(36.dp)
                                        .clip(CircleShape)
                                        .background(if (isSel) SolarGold else Color.White.copy(alpha = 0.03f))
                                        .clickable {
                                            selectedDays = if (isSel) selectedDays - day else selectedDays + day
                                        },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = day.take(1),
                                        color = if (isSel) Color.Black else TextSecondary,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 12.sp
                                    )
                                }
                            }
                        }
                    }

                    // Section 4: Rates in Cents
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("ELECTRICITY RATES (¢/kWh)", style = MaterialTheme.typography.labelSmall, color = TextSecondary, fontWeight = FontWeight.Bold)
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text("Buy (Grid Import)", style = MaterialTheme.typography.labelSmall, color = TextSecondary)
                                OutlinedTextField(
                                    value = importCents,
                                    onValueChange = { importCents = it },
                                    placeholder = { Text("30") },
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                    colors = OutlinedTextFieldDefaults.colors(
                                        focusedBorderColor = Color.White.copy(alpha = 0.1f),
                                        unfocusedBorderColor = Color.White.copy(alpha = 0.04f),
                                        focusedContainerColor = Color.White.copy(alpha = 0.03f),
                                        unfocusedContainerColor = Color.White.copy(alpha = 0.03f)
                                    ),
                                    shape = RoundedCornerShape(8.dp),
                                    modifier = Modifier.fillMaxWidth()
                                )
                            }
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text("Sell (Solar Export)", style = MaterialTheme.typography.labelSmall, color = TextSecondary)
                                OutlinedTextField(
                                    value = exportCents,
                                    onValueChange = { exportCents = it },
                                    placeholder = { Text("8") },
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                    colors = OutlinedTextFieldDefaults.colors(
                                        focusedBorderColor = Color.White.copy(alpha = 0.1f),
                                        unfocusedBorderColor = Color.White.copy(alpha = 0.04f),
                                        focusedContainerColor = Color.White.copy(alpha = 0.03f),
                                        unfocusedContainerColor = Color.White.copy(alpha = 0.03f)
                                    ),
                                    shape = RoundedCornerShape(8.dp),
                                    modifier = Modifier.fillMaxWidth()
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TimePickerButton(
    timeStr: String,
    onTimeSelected: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val parsedTime = timeStr.split(":")
    val initialHour = parsedTime.getOrNull(0)?.toIntOrNull() ?: 0
    val initialMinute = parsedTime.getOrNull(1)?.toIntOrNull() ?: 0

    Box(
        modifier = modifier
            .background(Color.White.copy(alpha = 0.03f), shape = RoundedCornerShape(8.dp))
            .border(1.dp, Color.White.copy(alpha = 0.04f), RoundedCornerShape(8.dp))
            .clickable {
                TimePickerDialog(
                    context,
                    { _, hour, minute ->
                        onTimeSelected(String.format(Locale.US, "%02d:%02d", hour, minute))
                    },
                    initialHour,
                    initialMinute,
                    true // 24-hour format
                ).show()
            }
            .padding(vertical = 10.dp, horizontal = 12.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        Text(text = timeStr, color = Color.White, style = MaterialTheme.typography.bodySmall)
    }
}

private fun summaryLine(plan: com.example.xgrowatt.data.ChargingPlan): String {
    if (plan.suggested_tasks.isEmpty()) {
        return "${plan.for_date}: no grid charge needed"
    }
    val windows = plan.suggested_tasks.joinToString(separator = ", ") {
        "${it.start_time}-${it.end_time} → SoC ${it.soc}%"
    }
    val cost = plan.est_day_cost ?: plan.est_cost
    return "${plan.for_date}: $windows (day ~\$${String.format(Locale.US, "%.2f", cost)})"
}

@Composable
private fun RowScope.MetricCell(title: String, value: String, color: Color) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
        modifier = Modifier.fillMaxWidth().weight(1f)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelSmall,
            color = TextSecondary,
            fontSize = 8.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.5.sp
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
            color = color,
            fontWeight = FontWeight.Black,
            fontSize = 14.sp
        )
    }
}

@Composable
fun AiPlanCard(
    plan: com.example.xgrowatt.data.ChargingPlan,
    settings: com.example.xgrowatt.data.GrowattSettings?,
    isSyncing: Boolean
) {
    var isExpanded by remember { mutableStateOf(false) }
    var showApplyConfirm by remember { mutableStateOf(false) }
    var showRevertConfirm by remember { mutableStateOf(false) }

    Card(
        colors = CardDefaults.cardColors(containerColor = CardBg),
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header Row (Clickable to Expand/Collapse)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { isExpanded = !isExpanded },
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.AutoAwesome,
                    contentDescription = null,
                    tint = SolarGold,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(Modifier.width(6.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        Text(
                            text = "AI CHARGING PLAN GENERATOR",
                            style = MaterialTheme.typography.labelSmall,
                            color = SolarGold,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.sp
                        )
                        if (settings?.ai_auto_apply == true) {
                            Text(
                                text = "AUTO",
                                fontSize = 7.5.sp,
                                fontWeight = FontWeight.Black,
                                color = Color.Black,
                                modifier = Modifier
                                    .background(BatteryGreen, RoundedCornerShape(2.5.dp))
                                    .padding(horizontal = 3.dp, vertical = 0.5.dp),
                                style = TextStyle(
                                    platformStyle = PlatformTextStyle(
                                        includeFontPadding = false
                                    )
                                )
                            )
                        }
                    }
                    if (!isExpanded) {
                        Text(
                            text = summaryLine(plan),
                            style = MaterialTheme.typography.bodySmall,
                            color = TextSecondary,
                            maxLines = 2,
                            fontSize = 10.sp
                        )
                    }
                }

                // Regenerate Button (accessible in both collapsed and expanded states)
                IconButton(
                    onClick = { FirebaseManager.triggerGeneratePlan() },
                    enabled = !isSyncing,
                    modifier = Modifier.size(24.dp)
                ) {
                    if (isSyncing) {
                        androidx.compose.material3.CircularProgressIndicator(
                            color = SolarGold,
                            strokeWidth = 1.5.dp,
                            modifier = Modifier.size(14.dp)
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = "Regenerate Plan",
                            tint = SolarGold,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
                Spacer(Modifier.width(4.dp))

                Icon(
                    imageVector = if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = null,
                    tint = TextSecondary,
                    modifier = Modifier.size(18.dp)
                )
            }

            if (isExpanded) {
                HorizontalDivider(color = Color.White.copy(alpha = 0.04f))

                // Metric Rows
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    val firstPower = plan.suggested_tasks.firstOrNull()?.power ?: "100"
                    MetricCell("TARGET SOC", "${plan.target_soc}% ($firstPower%)", BatteryGreen)
                    MetricCell("GRID CHARGE", String.format(Locale.US, "%.1f kWh", plan.charge_kwh), Color.White)
                    MetricCell("EST DAY BILL", String.format(Locale.US, "$%.2f", plan.est_day_cost ?: plan.est_cost), SolarGold)
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    MetricCell("PV FORECAST", String.format(Locale.US, "%.1f kWh", plan.pv_forecast_kwh ?: 0.0), SolarGold)
                    MetricCell("LOAD FORECAST", String.format(Locale.US, "%.1f kWh", plan.load_forecast_kwh ?: 0.0), Color.White)
                    val modelLabel = when {
                        plan.model_used?.contains("bayesian") == true -> if (plan.model_used?.contains("+p20") == true) "Bayes (P20)" else "Bayes ML"
                        plan.model_used?.contains("ridge") == true -> if (plan.model_used?.contains("+p20") == true) "Ridge (P20)" else "Ridge ML"
                        else -> "FORMULA"
                    }
                    MetricCell("MODEL", modelLabel, TextSecondary)
                }

                if (plan.ev_sponge_active) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Color(0xFF00E5FF).copy(alpha = 0.08f), RoundedCornerShape(8.dp))
                            .border(0.5.dp, Color(0xFF00E5FF).copy(alpha = 0.35f), RoundedCornerShape(8.dp))
                            .padding(10.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = Icons.Default.ElectricCar,
                                contentDescription = null,
                                tint = Color(0xFF00E5FF),
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "EV SOLAR SPONGE ACTIVE",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = Color(0xFF00E5FF),
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 8.5.sp
                                )
                                Text(
                                    text = "Releasing ~${String.format(Locale.US, "%.1f", plan.ev_transfer_kwh)} kWh to Tesla overnight to create daytime solar absorption capacity.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = Color.White.copy(alpha = 0.9f),
                                    fontSize = 10.5.sp
                                )
                            }
                        }

                        HorizontalDivider(color = Color(0xFF00E5FF).copy(alpha = 0.2f), thickness = 0.5.dp)

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "Tesla 达标后继续充电 (06:00前谷电)",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = Color.White,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 11.sp
                                )
                                Text(
                                    text = "电池达标后不停止特斯拉，自动切为电池优先保底，转由电网谷电继续充车。",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = TextSecondary,
                                    fontSize = 9.sp
                                )
                            }
                            Spacer(Modifier.width(8.dp))
                            Switch(
                                checked = plan.tesla_continue_charge,
                                onCheckedChange = { isChecked ->
                                    val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                                    db.collection("status").document("charging_plan")
                                        .update("tesla_continue_charge", isChecked)
                                    db.collection("settings").document("tesla")
                                        .set(mapOf("sponge_continue_charge" to isChecked), com.google.firebase.firestore.SetOptions.merge())
                                },
                                colors = SwitchDefaults.colors(
                                    checkedThumbColor = Color.Black,
                                    checkedTrackColor = Color(0xFF00E5FF),
                                    uncheckedThumbColor = Color.White.copy(alpha = 0.6f),
                                    uncheckedTrackColor = Color.White.copy(alpha = 0.1f)
                                )
                            )
                        }
                    }
                }

                // Suggested Tasks
                if (plan.suggested_tasks.isNotEmpty()) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = "SUGGESTED CHARGE WINDOWS (${plan.for_date})",
                            style = MaterialTheme.typography.labelSmall,
                            color = TextSecondary,
                            fontWeight = FontWeight.Bold,
                            fontSize = 9.sp
                        )
                        plan.suggested_tasks.forEach { task ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(Color.White.copy(alpha = 0.03f), RoundedCornerShape(8.dp))
                                    .padding(10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Bolt,
                                    contentDescription = null,
                                    tint = BatteryGreen,
                                    modifier = Modifier.size(12.dp)
                                )
                                Spacer(Modifier.width(6.dp))
                                Text(
                                    text = "${task.start_time}–${task.end_time}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = Color.White,
                                    fontWeight = FontWeight.Bold
                                )
                                Spacer(Modifier.width(6.dp))
                                Text(
                                    text = "→ SoC ${task.soc}% (${task.power}% Power)",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = BatteryGreen,
                                    fontWeight = FontWeight.Bold
                                )
                                Spacer(Modifier.weight(1f))
                                Text(
                                    text = task.days.joinToString(", "),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = TextSecondary,
                                    fontSize = 10.sp
                                )
                            }
                        }

                        // Apply / Recall Action Button
                        val hasApplied = settings?.ai_plan_applied_for?.isNotEmpty() == true
                        val isApplied = hasApplied && settings?.ai_plan_applied_for == plan.for_date

                        Button(
                            onClick = {
                                if (isApplied) {
                                    showRevertConfirm = true
                                } else {
                                    showApplyConfirm = true
                                }
                            },
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (isApplied) Color.Yellow.copy(alpha = 0.12f) else BatteryGreen,
                                contentColor = if (isApplied) Color(0xFFF59E0B) else Color.Black
                            ),
                            shape = RoundedCornerShape(10.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.padding(vertical = 4.dp)
                            ) {
                                Icon(
                                    imageVector = if (isApplied) Icons.Default.ArrowBack else Icons.Default.Add,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp)
                                )
                                Spacer(Modifier.width(6.dp))
                                Text(
                                    text = if (isApplied) "Recall from Schedule" else "Apply to Schedule",
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 13.sp
                                )
                            }
                        }
                    }
                }

                // AI Executive Briefing (Gemini 2.5 Flash)
                if (!plan.ai_briefing.isNullOrBlank()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(SolarGold.copy(alpha = 0.08f), RoundedCornerShape(8.dp))
                            .border(1.dp, SolarGold.copy(alpha = 0.2f), RoundedCornerShape(8.dp))
                            .padding(10.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Default.AutoAwesome,
                                    contentDescription = null,
                                    tint = SolarGold,
                                    modifier = Modifier.size(13.dp)
                                )
                                Text(
                                    text = "AI 能量管家简报",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = SolarGold,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 10.sp
                                )
                            }
                            if (!plan.llm_plan_source.isNullOrBlank()) {
                                androidx.compose.material3.Surface(
                                    color = Color.White.copy(alpha = 0.06f),
                                    shape = RoundedCornerShape(4.dp)
                                ) {
                                    Text(
                                        text = plan.llm_plan_source!!.removePrefix("gemini-"),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = TextSecondary,
                                        fontSize = 9.sp,
                                        modifier = Modifier.padding(horizontal = 5.dp, vertical = 2.dp)
                                    )
                                }
                            }
                        }
                        Text(
                            text = plan.ai_briefing!!,
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.White.copy(alpha = 0.92f),
                            fontSize = 11.5.sp,
                            lineHeight = 16.sp
                        )
                    }
                }

                // Why / Reasoning Block
                val filteredReasoning = plan.reasoning.filter { !(plan.ai_briefing != null && it.startsWith("🤖 AI 能量管家简报")) }
                if (filteredReasoning.isNotEmpty()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(8.dp))
                            .padding(10.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = "WHY",
                            style = MaterialTheme.typography.labelSmall,
                            color = TextSecondary,
                            fontWeight = FontWeight.Bold,
                            fontSize = 9.sp
                        )
                        filteredReasoning.forEach { line ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.Top
                            ) {
                                Text(
                                    text = "•",
                                    fontSize = 11.sp,
                                    color = SolarGold.copy(alpha = 0.8f)
                                )
                                Text(
                                    text = line,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = TextSecondary,
                                    fontSize = 10.5.sp
                                )
                            }
                        }
                    }
                }

                // Auto Apply nightly plan Toggle Section (matching iOS 100%)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(8.dp))
                        .padding(10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Auto-apply nightly plan",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.White,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = "Applies each night's 23:30 plan automatically. If fresh weather can't be fetched, generation is skipped and the weekly schedule runs.",
                            style = MaterialTheme.typography.labelSmall,
                            color = TextSecondary,
                            fontSize = 8.5.sp
                        )
                    }
                    Spacer(Modifier.width(16.dp))
                    Switch(
                        checked = settings?.ai_auto_apply == true,
                        onCheckedChange = { isChecked ->
                            if (settings != null) {
                                val updated = settings.copy(ai_auto_apply = isChecked)
                                FirebaseManager.saveSettings(updated)
                            }
                        },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.Black,
                            checkedTrackColor = BatteryGreen,
                            uncheckedThumbColor = TextSecondary,
                            uncheckedTrackColor = Color.White.copy(alpha = 0.05f)
                        )
                    )
                }

                plan.generated_at?.let { generated ->
                    val sdf = SimpleDateFormat("MMM d, yyyy h:mm a", Locale.getDefault())
                    val modeText = if (settings?.ai_auto_apply == true) {
                        "AUTO mode on — tonight's plan will apply itself at 23:30. "
                    } else {
                        "Advisory only — nothing changes until you apply. "
                    }
                    Text(
                        text = "$modeText\nGenerated ${sdf.format(generated)}.",
                        style = MaterialTheme.typography.labelSmall,
                        color = TextSecondary.copy(alpha = 0.7f),
                        fontSize = 9.sp
                    )
                }
            }
        }
    }

    // Dialog confirmations
    if (showApplyConfirm) {
        AlertDialog(
            onDismissRequest = { showApplyConfirm = false },
            confirmButton = {
                androidx.compose.material3.TextButton(
                    onClick = {
                        FirebaseManager.applyChargingPlan()
                        showApplyConfirm = false
                    }
                ) {
                    Text("Apply", color = BatteryGreen)
                }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { showApplyConfirm = false }) {
                    Text("Cancel", color = Color.White)
                }
            },
            title = { Text("Apply AI plan for ${plan.for_date}?") },
            text = { Text("One-shot override: on ${plan.for_date} the inverter follows this AI plan instead of your weekly schedule. Your weekly schedule is not modified and resumes automatically the day after.") }
        )
    }

    if (showRevertConfirm) {
        AlertDialog(
            onDismissRequest = { showRevertConfirm = false },
            confirmButton = {
                androidx.compose.material3.TextButton(
                    onClick = {
                        FirebaseManager.revertChargingPlan()
                        showRevertConfirm = false
                    }
                ) {
                    Text("Recall", color = SolarGold)
                }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { showRevertConfirm = false }) {
                    Text("Cancel", color = Color.White)
                }
            },
            title = { Text("Recall the AI plan?") },
            text = { Text("Removes the applied AI Plan tasks. Your weekly schedule was never modified — it takes effect again from the next sync.") }
        )
    }
}

