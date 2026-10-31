package com.mathlessons.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mathlessons.app.data.LessonsRepository

@Composable
fun LeaderboardScreen(repository: LessonsRepository) {
    var entries by remember { mutableStateOf<List<com.mathlessons.app.model.LeaderboardEntry>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        try {
            entries = repository.getLeaderboard()
        } catch (e: Exception) {
            error = e.message
        } finally {
            loading = false
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Text("🏆 لوحة الصدارة", style = MaterialTheme.typography.headlineSmall)
        Text(
            "مبنية على عدد الإجابات الصحيحة بالاختبارات",
            style = MaterialTheme.typography.bodySmall
        )
        Spacer(Modifier.height(16.dp))

        when {
            loading -> CircularProgressIndicator()
            error != null -> Text("خطأ: $error")
            entries.isEmpty() -> Text("لا توجد بيانات كافية بعد.")
            else -> LazyColumn {
                itemsIndexed(entries) { index, entry ->
                    Card(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Row(
                            modifier = Modifier.padding(12.dp).fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("${index + 1}. ${entry.displayName}")
                            Text("${entry.correctCount} إجابة صحيحة")
                        }
                    }
                }
            }
        }
    }
}
