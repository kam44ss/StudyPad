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
import com.mathlessons.app.model.LessonContentResponse
import kotlinx.coroutines.launch

@Composable
fun LessonViewerScreen(repository: LessonsRepository, lessonId: String, lessonTitle: String) {
    var data by remember { mutableStateOf<LessonContentResponse?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(lessonId) {
        try {
            data = repository.getLessonContent(lessonId)
        } catch (e: Exception) {
            error = e.message
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Text(lessonTitle, style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(16.dp))

        when {
            error != null -> Text("خطأ: $error")
            data == null -> CircularProgressIndicator()
            else -> LazyColumn {
                items(data!!.content) { item ->
                    ContentItemCard(item = item, repository = repository, lessonId = lessonId, lessonTitle = lessonTitle)
                }

                item {
                    Spacer(Modifier.height(16.dp))
                    MarkCompleteSection(repository = repository, lessonId = lessonId)
                }

                if (data!!.questions.isNotEmpty()) {
                    item {
                        Spacer(Modifier.height(16.dp))
                        Text("اختبار قصير", style = MaterialTheme.typography.titleMedium)
                    }
                    items(data!!.questions) { q ->
                        QuizQuestionCard(repository = repository, question = q)
                    }
                }

                item {
                    Spacer(Modifier.height(24.dp))
                    QASection(repository = repository, lessonId = lessonId)
                }

                item {
                    Spacer(Modifier.height(24.dp))
                    ReviewSection(repository = repository, lessonId = lessonId)
                }
            }
        }
    }
}

@Composable
private fun MarkCompleteSection(repository: LessonsRepository, lessonId: String) {
    val scope = rememberCoroutineScope()
    var done by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var certMessage by remember { mutableStateOf<String?>(null) }

    Column {
        Button(
            onClick = {
                loading = true
                scope.launch {
                    try {
                        val result = repository.markLessonComplete(lessonId)
                        done = true
                        if (result.newCertificates.isNotEmpty()) {
                            certMessage = "🎓 مبروك! حصلت على شهادة إتمام: " +
                                result.newCertificates.joinToString(", ") { it.bundleTitle }
                        }
                    } catch (e: Exception) {
                        // نتجاهل بصمت - يقدر يعيد المحاولة
                    } finally {
                        loading = false
                    }
                }
            },
            enabled = !done && !loading
        ) {
            Text(
                when {
                    loading -> "جاري الحفظ..."
                    done -> "تم إكمال الدرس ✅"
                    else -> "علّم الدرس كمكتمل"
                }
            )
        }
        certMessage?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun QASection(repository: LessonsRepository, lessonId: String) {
    val scope = rememberCoroutineScope()
    var questions by remember { mutableStateOf<List<com.mathlessons.app.model.LessonQuestion>>(emptyList()) }
    var newQuestion by remember { mutableStateOf("") }
    var submitting by remember { mutableStateOf(false) }

    suspend fun reload() {
        try {
            questions = repository.getLessonQuestions(lessonId)
        } catch (e: Exception) {
            // نتجاهل بصمت - القائمة تبقى فارغة
        }
    }

    LaunchedEffect(lessonId) { reload() }

    Column {
        Text("أسئلة الطلاب", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))

        Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = newQuestion,
                onValueChange = { newQuestion = it },
                label = { Text("اسأل سؤالاً عن هذا الدرس") },
                modifier = Modifier.weight(1f)
            )
            Button(
                onClick = {
                    submitting = true
                    scope.launch {
                        try {
                            repository.askLessonQuestion(lessonId, newQuestion.trim())
                            newQuestion = ""
                            reload()
                        } catch (e: Exception) {
                            // نتجاهل بصمت
                        } finally {
                            submitting = false
                        }
                    }
                },
                enabled = newQuestion.isNotBlank() && !submitting,
                modifier = Modifier.padding(start = 8.dp)
            ) {
                Text("إرسال")
            }
        }

        Spacer(Modifier.height(12.dp))

        questions.forEach { q ->
            QuestionWithAnswers(repository = repository, question = q)
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun QuestionWithAnswers(repository: LessonsRepository, question: com.mathlessons.app.model.LessonQuestion) {
    val scope = rememberCoroutineScope()
    var answers by remember { mutableStateOf<List<com.mathlessons.app.model.LessonAnswer>>(emptyList()) }
    var newAnswer by remember { mutableStateOf("") }
    var showAnswerBox by remember { mutableStateOf(false) }

    LaunchedEffect(question.id) {
        try {
            answers = repository.getAnswersFor(question.id)
        } catch (e: Exception) {
            // نتجاهل بصمت
        }
    }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(question.questionText, style = MaterialTheme.typography.bodyMedium)

            answers.forEach { a ->
                Text(
                    "↳ ${a.answerText}${if (a.isTeacherAnswer) " (المدرس)" else ""}",
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(top = 4.dp, start = 12.dp)
                )
            }

            if (!showAnswerBox) {
                TextButton(onClick = { showAnswerBox = true }) {
                    Text("جاوب على هذا السؤال")
                }
            } else {
                Row {
                    OutlinedTextField(
                        value = newAnswer,
                        onValueChange = { newAnswer = it },
                        modifier = Modifier.weight(1f)
                    )
                    Button(
                        onClick = {
                            scope.launch {
                                try {
                                    repository.answerLessonQuestion(question.id, newAnswer.trim())
                                    answers = repository.getAnswersFor(question.id)
                                    newAnswer = ""
                                    showAnswerBox = false
                                } catch (e: Exception) {
                                    // نتجاهل بصمت
                                }
                            }
                        },
                        enabled = newAnswer.isNotBlank(),
                        modifier = Modifier.padding(start = 8.dp)
                    ) {
                        Text("إرسال")
                    }
                }
            }
        }
    }
}

@Composable
private fun ReviewSection(repository: LessonsRepository, lessonId: String) {
    val scope = rememberCoroutineScope()
    var rating by remember { mutableStateOf(0) }
    var comment by remember { mutableStateOf("") }
    var submitting by remember { mutableStateOf(false) }
    var submitted by remember { mutableStateOf(false) }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("قيّم هذا الدرس", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))

            Row {
                for (star in 1..5) {
                    IconToggleButton(
                        checked = star <= rating,
                        onCheckedChange = { rating = star }
                    ) {
                        Text(if (star <= rating) "★" else "☆", style = MaterialTheme.typography.headlineSmall)
                    }
                }
            }

            OutlinedTextField(
                value = comment,
                onValueChange = { comment = it },
                label = { Text("تعليق (اختياري)") },
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(Modifier.height(8.dp))

            Button(
                onClick = {
                    submitting = true
                    scope.launch {
                        try {
                            repository.submitReview(lessonId, rating, comment.ifBlank { null })
                            submitted = true
                        } catch (e: Exception) {
                            // نتجاهل بصمت هنا لتبسيط الواجهة - يقدر يعيد المحاولة
                        } finally {
                            submitting = false
                        }
                    }
                },
                enabled = rating > 0 && !submitting
            ) {
                Text(
                    when {
                        submitting -> "جاري الإرسال..."
                        submitted -> "تم الإرسال ✅ (اضغط للتعديل)"
                        else -> "إرسال التقييم"
                    }
                )
            }
        }
    }
}

