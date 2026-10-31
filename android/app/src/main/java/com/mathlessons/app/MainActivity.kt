package com.mathlessons.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import com.mathlessons.app.data.LessonsRepository
import com.mathlessons.app.model.Lesson
import com.mathlessons.app.ui.LeaderboardScreen
import com.mathlessons.app.ui.LessonViewerScreen
import com.mathlessons.app.ui.LessonsScreen
import com.mathlessons.app.ui.LoginScreen
import com.mathlessons.app.ui.PracticeScreen
import com.mathlessons.app.ui.RedeemCodeScreen
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

private sealed class Screen {
    data object Login : Screen()
    data object Lessons : Screen()
    data object Redeem : Screen()
    data object Leaderboard : Screen()
    data object Practice : Screen()
    data class Viewer(val lesson: Lesson) : Screen()
}

class MainActivity : ComponentActivity() {
    @OptIn(DelicateCoroutinesApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val repository = LessonsRepository()

        // نسجّل أي كراش غير متوقع بالتطبيق قبل ما ينهار - بديل بسيط عن Sentry.
        // نستخدم GlobalScope هنا فقط لأن التطبيق على وشك الانهيار أصلاً (أي Scope
        // عادي بينلغى فوراً)، ونحدد مهلة قصيرة عشان ما نأخّر انهيار التطبيق كثير.
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            GlobalScope.launch {
                withTimeoutOrNull(2000) {
                    repository.logClientError(
                        throwable.message ?: throwable.toString(),
                        mapOf("stack" to throwable.stackTraceToString().take(1500))
                    )
                }
            }
            defaultHandler?.uncaughtException(thread, throwable)
        }

        setContent {
            MaterialTheme {
                Surface(modifier = Modifier) {
                    var screen by remember {
                        mutableStateOf<Screen>(
                            if (repository.isLoggedIn()) Screen.Lessons else Screen.Login
                        )
                    }

                    when (val current = screen) {
                        is Screen.Login -> LoginScreen(
                            repository = repository,
                            onLoggedIn = { screen = Screen.Lessons }
                        )
                        is Screen.Lessons -> LessonsScreen(
                            repository = repository,
                            onOpenLesson = { lesson -> screen = Screen.Viewer(lesson) },
                            onOpenRedeem = { screen = Screen.Redeem },
                            onOpenLeaderboard = { screen = Screen.Leaderboard },
                            onOpenPractice = { screen = Screen.Practice },
                            onLoggedOut = { screen = Screen.Login }
                        )
                        is Screen.Redeem -> RedeemCodeScreen(
                            repository = repository,
                            onDone = { screen = Screen.Lessons }
                        )
                        is Screen.Leaderboard -> LeaderboardScreen(repository = repository)
                        is Screen.Practice -> PracticeScreen(repository = repository)
                        is Screen.Viewer -> LessonViewerScreen(
                            repository = repository,
                            lessonId = current.lesson.id,
                            lessonTitle = current.lesson.title
                        )
                    }
                }
            }
        }
    }
}
