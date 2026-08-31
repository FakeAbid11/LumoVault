package com.lumovault.feature.onboarding.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.lumovault.core.device.DeviceBrand

@Composable
fun BackgroundPermissionsScreen(
    brand: DeviceBrand,
    onOpenSettings: () -> Unit,
    onSkip: () -> Unit,
) {
    val steps = when (brand) {
        DeviceBrand.XIAOMI -> listOf(
            "Open Settings > Apps > Manage Apps",
            "Find LumoVault and tap on it",
            "Tap 'Battery saver' and set to 'No restrictions'",
            "Go back, tap 'Autostart' and enable it",
            "Open Security app > Boost > Manage apps' battery usage",
            "Find LumoVault and disable optimization",
        )
        DeviceBrand.SAMSUNG -> listOf(
            "Open Settings > Battery and device care",
            "Tap Battery > Background usage limits",
            "Find LumoVault and remove from sleeping apps",
            "Go back, tap Never sleeping apps and add LumoVault",
        )
        DeviceBrand.HUAWEI -> listOf(
            "Open Settings > Battery",
            "Tap 'App launch' and find LumoVault",
            "Set to 'Manage manually' and enable all toggles",
            "Go back, tap 'Close apps' and ensure LumoVault is not listed",
        )
        DeviceBrand.ONEPLUS -> listOf(
            "Open Settings > Battery > Battery Optimization",
            "Find LumoVault and set to 'Don't optimize'",
            "Go back, tap 'More settings' > 'Optimize battery usage'",
            "Find LumoVault and disable optimization",
        )
        DeviceBrand.OPPO, DeviceBrand.REALME -> listOf(
            "Open Settings > Battery > More settings",
            "Tap 'Optimize battery use' and find LumoVault",
            "Set to 'Don't optimize'",
            "Go back, tap 'App battery management' and enable all toggles",
        )
        DeviceBrand.OTHER -> listOf(
            "Open your device Settings",
            "Find Battery or Battery Optimization",
            "Find LumoVault and set to 'Don't optimize'",
            "Also enable autostart if available",
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "Background Access",
            style = MaterialTheme.typography.headlineLarge,
            color = MaterialTheme.colorScheme.onSurface,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "To keep backing up your photos, LumoVault needs to run in the background.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(32.dp))

        steps.forEachIndexed { index, step ->
            StepItem(
                stepNumber = index + 1,
                text = step,
            )
            if (index < steps.lastIndex) {
                Spacer(modifier = Modifier.height(12.dp))
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = onOpenSettings,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Open Settings")
        }

        Spacer(modifier = Modifier.height(12.dp))

        OutlinedButton(
            onClick = onSkip,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Skip for now")
        }
    }
}

@Composable
private fun StepItem(stepNumber: Int, text: String) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
    ) {
        androidx.compose.foundation.layout.Box(
            modifier = Modifier
                .padding(end = 12.dp)
                .padding(top = 2.dp),
            contentAlignment = Alignment.Center,
        ) {
            androidx.compose.material3.Surface(
                modifier = Modifier,
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.primary,
            ) {
                Text(
                    text = stepNumber.toString(),
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
            }
        }
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}
