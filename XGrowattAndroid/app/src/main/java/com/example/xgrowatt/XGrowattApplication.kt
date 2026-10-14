package com.example.xgrowatt

import android.app.Application
import android.content.Context
import com.google.firebase.Firebase
import com.google.firebase.appcheck.appCheck
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory
import com.google.firebase.initialize

class XGrowattApplication : Application() {
    companion object {
        lateinit var appContext: Context
            private set
    }

    override fun onCreate() {
        super.onCreate()
        appContext = this
        // Initialize Firebase
        Firebase.initialize(context = this)

        // Custom Static Debug Token
        // The token below was found in your recent logs. 
        // PLEASE ENSURE this is registered in Firebase Console:
        // Build > App Check > Apps > Manage debug tokens
        val debugToken = "f9558d8f-4369-49b6-94af-70e0f2573d0e"

        try {
            // Write debug secret into the SharedPreferences backing the DebugAppCheckProvider
            val persistenceKey = "[DEFAULT]"
            val prefs = getSharedPreferences(
                "com.google.firebase.appcheck.debug.store.$persistenceKey",
                Context.MODE_PRIVATE
            )
            prefs.edit()
                .putString("com.google.firebase.appcheck.debug.DEBUG_SECRET", debugToken)
                .apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // Install the standard Debug App Check Factory
        Firebase.appCheck.installAppCheckProviderFactory(
            DebugAppCheckProviderFactory.getInstance()
        )
    }
}
