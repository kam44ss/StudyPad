package com.mathlessons.app.data

import com.mathlessons.app.model.AnswerHintResponse
import com.mathlessons.app.model.BundleInfo
import com.mathlessons.app.model.BundleLessonLink
import com.mathlessons.app.model.CheckAnswerRequest
import com.mathlessons.app.model.CheckAnswerResponse
import com.mathlessons.app.model.ClientErrorRequest
import com.mathlessons.app.model.Flashcard
import com.mathlessons.app.model.LeaderboardEntry
import com.mathlessons.app.model.LeaderboardResponse
import com.mathlessons.app.model.Lesson
import com.mathlessons.app.model.LessonAnswer
import com.mathlessons.app.model.LessonContentResponse
import com.mathlessons.app.model.LessonQuestion
import com.mathlessons.app.model.MarkCompleteResponse
import com.mathlessons.app.model.ParentViewTokenResponse
import com.mathlessons.app.model.PracticeSetRequest
import com.mathlessons.app.model.PracticeSetResponse
import com.mathlessons.app.model.Purchase
import com.mathlessons.app.model.RedeemCodeRequest
import com.mathlessons.app.model.RedeemCodeResponse
import com.mathlessons.app.model.ReviewUpsert
import com.mathlessons.app.model.StreakInfo
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.ktor.client.call.body

class LessonsRepository {

    private val supabase = SupabaseClientProvider.client

    /** يرسل كود مكوّن من 6 أرقام للبريد الإلكتروني */
    suspend fun sendLoginCode(email: String) {
        supabase.auth.signInWith(OTP) {
            this.email = email
        }
    }

    /**
     * يتحقق من الكود اللي وصل بالبريد ويفعّل الجلسة مباشرة داخل التطبيق نفسه -
     * بدون أي حاجة لإعداد Deep Link/App Link (الطريقة الأبسط والأضمن لتطبيق أندرويد).
     */
    suspend fun verifyLoginCode(email: String, code: String) {
        supabase.auth.verifyEmailOtp(
            type = OtpType.Email.EMAIL,
            email = email,
            token = code
        )
    }

    fun isLoggedIn(): Boolean = supabase.auth.currentUserOrNull() != null

    suspend fun signOut() {
        supabase.auth.signOut()
    }

    /**
     * يرجع الدروس اللي اشتراها الطالب فعلاً فقط - ما فيه أي عرض لدروس غير مشتراة
     * للبيع (التطبيق "عارض" فقط، الشراء يصير من الموقع خارج التطبيق).
     */
    suspend fun getMyPurchasedLessons(): List<Lesson> {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return emptyList()

        val purchases = supabase.postgrest["purchases"]
            .select(columns = Columns.list("lesson_id")) {
                filter { eq("student_id", userId) }
            }
            .decodeList<Purchase>()

        val lessonIds = purchases.map { it.lessonId }.distinct()
        if (lessonIds.isEmpty()) return emptyList()

        return supabase.postgrest["lessons"]
            .select {
                filter { isIn("id", lessonIds) }
            }
            .decodeList<Lesson>()
    }

    /**
     * يرجع الحزم اللي عند الطالب على الأقل درس واحد منها مشترى - تُستخدم كقائمة
     * اختيار بشاشة الامتحان الشامل بدل ما يكتب معرّف الحزمة يدوياً (uuid خام).
     * ملاحظة: هذا لا يعني إنه اشترى الحزمة كاملة - التحقق الفعلي من الشراء
     * الكامل يصير بالسيرفر (generate_practice_set) وقت بدء الامتحان.
     */
    suspend fun getMyBundles(): List<BundleInfo> {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return emptyList()

        val purchases = supabase.postgrest["purchases"]
            .select(columns = Columns.list("lesson_id")) {
                filter { eq("student_id", userId) }
            }
            .decodeList<Purchase>()

        val lessonIds = purchases.map { it.lessonId }.distinct()
        if (lessonIds.isEmpty()) return emptyList()

        val links = supabase.postgrest["bundle_lessons"]
            .select(columns = Columns.list("bundle_id", "lesson_id")) {
                filter { isIn("lesson_id", lessonIds) }
            }
            .decodeList<BundleLessonLink>()

        val bundleIds = links.map { it.bundleId }.distinct()
        if (bundleIds.isEmpty()) return emptyList()

        return supabase.postgrest["bundles"]
            .select(columns = Columns.list("id", "title")) {
                filter { isIn("id", bundleIds) }
            }
            .decodeList<BundleInfo>()
    }

    /** يفعّل كود تفعيل عبر Edge Function - كل التحقق والمحاسبة يصير بالسيرفر */
    suspend fun redeemCode(code: String): RedeemCodeResponse {
        return try {
            supabase.functions.invoke(
                function = "redeem-code",
                body = RedeemCodeRequest(code = code)
            ).body()
        } catch (e: Exception) {
            RedeemCodeResponse(status = "error", error = e.message ?: "خطأ غير متوقع")
        }
    }

    /** يجلب محتوى الدرس (فيديو/PDF/اختبار) - يرفض السيرفر الطلب لو ما فيه شراء فعلي */
    suspend fun getLessonContent(lessonId: String): LessonContentResponse {
        return supabase.functions.invoke(
            function = "get-lesson-content",
            body = mapOf("lessonId" to lessonId)
        ).body()
    }

