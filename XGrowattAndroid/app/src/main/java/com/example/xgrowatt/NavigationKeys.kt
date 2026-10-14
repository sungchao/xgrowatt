package com.example.xgrowatt

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

// Top-level tabs
@Serializable data object Dashboard : NavKey
@Serializable data object Analytics : NavKey
@Serializable data object PlanAndBills : NavKey
@Serializable data object Settings : NavKey
