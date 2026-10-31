import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser, getUserRole } from "../_shared/supabaseAdmin.js";

/**
 * يتحقق من إجابة سؤال اختبار بالسيرفر فقط - correct_index لا يُرسَل أبداً للتطبيق،
 * فقط النتيجة (صح/خطأ). هذا يمنع أي طالب من رؤية الإجابة الصحيحة بفحص استجابة الشبكة.
 */
Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const admin = getAdminClient();
    const user = await getAuthenticatedUser(req, admin);
    if (!user) {
      return jsonResponse({ error: "يجب تسجيل الدخول أولاً" }, 401);
    }

    const { questionId, selectedIndex } = await req.json();
    if (!questionId || selectedIndex == null) {
      return jsonResponse({ error: "questionId و selectedIndex مطلوبان" }, 400);
    }

    const { data: question, error: qErr } = await admin
      .from("quiz_questions")
      .select("id, lesson_id, correct_index, explanation")
      .eq("id", questionId)
      .single();

    if (qErr || !question) {
      return jsonResponse({ error: "السؤال غير موجود" }, 404);
    }

    const role = await getUserRole(admin, user.id);
    const { data: lesson } = await admin
      .from("lessons")
      .select("teacher_id")
      .eq("id", question.lesson_id)
      .single();

    const isOwnerTeacher = role === "teacher" && lesson && lesson.teacher_id === user.id;
    const isAdminCaller = role === "admin";
    let hasAccess = isOwnerTeacher || isAdminCaller;

    if (!hasAccess) {
      const nowIso = new Date().toISOString();
      const { data: purchase } = await admin
        .from("purchases")
        .select("id, expires_at")
        .eq("student_id", user.id)
        .eq("lesson_id", question.lesson_id)
        .eq("status", "verified")
        .limit(1)
        .maybeSingle();
      hasAccess = !!purchase && (purchase.expires_at === null || purchase.expires_at > nowIso);
    }

    if (!hasAccess) {
      return jsonResponse({ error: "لم تشترِ هذا الدرس بعد" }, 403);
    }

    const isCorrect = Number(selectedIndex) === Number(question.correct_index);

    // نسجّل المحاولة لحساب لوحة الصدارة - لا نرسل هذا للتطبيق، فقط نخزّنه
    await admin.from("quiz_attempts").insert({
      student_id: user.id,
      question_id: questionId,
      correct: isCorrect,
    });

    // نسجّل نشاط اليوم لحساب سلسلة الأيام المتتالية (Streak)
    const { data: streak } = await admin.rpc("record_daily_activity", { p_student_id: user.id });

    return jsonResponse({
      correct: isCorrect,
      explanation: question.explanation || null,
      streak: streak || null,
    });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