    /**
     * يعلّم الدرس كمكتمل - وإذا أكمل الطالب كل دروس حزمة معيّنة، يصدر النظام
     * شهادة تلقائياً ويرجع تفاصيلها هنا.
     */
    suspend fun markLessonComplete(lessonId: String): MarkCompleteResponse {
        return supabase.functions.invoke(
            function = "mark-lesson-complete",
            body = mapOf("lessonId" to lessonId)
        ).body()
    }

    /**
     * يضيف أو يعدّل تقييم الطالب لدرس اشتراه فعلاً - upsert لأن كل طالب
     * له تقييم واحد فقط لكل درس (قيد فريد بقاعدة البيانات).
     */
    suspend fun submitReview(lessonId: String, rating: Int, comment: String?) {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return
        supabase.postgrest["lesson_reviews"].upsert(
            ReviewUpsert(lessonId = lessonId, studentId = userId, rating = rating, comment = comment)
        ) {
            onConflict = "lesson_id,student_id"
        }
    }

    /**
     * يتحقق من إجابة سؤال اختبار بالسيرفر - التطبيق ما يعرف الإجابة الصحيحة أبداً،
     * فقط يرسل اختيار الطالب ويستقبل صح/خطأ.
     */
    suspend fun checkQuizAnswer(questionId: String, selectedIndex: Int): CheckAnswerResponse {
        return supabase.functions.invoke(
            function = "check-quiz-answer",
            body = CheckAnswerRequest(questionId = questionId, selectedIndex = selectedIndex)
        ).body()
    }

    /** يسأل سؤال عن الدرس - أي طالب اشترى الدرس يقدر يجاوب (تعاون بين الطلاب) */
    suspend fun askLessonQuestion(lessonId: String, questionText: String) {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return
        supabase.postgrest["lesson_questions"].insert(
            mapOf("lesson_id" to lessonId, "student_id" to userId, "question_text" to questionText)
        )
    }

    suspend fun getLessonQuestions(lessonId: String): List<LessonQuestion> {
        return supabase.postgrest["lesson_questions"]
            .select { filter { eq("lesson_id", lessonId) } }
            .decodeList()
    }

    suspend fun getAnswersFor(questionId: String): List<LessonAnswer> {
        return supabase.postgrest["lesson_answers"]
            .select { filter { eq("question_id", questionId) } }
            .decodeList()
    }

    suspend fun answerLessonQuestion(questionId: String, answerText: String) {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return
        supabase.postgrest["lesson_answers"].insert(
            mapOf("question_id" to questionId, "responder_id" to userId, "answer_text" to answerText)
        )
    }

    /** يسجّل خطأ غير متوقع بالتطبيق - نفس فكرة سجل الأخطاء بالموقع، بديل بسيط عن Sentry */
    suspend fun logClientError(message: String, context: Map<String, String?> = emptyMap()) {
        try {
            supabase.functions.invoke(
                function = "log-client-error",
                body = ClientErrorRequest(platform = "android", message = message, context = context)
            )
        } catch (e: Exception) {
            // لا نطيح التطبيق بسبب فشل تسجيل خطأ ثانوي
        }
    }

    /** يجلب سلسلة الأيام المتتالية الحالية للطالب - 0 لو ما فيه أي نشاط بعد */
    suspend fun getMyStreak(): Int {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return 0
        return try {
            val row = supabase.postgrest["student_streaks"]
                .select { filter { eq("student_id", userId) } }
                .decodeSingleOrNull<StreakInfo>()
            row?.currentStreak ?: 0
        } catch (e: Exception) {
            0
        }
    }

    suspend fun getLeaderboard(): List<LeaderboardEntry> {
        val response: LeaderboardResponse = supabase.functions.invoke(
            function = "get-leaderboard"
        ).body()
        return response.leaderboard
    }

    /** تلميح محلي بدون ذكاء اصطناعي: يحذف خيارات خاطئة عشوائياً + تلميح نصي من المدرس إن وُجد */
    suspend fun getAnswerHint(questionId: String): AnswerHintResponse {
        return supabase.functions.invoke(
            function = "get-answer-hint",
            body = mapOf("questionId" to questionId)
        ).body()
    }

    suspend fun getFlashcards(lessonId: String): List<Flashcard> {
        return supabase.postgrest["flashcards"]
            .select { filter { eq("lesson_id", lessonId) } }
            .decodeList()
    }

    /** ينشئ رابط متابعة جديد لولي الأمر ويرجع الكود (يُبنى منه الرابط الكامل بالواجهة) */
    suspend fun createParentViewToken(): String {
        val response: ParentViewTokenResponse = supabase.functions.invoke(
            function = "create-parent-view-token"
        ).body()
        return response.token ?: ""
    }

    /**
     * يولّد مجموعة تمارين: mode = "daily" (يومي)، "custom" (مادة+عدد اختياريين)،
     * "review" (مراجعة أسئلة أخطأ فيها الطالب سابقاً)، أو "mock_exam" (يحتاج bundleId).
     */
    suspend fun generatePracticeSet(
        mode: String,
        subject: String? = null,
        count: Int? = null,
        bundleId: String? = null
    ): PracticeSetResponse {
        return supabase.functions.invoke(
            function = "generate-practice-set",
            body = PracticeSetRequest(mode = mode, subject = subject, count = count, bundleId = bundleId)
        ).body()
    }
}
