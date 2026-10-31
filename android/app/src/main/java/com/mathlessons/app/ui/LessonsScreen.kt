package com.mathlessons.app.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.mathlessons.app.data.LessonsRepository
import com.mathlessons.app.model.Lesson
import kotlinx.coroutines.launch

// دومين موقعك الفعلي بعد النشر - نفس اللي بـ SITE_URL بإعدادات Edge Functions
private const val WEBSITE_URL = "https://your-domain.com"

@Composable
fun LessonsScreen(
    repository: LessonsRepository,
    onOpenLesson: (Lesson) -> Unit,
    onOpenRedeem: () -> Unit,
    onOpenLeaderboard: () -> Unit,
    onOpenPractice: () -> Unit,
    onLoggedOut: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var lessons by remember { mutableStateOf<List<Lesson>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var continueWatching by remember { mutableStateOf<ContinueWatchingEntry?>(null) }
    var currentStreak by remember { mutableStateOf(0) }
    var parentViewLink by remember { mutableStateOf<String?>(null) }
    var generatingLink by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        try {
            lessons = repository.getMyPurchasedLessons()
        } catch (e: Exception) {
            error = e.message
        } finally {
            loading = false
        }
        continueWatching = getContinueWatching(context)
        try {
            currentStreak = repository.getMyStreak()
        } catch (e: Exception) {
            // لا نعرض خطأ لأجل هذا - مجرد مؤشر تحفيزي ثانوي
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("دروسي", style = MaterialTheme.typography.headlineSmall)
            TextButton(onClick = {
                scope.launch {
                    repository.signOut()
                    onLoggedOut()
                }
            }) { Text("خروج") }
        }

        if (currentStreak > 0) {
            Text("🔥 $currentStreak يوم متتالي", style = MaterialTheme.typography.bodyMedium)
        }

        Spacer(Modifier.height(8.dp))

        continueWatching?.let { entry ->
            val matchingLesson = lessons.find { it.id == entry.lessonId }
            Card(
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                onClick = { matchingLesson?.let { onOpenLesson(it) } }
            ) {
                Row(
                    modifier = Modifier.padding(12.dp).fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column {
                        Text("▶ متابعة المشاهدة", style = MaterialTheme.typography.labelMedium)
                        Text(entry.lessonTitle, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }

        // لا يوجد أي زر شراء أو سعر هنا داخل التطبيق - فقط رابط خارجي للموقع
        OutlinedButton(
            onClick = {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(WEBSITE_URL))
                context.startActivity(intent)
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("لشراء دروس جديدة، زور موقعنا")
        }

        Spacer(Modifier.height(8.dp))

        OutlinedButton(onClick = onOpenRedeem, modifier = Modifier.fillMaxWidth()) {
            Text("عندي كود تفعيل")
        }

        Spacer(Modifier.height(8.dp))

        Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(onClick = onOpenPractice, modifier = Modifier.weight(1f)) {
                Text("📝 تمارين")
            }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = onOpenLeaderboard, modifier = Modifier.weight(1f)) {
                Text("🏆 الصدارة")
            }
        }

        Spacer(Modifier.height(8.dp))

        OutlinedButton(
            onClick = {
                generatingLink = true
                scope.launch {
                    try {
                        val token = repository.createParentViewToken()
                        parentViewLink = "$WEBSITE_URL/parent-view.html?token=$token"
                    } catch (e: Exception) {
                        // نتجاهل بصمت
                    }
                    generatingLink = false
                }
            },
            enabled = !generatingLink,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (generatingLink) "جاري الإنشاء..." else "👪 إنشاء رابط متابعة لولي الأمر")
        }
        parentViewLink?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp))
        }

        Spacer(Modifier.height(16.dp))

        when {
            loading -> CircularProgressIndicator()
            error != null -> Text("خطأ: $error")
            lessons.isEmpty() -> Text("ما عندك دروس مفعّلة بعد.")
            else -> LazyColumn {
                items(lessons) { lesson ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 6.dp),
                        onClick = { onOpenLesson(lesson) }
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text(lesson.title, style = MaterialTheme.typography.titleMedium)
                            lesson.subject?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
        }
    }
}
