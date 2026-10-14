package com.example.xgrowatt

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.example.xgrowatt.theme.XGrowattTheme

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    val splashScreen = installSplashScreen()
    super.onCreate(savedInstanceState)

    val startTime = System.currentTimeMillis()
    splashScreen.setKeepOnScreenCondition {
      val elapsed = System.currentTimeMillis() - startTime
      val settingsLoaded = com.example.xgrowatt.data.FirebaseManager.settings.value != null
      val weatherLoaded = com.example.xgrowatt.data.WeatherManager.weather.value.isRealData
      
      // Keep splash screen visible until initial data is loaded, up to a 2.5s timeout
      (!settingsLoaded || !weatherLoaded) && elapsed < 2500
    }

    enableEdgeToEdge()
    setContent {
      XGrowattTheme { Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { MainNavigation() } }
    }
  }
}
