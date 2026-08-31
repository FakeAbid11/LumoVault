package com.lumovault.core.tdlib

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random

enum class ConnectionStatus {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    RECONNECTING,
    FAILED,
}

class TdLibConnectionManager(
    private val client: TdLibClient,
    private val databaseKeyProvider: suspend () -> String?,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _status = MutableStateFlow(ConnectionStatus.DISCONNECTED)
    val status: StateFlow<ConnectionStatus> = _status.asStateFlow()

    val isConnected: Boolean get() = _status.value == ConnectionStatus.CONNECTED

    private val _connectionStateEvents = MutableSharedFlow<ConnectionStatus>(extraBufferCapacity = 8)
    val connectionStateEvents = _connectionStateEvents

    private var retryCount = 0
    private var heartbeatJob: Job? = null
    private var reconnectJob: Job? = null
    private var databaseKey: String? = null

    companion object {
        private const val TAG = "TdLibConnectionManager"
        private const val MAX_RETRIES = 10
        private const val INITIAL_BACKOFF_MS = 1_000L
        private const val MAX_BACKOFF_MS = 120_000L
        private const val HEARTBEAT_INTERVAL_MS = 30_000L
    }

    /**
     * Initialize the connection and connect to TDLib.
     */
    suspend fun connect(dbKey: String) {
        if (_status.value == ConnectionStatus.CONNECTED) return

        databaseKey = dbKey
        updateStatus(ConnectionStatus.CONNECTING)

        try {
            client.initialize(dbKey)
            retryCount = 0
            updateStatus(ConnectionStatus.CONNECTED)
            startHeartbeat()
            listenForUpdates()
            Log.i(TAG, "Connected to TDLib")
        } catch (e: Exception) {
            Log.e(TAG, "Connect failed", e)
            updateStatus(ConnectionStatus.FAILED)
            throw e
        }
    }

    /**
     * Disconnect gracefully.
     */
    suspend fun disconnect() {
        stopHeartbeat()
        stopReconnect()

        try {
            client.close()
        } catch (_: Exception) {
            // Ignore
        }

        retryCount = 0
        updateStatus(ConnectionStatus.DISCONNECTED)
    }

    /**
     * Send a request through the connection manager.
     * Automatically handles reconnection on transient failures.
     */
    suspend fun sendRequest(
        method: String,
        params: Map<String, dynamic>? = null,
    ): Map<String, dynamic> {
        if (!isConnected) throw TdLibException.notConnected()

        return try {
            client.sendRequest(method, params)
        } catch (e: TdLibException) {
            if (isTransientError(e)) {
                scheduleReconnect()
            }
            throw e
        }
    }

    /**
     * Force an immediate reconnection attempt.
     */
    suspend fun reconnect() {
        if (_status.value == ConnectionStatus.CONNECTED) {
            disconnect()
        }

        val key = databaseKey ?: databaseKeyProvider()
        if (key == null) {
            updateStatus(ConnectionStatus.FAILED)
            throw TdLibException(
                code = "NO_DATABASE_KEY",
                message = "No database key available for reconnect",
            )
        }

        try {
            connect(key)
        } catch (e: Exception) {
            scheduleReconnect()
        }
    }

    private fun startHeartbeat() {
        stopHeartbeat()
        heartbeatJob = scope.launch {
            while (isConnected) {
                delay(HEARTBEAT_INTERVAL_MS)
                try {
                    client.sendRequest("getOption", mapOf("option" -> "online"))
                } catch (e: Exception) {
                    Log.w(TAG, "Heartbeat failed", e)
                    scheduleReconnect()
                    break
                }
            }
        }
    }

    private fun stopHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }

    private fun scheduleReconnect() {
        if (reconnectJob?.isActive == true) return
        if (retryCount >= MAX_RETRIES) {
            updateStatus(ConnectionStatus.FAILED)
            return
        }

        updateStatus(ConnectionStatus.RECONNECTING)
        val backoff = calculateBackoff()

        reconnectJob = scope.launch {
            delay(backoff)
            retryCount++
            try {
                reconnect()
            } catch (e: Exception) {
                Log.e(TAG, "Reconnect attempt $retryCount failed", e)
                scheduleReconnect()
            }
        }
    }

    private fun stopReconnect() {
        reconnectJob?.cancel()
        reconnectJob = null
    }

    private fun calculateBackoff(): Long {
        val exponential = INITIAL_BACKOFF_MS * 2.0.pow(retryCount.toDouble())
        val jitter = Random.nextLong(0, exponential.toLong() / 2)
        return min(exponential + jitter, MAX_BACKOFF_MS).toLong()
    }

    private fun listenForUpdates() {
        scope.launch {
            client.updates.collect { update ->
                val type = update["@type"] as? String
                when (type) {
                    "updateConnectionState" -> {
                        val state = update["state"] as? Map<*, *>
                        val stateType = state?.get("@type") as? String
                        if (stateType == "connectionStateReady") {
                            // Reset backoff on successful connection
                            retryCount = 0
                        }
                    }
                    "updateAuthorizationState" -> {
                        // Auth state changes
                    }
                }
            }
        }
    }

    private fun updateStatus(newStatus: ConnectionStatus) {
        _status.value = newStatus
        scope.launch { _connectionStateEvents.emit(newStatus) }
    }

    private fun isTransientError(error: TdLibException): Boolean {
        return error.code in listOf(
            "TIMEOUT",
            "NETWORK_ERROR",
            "CLIENT_CLOSED",
            "NOT_CONNECTED",
        )
    }
}
