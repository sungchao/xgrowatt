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

        // Custom Static Debug Token (Optional: register in Firebase Console -> App Check -> Manage debug tokens)
        val debugToken = "" // Set your App Check debug token here if needed

        if (debugToken.isNotEmpty()) {
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
        }

        // Install the standard Debug App Check Factory
        Firebase.appCheck.installAppCheckProviderFactory(
            DebugAppCheckProviderFactory.getInstance()
        )
    }
}
