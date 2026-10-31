package com.mathlessons.app.model

import kotlinx.serialization.Serializable

@Serializable
data class Lesson(
    val id: String,
    val title: String,
    val subject: String? = null,
    val status: String? = null
)

@Serializable
data class BundleInfo(
    val id: String,
    val title: String
)

@Serializable
data class BundleLessonLink(
    @kotlinx.serialization.SerialName("bundle_id")
    val bundleId: String,
    @kotlinx.serialization.SerialName("lesson_id")
    val lessonId: String
)

@Serializable
data class Purchase(
    @kotlinx.serialization.SerialName("lesson_id")
    val lessonId: String
)

@Serializable
data class LessonContentItem(
    val id: String,
    val type: String, // "video" | "pdf" | "quiz"
    val url: String? = null,
    @kotlinx.serialization.SerialName("caption_url")
    val captionUrl: String? = null,
    @kotlinx.serialization.SerialName("order_index")
    val orderIndex: Int = 0
)

@Serializable
data class QuizQuestion(
    val id: String,
    val text: String,
    val choices: List<String>
)

@Serializable
data class LessonContentResponse(
    val content: List<LessonContentItem> = emptyList(),
    val questions: List<QuizQuestion> = emptyList()
)

@Serializable
data class LessonQuestion(
    val id: String,
    @kotlinx.serialization.SerialName("lesson_id")
    val lessonId: String,
    @kotlinx.serialization.SerialName("question_text")
    val questionText: String
)

@Serializable
data class LessonAnswer(
    val id: String,
    @kotlinx.serialization.SerialName("question_id")
    val questionId: String,
    @kotlinx.serialization.SerialName("answer_text")
    val answerText: String,
    @kotlinx.serialization.SerialName("is_teacher_answer")
    val isTeacherAnswer: Boolean = false
)

@Serializable
data class LeaderboardEntry(
    @kotlinx.serialization.SerialName("display_name")
    val displayName: String,
    @kotlinx.serialization.SerialName("correct_count")
    val correctCount: Int,
    @kotlinx.serialization.SerialName("total_attempts")
    val totalAttempts: Int
)

@Serializable
data class LeaderboardResponse(val leaderboard: List<LeaderboardEntry> = emptyList())

@Serializable
data class PracticeQuestion(
    val id: String,
    val text: String,
    val choices: List<String>
)

@Serializable
data class PracticeSetResponse(
    val mode: String = "",
    val questions: List<PracticeQuestion> = emptyList(),
    val error: String? = null
)

@Serializable
data class RedeemCodeRequest(val code: String)

@Serializable
data class StreakInfo(
    @kotlinx.serialization.SerialName("current_streak")
    val currentStreak: Int = 0,
    @kotlinx.serialization.SerialName("longest_streak")
    val longestStreak: Int = 0
)

@Serializable
data class CheckAnswerResponse(
    val correct: Boolean = false,
    val explanation: String? = null,
    val streak: StreakInfo? = null,
    val error: String? = null
)

@Serializable
data class AnswerHintResponse(
    @kotlinx.serialization.SerialName("eliminated_indexes")
    val eliminatedIndexes: List<Int> = emptyList(),
    val hint: String? = null,
    val error: String? = null
)

@Serializable
data class Flashcard(
    val id: String,
    @kotlinx.serialization.SerialName("front_text")
    val frontText: String,
    @kotlinx.serialization.SerialName("back_text")
    val backText: String
)

@Serializable
data class ParentViewTokenResponse(val token: String? = null, val error: String? = null)

@Serializable
data class NewCertificate(
    @kotlinx.serialization.SerialName("bundle_id")
    val bundleId: String,
    @kotlinx.serialization.SerialName("bundle_title")
    val bundleTitle: String
)

@Serializable
data class MarkCompleteResponse(
    val status: String = "",
    @kotlinx.serialization.SerialName("lesson_id")
    val lessonId: String? = null,
    @kotlinx.serialization.SerialName("bundle_id")
    val bundleId: String? = null,
    @kotlinx.serialization.SerialName("new_certificates")
    val newCertificates: List<NewCertificate> = emptyList(),
    val streak: StreakInfo? = null,
    val error: String? = null
)

@Serializable
data class RedeemCodeResponse(
    val status: String,
    @kotlinx.serialization.SerialName("lesson_id")
    val lessonId: String? = null,
    @kotlinx.serialization.SerialName("bundle_id")
    val bundleId: String? = null,
    @kotlinx.serialization.SerialName("lesson_ids")
    val lessonIds: List<String>? = null,
    val error: String? = null
)
