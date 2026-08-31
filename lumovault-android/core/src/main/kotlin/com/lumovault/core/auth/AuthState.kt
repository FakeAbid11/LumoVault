package com.lumovault.core.auth

enum class AuthState {
    UNAUTHENTICATED,
    PHONE_REQUESTED,
    CODE_REQUESTED,
    PASSWORD_REQUESTED,
    AUTHENTICATED,
}

sealed class AuthEvent {
    data object PhoneRequested : AuthEvent()
    data object CodeRequested : AuthEvent()
    data object PasswordRequested : AuthEvent()
    data object Authenticated : AuthEvent()
    data class Error(val message: String) : AuthEvent()
}
