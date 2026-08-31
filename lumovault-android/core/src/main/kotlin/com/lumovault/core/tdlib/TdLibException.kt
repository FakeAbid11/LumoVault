package com.lumovault.core.tdlib

class TdLibException(
    val code: String,
    override val message: String,
    val userFacingMessage: String? = null,
) : Exception(message) {

    val displayMessage: String get() = userFacingMessage ?: message

    override fun toString(): String = "TdLibException($code): $message"

    companion object {
        fun clientNotInitialized() = TdLibException(
            code = "CLIENT_NOT_INITIALIZED",
            message = "TDLib client not initialized",
            userFacingMessage = "Telegram is reconnecting. Please wait and try again.",
        )

        fun notConnected() = TdLibException(
            code = "NOT_CONNECTED",
            message = "Not connected to TDLib",
            userFacingMessage = "Telegram is reconnecting. Please wait and try again.",
        )

        fun fromResponse(response: Map<String, dynamic>): TdLibException {
            val status = response["@type"]?.toString() ?: "UNKNOWN_ERROR"
            val message = response["message"]?.toString() ?: "Unknown error"
            val code = if (message.isNotEmpty()) message else status
            return TdLibException(
                code = code,
                message = message,
                userFacingMessage = mapErrorToUserMessage(code),
            )
        }

        private fun mapErrorToUserMessage(code: String): String {
            return when {
                code.startsWith("FLOOD_WAIT") -> {
                    val seconds = code.removePrefix("FLOOD_WAIT_")
                    "Too many attempts. Please wait $seconds seconds before trying again."
                }
                code == "PHONE_INVALID" || code == "PHONE_NUMBER_INVALID" ->
                    "Invalid phone number. Please check and try again."
                code == "PHONE_CODE_INVALID" || code == "CODE_INVALID" ->
                    "Invalid verification code. Please try again."
                code == "PHONE_CODE_EXPIRED" ->
                    "Verification code expired. Please request a new one."
                code == "PASSWORD_HASH_INVALID" || code == "PASSWORD_INVALID" ->
                    "Incorrect password. Please try again."
                code == "AUTH_KEY_UNREGISTERED" || code == "AUTH_KEY_INVALID" ->
                    "Session expired. Please log in again."
                code == "USER_DEACTIVATED" || code == "USER_DEACTIVATED_BAN" ->
                    "This account has been deactivated."
                code == "CHANNEL_PRIVATE" || code == "CHAT_ADMIN_REQUIRED" ->
                    "Storage channel not accessible."
                code == "NETWORK_ERROR" || code == "TIMEOUT" ->
                    "Network error. Check your connection."
                code == "FILE_NOT_FOUND" ->
                    "File no longer available."
                else -> "Something went wrong. Please try again."
            }
        }
    }
}