@Composable
private fun ContentItemCard(
    item: com.mathlessons.app.model.LessonContentItem,
    repository: LessonsRepository,
    lessonId: String,
    lessonTitle: String
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var expanded by remember { mutableStateOf(false) }
    var autoCompleteMessage by remember { mutableStateOf<String?>(null) }

    Card(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Column {
            Row(
                modifier = Modifier
                    .padding(16.dp)
                    .fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(labelFor(item.type))
                TextButton(onClick = {
                    if (item.type == "video") {
                        expanded = !expanded
                    } else {
                        // ملفات PDF حالياً تُفتح بتطبيق/متصفح خارجي - عارض PDF مدمج
                        // بالتطبيق نفسه يبقى تحسين مستقبلي منفصل
                        item.url?.let {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it)))
                        }
                    }
                }) {
                    Text(
                        when {
                            item.type == "video" && expanded -> "إخفاء ▲"
                            item.type == "video" -> "تشغيل ▼"
                            else -> "فتح ←"
                        }
                    )
                }
            }

            if (item.type == "video" && !expanded && item.url != null) {
                VideoThumbnail(
                    url = item.url,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f)
                )
            }

            if (item.type == "video" && expanded && item.url != null) {
                when (val source = resolveVideoSource(item.url)) {
                    is VideoSource.DirectFile -> DirectVideoPlayer(
                        url = source.url,
                        contentId = item.id,
                        lessonId = lessonId,
                        lessonTitle = lessonTitle,
                        captionUrl = item.captionUrl,
                        onVideoCompleted = {
                            // نعلّم الدرس مكتمل تلقائياً بمجرد ما يخلص الفيديو - بدون
                            // ما يحتاج الطالب يضغط الزر يدوياً بالأسفل
                            scope.launch {
                                try {
                                    val result = repository.markLessonComplete(lessonId)
                                    if (result.newCertificates.isNotEmpty()) {
                                        autoCompleteMessage = "🎓 مبروك! حصلت على شهادة إتمام: " +
                                            result.newCertificates.joinToString(", ") { it.bundleTitle }
                                    }
                                } catch (e: Exception) {
                                    // نتجاهل بصمت - زر "علّم الدرس كمكتمل" بالأسفل يبقى متاح كبديل
                                }
                            }
                        }
                    )
                    is VideoSource.YouTube -> EmbeddedWebPlayer(source.embedUrl)
                    is VideoSource.Vimeo -> EmbeddedWebPlayer(source.embedUrl)
                }
            }

            autoCompleteMessage?.let {
                Text(
                    it,
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

private fun labelFor(type: String) = when (type) {
    "video" -> "🎬 فيديو"
    "pdf" -> "📄 ملف PDF"
    else -> "محتوى"
}

@Composable
private fun QuizQuestionCard(repository: LessonsRepository, question: com.mathlessons.app.model.QuizQuestion) {
    val scope = rememberCoroutineScope()
    var selectedIndex by remember { mutableStateOf(-1) }
    var result by remember { mutableStateOf<Boolean?>(null) }
    var explanation by remember { mutableStateOf<String?>(null) }
    var checking by remember { mutableStateOf(false) }

    Card(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(question.text, style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(8.dp))

            question.choices.forEachIndexed { index, choice ->
                val isSelected = index == selectedIndex
                val bg = when {
                    result == null -> null
                    isSelected && result == true -> "correct"
                    isSelected && result == false -> "wrong"
                    else -> null
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 2.dp),
                ) {
                    RadioButton(
                        selected = isSelected,
                        onClick = {
                            if (result == null) {
                                selectedIndex = index
                            }
                        },
                        enabled = result == null
                    )
                    Text(
                        choice,
                        modifier = Modifier.padding(top = 12.dp),
                        color = when (bg) {
                            "correct" -> androidx.compose.ui.graphics.Color(0xFF2F5D50)
                            "wrong" -> androidx.compose.ui.graphics.Color(0xFFA4342A)
                            else -> MaterialTheme.colorScheme.onSurface
                        }
                    )
                }
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
                    Text(if (checking) "جاري التحقق..." else "تحقق من الإجابة")
                }
            } else {
                Text(
                    if (result == true) "إجابة صحيحة ✅" else "إجابة خاطئة ❌",
                    style = MaterialTheme.typography.bodyMedium
                )
                explanation?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "الشرح: $it",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }
    }
}
