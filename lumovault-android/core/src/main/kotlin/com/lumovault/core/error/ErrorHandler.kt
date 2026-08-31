package com.lumovault.core.error

import android.util.Log
import io.sentry.Sentry
import io.sentry.SentryLevel
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ErrorHandler @Inject constructor() {

    fun init(isDebug: Boolean) {
        if (!isDebug) {
            Sentry.init { options ->
                options.dsn = SENTRY_DSN
                options.tracesSampleRate = 0.2
                options.profilesSampleRate = 0.2
                options.isEnableAutoSessionTracking = true
                options.environment = "production"
            }
        }
    }

    fun captureException(throwable: Throwable, message: String? = null) {
        Log.e(TAG, message ?: throwable.message, throwable)

        if (!isDebug) {
            Sentry.captureException(throwable).also { event ->
                if (message != null) {
                    event.setExtra("context", message)
                }
            }
        }
    }

    fun captureMessage(message: String, level: SentryLevel = SentryLevel.INFO) {
        Log.d(TAG, message)

        if (!isDebug) {
            Sentry.captureMessage(message, level)
        }
    }

    companion object {
        private const val TAG = "LumoVault"
        private const val SENTRY_DSN = "" // Set in production build
        private var isDebug = false

        fun setDebugMode(debug: Boolean) {
            isDebug = debug
        }
    }
}
