package com.lumovault.app.navigation

import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.lumovault.core.theme.LumoVaultTheme

@Composable
fun AppShell(
    currentRoute: String?,
    onNavigate: (Screen) -> Unit,
) {
    NavigationBar {
        bottomNavItems.forEach { item ->
            val selected = currentRoute == item.screen.route
            NavigationBarItem(
                icon = {
                    Icon(
                        imageVector = item.icon,
                        contentDescription = item.label,
                    )
                },
                label = {
                    Text(
                        text = item.label,
                        fontSize = 12.sp,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    )
                },
                selected = selected,
                onClick = { onNavigate(item.screen) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = LumoVaultTheme.colorScheme.primary,
                    selectedTextColor = LumoVaultTheme.colorScheme.primary,
                    unselectedIconColor = LumoVaultTheme.colorScheme.onSurfaceVariant,
                    unselectedTextColor = LumoVaultTheme.colorScheme.onSurfaceVariant,
                    indicatorColor = LumoVaultTheme.colorScheme.primaryContainer,
                ),
            )
        }
    }
}
