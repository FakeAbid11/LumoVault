package com.lumovault.core.tdlib

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * JNI bridge to the TDLib JSON interface.
 *
 * Runs a background receive loop on a dedicated coroutine that reads
 * responses from the native TDLib client and dispatches them to callers
 * via request-specific [CompletableDeferred] instances.
 */
class TdLibClient(
    @Suppress("unused") private val context: Context,
    private val config: TdLibConfig,
) {
    private var clientId: Long? = null
    private var _initialized = false
    val isInitialized: Boolean get() = _initialized

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val requestId = AtomicInteger(0)
    private val pendingRequests = ConcurrentHashMap<Int, CompletableDeferred<Map<String, dynamic>>>()
    private val responseChannel = Channel<Pair<Int, String>>(Channel.UNLIMITED)

    private val _updates = MutableSharedFlow<Map<String, dynamic>>(extraBufferCapacity = 64)
    val updates: SharedFlow<Map<String, dynamic>> = _updates.asSharedFlow()

    private var receiveJob: kotlinx.coroutines.Job? = null

    /**
     * Initialize the TDLib client with the given database encryption key.
     * Must be called before any other methods.
     */
    suspend fun initialize(databaseKey: String) {
        if (_initialized) return

        require(databaseKey.length >= config.databaseKeyLength) {
            "Database key must be at least ${config.databaseKeyLength} characters"
        }

        try {
            clientId = nativeCreateClient()
            nativeInitialize(clientId!!, databaseKey)
            _initialized = true
            startReceiveLoop()
            Log.i(TAG, "TDLib client initialized")
        } catch (e: Exception) {
            teardown()
            throw TdLibException(
                code = "INIT_FAILED",
                message = "Failed to initialize TDLib: ${e.message}",
                userFacingMessage = "Could not connect to Telegram. Please try again.",
            )
        }
    }

    /**
     * Send a TDLib request and wait for the response.
     */
    suspend fun sendRequest(
        method: String,
        params: Map<String, dynamic>? = null,
    ): Map<String, dynamic> {
        if (!_initialized) throw TdLibException.clientNotInitialized()

        val id = requestId.incrementAndGet()
        val deferred = CompletableDeferred<Map<String, dynamic>>()
        pendingRequests[id] = deferred

        val request = buildJsonObject {
            put("@type", method)
            params?.forEach { (key, value) -> put(key, value) }
            put("@extra", id)
        }

        try {
            nativeSendRequest(clientId!!, request.toString())
            return withTimeout(REQUEST_TIMEOUT_MS) {
                deferred.await()
            }
        } catch (e: Exception) {
            pendingRequests.remove(id)
            if (e is kotlinx.coroutines.TimeoutCancellationException) {
                throw TdLibException(
                    code = "TIMEOUT",
                    message = "Request $method timed out",
                )
            }
            throw e
        }
    }

    /**
     * Close the TDLib client and release resources.
     */
    suspend fun close() {
        if (clientId == null) return

        try {
            sendRequest("close")
        } catch (_: Exception) {
            // Ignore errors during close
        }

        teardown()
        Log.i(TAG, "TDLib client closed")
    }

    private fun teardown() {
        receiveJob?.cancel()
        _initialized = false
        val id = clientId
        if (id != null) {
            try {
                nativeDestroyClient(id)
            } catch (_: Exception) {
                // Ignore cleanup errors
            }
        }
        clientId = null
        pendingRequests.values.forEach {
            it.completeExceptionally(TdLibException.clientNotInitialized())
        }
        pendingRequests.clear()
    }

    private fun startReceiveLoop() {
        receiveJob = scope.launch {
            while (_initialized) {
                try {
                    val response = nativeReceiveResponse(clientId!!)
                    if (response != null) {
                        processResponse(response)
                    } else {
                        delay(10) // Brief pause when no data available
                    }
                } catch (e: Exception) {
                    if (_initialized) {
                        Log.e(TAG, "Receive loop error", e)
                        delay(100)
                    }
                }
            }
        }
    }

    private fun processResponse(responseJson: String) {
        try {
            val json = JSONObject(responseJson)
            val extra = json.optInt("@extra", -1)

            if (extra != -1 && pendingRequests.containsKey(extra)) {
                val deferred = pendingRequests.remove(extra)
                val result = jsonToMap(json)
                deferred?.complete(result)
            } else {
                // Update event (no @extra)
                val update = jsonToMap(json)
                scope.launch { _updates.emit(update) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse response", e)
        }
    }

    private fun jsonToMap(json: JSONObject): Map<String, dynamic> {
        val map = mutableMapOf<String, dynamic>()
        json.keys().forEach { key ->
            map[key] = json.get(key)
        }
        return map
    }

    private fun buildJsonObject(init: JSONObject.() -> Unit): String {
        return JSONObject().apply(init).toString()
    }

    companion object {
        private const val TAG = "TdLibClient"
        private const val REQUEST_TIMEOUT_MS = 30_000L

        // Native JNI methods
        @JvmStatic private external fun nativeCreateClient(): Long
        @JvmStatic private external fun nativeInitialize(clientId: Long, databaseKey: String)
        @JvmStatic private external fun nativeSendRequest(clientId: Long, request: String)
        @JvmStatic private external fun nativeReceiveResponse(clientId: Long): String?
        @JvmStatic private external fun nativeDestroyClient(clientId: Long)

        init {
            System.loadLibrary("lumovault_jni")
        }
    }
}

typealias dynamic = Any?
