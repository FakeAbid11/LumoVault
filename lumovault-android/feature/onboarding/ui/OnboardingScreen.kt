package com.lumovault.feature.onboarding.ui

import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import com.lumovault.core.auth.AuthState
import com.lumovault.core.device.DeviceInfoService
import com.lumovault.feature.onboarding.viewmodel.OnboardingViewModel

@Composable
fun OnboardingScreen(
    onComplete: () -> Unit,
    viewModel: OnboardingViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val deviceInfo = remember { DeviceInfoService(context) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) {
            viewModel.onPermissionsGranted()
            viewModel.nextStep()
        }
    }

    // Complete onboarding when authenticated
    LaunchedEffect(uiState.authState) {
        if (uiState.authState == AuthState.AUTHENTICATED && uiState.step == OnboardingStep.TELEGRAM) {
            onComplete()
        }
    }

    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        AnimatedContent(
            targetState = uiState.step,
            transitionSpec = {
                if (targetState.ordinal > initialState.ordinal) {
                    slideInHorizontally { it } togetherWith slideOutHorizontally { -it }
                } else {
                    slideInHorizontally { -it } togetherWith slideOutHorizontally { it }
                }
            },
            label = "onboarding_step",
        ) { step ->
            when (step) {
                OnboardingStep.WELCOME -> {
                    WelcomeScreen(
                        onGetStarted = { viewModel.nextStep() },
                    )
                }

                OnboardingStep.PERMISSIONS -> {
                    PermissionsScreen(
                        onGrantPermissions = {
                            val permissions = mutableListOf<String>()
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                permissions.add(android.Manifest.permission.READ_MEDIA_IMAGES)
                                permissions.add(android.Manifest.permission.READ_MEDIA_VIDEO)
                            } else {
                                permissions.add(android.Manifest.permission.READ_EXTERNAL_STORAGE)
                            }
                            permissions.add(android.Manifest.permission.ACCESS_FINE_LOCATION)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                permissions.add(android.Manifest.permission.POST_NOTIFICATIONS)
                            }
                            permissionLauncher.launch(permissions.toTypedArray())
                        },
                        onSkip = { viewModel.nextStep() },
                    )
                }

                OnboardingStep.BACKGROUND_PERMISSIONS -> {
                    BackgroundPermissionsScreen(
                        brand = deviceInfo.brand,
                        onOpenSettings = {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            context.startActivity(intent)
                            viewModel.onBackgroundPermissionsExplained()
                        },
                        onSkip = { viewModel.nextStep() },
                    )
                }

                OnboardingStep.FOLDERS -> {
                    FolderSelectionScreen(
                        availableFolders = emptyList(), // TODO: Load from MediaStore
                        onFoldersSelected = { viewModel.onFoldersSelected(it) },
                        onNext = { viewModel.nextStep() },
                    )
                }

                OnboardingStep.TELEGRAM -> {
                    TelegramConnectScreen(
                        authState = uiState.authState,
                        phoneNumber = uiState.phoneNumber,
                        verificationCode = uiState.verificationCode,
                        password = uiState.password,
                        isLoading = uiState.isLoading,
                        error = uiState.error,
                        onPhoneNumberChanged = viewModel::onPhoneNumberChanged,
                        onVerificationCodeChanged = viewModel::onVerificationCodeChanged,
                        onPasswordChanged = viewModel::onPasswordChanged,
                        onSendPhoneNumber = viewModel::sendPhoneNumber,
                        onSubmitCode = viewModel::submitCode,
                        onSubmitPassword = viewModel::submitPassword,
                        onConnected = onComplete,
                    )
                }
            }
        }

        if (uiState.isLoading && uiState.authState != AuthState.AUTHENTICATED) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center),
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}
