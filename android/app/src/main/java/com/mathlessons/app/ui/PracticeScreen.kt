package com.mathlessons.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mathlessons.app.data.LessonsRepository
import com.mathlessons.app.model.PracticeQuestion
import kotlinx.coroutines.launch

/**
 * شاشة تمارين موحّدة تخدم 3 حالات: اختبار يومي، اختبار مخصص بمادة معيّنة،
 * وامتحان شامل تجريبي لحزمة كاملة (يحتاج bundleId).
 */
@Composable
fun PracticeScreen(repository: LessonsRepository) {
    var mode by remember { mutableStateOf<String?>(null) }
    var subject by remember { mutableStateOf("") }
    var selectedBundle by remember { mutableStateOf<com.mathlessons.app.model.BundleInfo?>(null) }
    var bundleDropdownExpanded by remember { mutableStateOf(false) }
    var myBundles by remember { mutableStateOf<List<com.mathlessons.app.model.BundleInfo>>(emptyList()) }
    var questions by remember { mutableStateOf<List<PracticeQuestion>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        try {
            myBundles = repository.getMyBundles()
        } catch (e: Exception) {
            // قائمة فارغة كافية - الطالب ببساطة ما يشوف خيارات بالامتحان الشامل
        }
    }

    fun startPractice(selectedMode: String) {
        loading = true
        error = null
        scope.launch {
            try {
                val result = repository.generatePracticeSet(
                    mode = selectedMode,
                    subject = subject.ifBlank { null },
                    bundleId = if (selectedMode == "mock_exam") selectedBundle?.id else null
                )
                if (result.questions.isEmpty()) {
                    error = "لا توجد أسئلة متاحة حالياً بهذي الفلاتر"
                } else {
                    questions = result.questions
                    mode = selectedMode
                }
            } catch (e: Exception) {
                error = e.message
            } finally {
                loading = false
            }
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        if (mode == null) {
            Text("تمارين", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(16.dp))

            Button(onClick = { startPractice("daily") }, modifier = Modifier.fillMaxWidth()) {
                Text("اختبار اليوم")
            }

            Spacer(Modifier.height(8.dp))
            Button(onClick = { startPractice("review") }, modifier = Modifier.fillMaxWidth()) {
                Text("🔁 مراجعة أسئلتي الخاطئة")
            }

            Spacer(Modifier.height(12.dp))
            Text("اختبار مخصص", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                value = subject,
                onValueChange = { subject = it },
                label = { Text("المادة (اختياري)") },
                modifier = Modifier.fillMaxWidth()
            )
            Button(
                onClick = { startPractice("custom") },
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
            ) {
                Text("ابدأ اختبار مخصص")
            }

            Spacer(Modifier.height(12.dp))
            Text("امتحان شامل تجريبي", style = MaterialTheme.typography.titleMedium)

            if (myBundles.isEmpty()) {
                Text(
                    "ما عندك حزمة مشترى منها درس بعد.",
                    style = MaterialTheme.typography.bodySmall
                )
            } else {
                Box {
                    OutlinedButton(
                        onClick = { bundleDropdownExpanded = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(selectedBundle?.title ?: "اختر حزمة")
                    }
                    DropdownMenu(
                        expanded = bundleDropdownExpanded,
                        onDismissRequest = { bundleDropdownExpanded = false }
                    ) {
                        myBundles.forEach { bundle ->
                            DropdownMenuItem(
                                text = { Text(bundle.title) },
                                onClick = {
                                    selectedBundle = bundle
                                    bundleDropdownExpanded = false
                                }
                            )
                        }
                    }
                }
            }

            Button(
                onClick = { startPractice("mock_exam") },
                enabled = selectedBundle != null,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
            ) {
                Text("ابدأ الامتحان الشامل")
            }

            if (loading) {
                Spacer(Modifier.height(12.dp))
                CircularProgressIndicator()
            }
            error?.let {
                Spacer(Modifier.height(12.dp))
                Text(it, color = androidx.compose.ui.graphics.Color(0xFFA4342A))
            }
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    when (mode) {
                        "daily" -> "اختبار اليوم"
                        "mock_exam" -> "امتحان شامل"
                        "review" -> "مراجعة الأخطاء"
                        else -> "اختبار مخصص"
                    },
                    style = MaterialTheme.typography.headlineSmall
                )
                TextButton(onClick = { mode = null; questions = emptyList() }) {
                    Text("إنهاء")
                }
            }
            Spacer(Modifier.height(12.dp))
            LazyColumn {
                items(questions) { q ->
                    PracticeQuestionCard(repository = repository, question = q)
                }
            }
        }
    }
}

@Composable
private fun PracticeQuestionCard(repository: LessonsRepository, question: PracticeQuestion) {
    val scope = rememberCoroutineScope()
    var selectedIndex by remember { mutableStateOf(-1) }
    var result by remember { mutableStateOf<Boolean?>(null) }
    var explanation by remember { mutableStateOf<String?>(null) }
    var checking by remember { mutableStateOf(false) }
    var eliminatedIndexes by remember { mutableStateOf<List<Int>>(emptyList()) }
    var hintText by remember { mutableStateOf<String?>(null) }
    var loadingHint by remember { mutableStateOf(false) }

    Card(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(question.text, style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(8.dp))

            question.choices.forEachIndexed { index, choice ->
                if (index !in eliminatedIndexes) {
                    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                        RadioButton(
                            selected = index == selectedIndex,
                            onClick = { if (result == null) selectedIndex = index },
                            enabled = result == null
                        )
                        Text(choice, modifier = Modifier.padding(top = 12.dp))
                    }
                }
            }

            if (result == null && eliminatedIndexes.isEmpty()) {
                TextButton(
                    onClick = {
                        loadingHint = true
                        scope.launch {
                            try {
                                val hint = repository.getAnswerHint(question.id)
                                eliminatedIndexes = hint.eliminatedIndexes
                                hintText = hint.hint
                            } catch (e: Exception) {
                                // نتجاهل بصمت
                            }
                            loadingHint = false
                        }
                    },
                    enabled = !loadingHint
                ) {
                    Text(if (loadingHint) "..." else "💡 تلميح")
                }
            }
            hintText?.let {
                Text("تلميح المدرس: $it", style = MaterialTheme.typography.bodySmall)
            }

            Spacer(Modifier.height(8.dp))

            if (result == null) {
                Button(
                    onClick = {
                        checking = true
                        scope.launch {
                            try {
                                val response = repository.checkQuizAnswer(question.id, selectedIndex)
                                result = response.correct
                                explanation = response.explanation
                            } catch (e: Exception) {
                                result = null
                            }
                            checking = false
                        }
                    },
                    enabled = selectedIndex >= 0 && !checking
                ) {
                    Text(if (checking) "جاري التحقق..." else "تحقق")
                }
            } else {
                Text(if (result == true) "✅ صحيح" else "❌ خطأ")
                explanation?.let {
                    Text("الشرح: $it", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
