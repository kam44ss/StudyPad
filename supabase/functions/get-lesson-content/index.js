import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser, getUserRole } from "../_shared/supabaseAdmin.js";

/**
 * ترجع محتوى الدرس (فيديو/PDF/اختبار) فقط لو الطالب اشترى الدرس فعلاً
 * (أو هو مدرس الدرس نفسه، أو أدمن). هذا يسد الثغرة: lesson_content ما تُقرأ
 * مباشرة من العميل بأي حال (RLS تمنعها)، فقط عبر هذه الفنكشن بعد التحقق.
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

    const { lessonId } = await req.json();
    if (!lessonId) {
      return jsonResponse({ error: "lessonId مطلوب" }, 400);
    }

    const { data: lesson, error: lessonErr } = await admin
      .from("lessons")
      .select("id, teacher_id")
      .eq("id", lessonId)
      .single();

    if (lessonErr || !lesson) {
      return jsonResponse({ error: "الدرس غير موجود" }, 404);
    }

    const role = await getUserRole(admin, user.id);
    const isOwnerTeacher = role === "teacher" && lesson.teacher_id === user.id;
    const isAdminCaller = role === "admin";

    let hasAccess = isOwnerTeacher || isAdminCaller;

    if (!hasAccess) {
      const nowIso = new Date().toISOString();
      const { data: purchase } = await admin
        .from("purchases")
        .select("id, expires_at")
        .eq("student_id", user.id)
        .eq("lesson_id", lessonId)
        .eq("status", "verified")
        .limit(1)
        .maybeSingle();
      // expires_at = null يعني وصول دائم، وإلا لازم يكون لسا ما انتهى (اشتراك ساري)
      hasAccess = !!purchase && (purchase.expires_at === null || purchase.expires_at > nowIso);
    }

    if (!hasAccess) {
      return jsonResponse({ error: "لم تشترِ هذا الدرس بعد" }, 403);
    }

    const [{ data: content }, { data: questions }] = await Promise.all([
      admin
        .from("lesson_content")
        .select("id, type, url, caption_url, order_index")
        .eq("lesson_id", lessonId)
        .order("order_index", { ascending: true }),
      admin
        .from("quiz_questions")
        .select("id, text, choices") // لا نرسل correct_index أبداً - التحقق من الإجابة يصير بالسيرفر فقط
        .eq("lesson_id", lessonId),
    ]);

    // "url" المخزّن بالجدول هو مسار داخل bucket خاص (لو ملف مرفوع)، أو رابط خارجي
    // كامل (يوتيوب/فيميو). نولّد رابط موقّع مؤقت للملفات الداخلية فقط، صالح لساعة واحدة.
    async function signIfInternal(path) {
      if (!path || /^https?:\/\//i.test(path)) {
        return path; // رابط خارجي جاهز أصلاً، أو فارغ
      }
      const { data: signed } = await admin.storage
        .from("lesson-content")
        .createSignedUrl(path, 3600);
      return signed ? signed.signedUrl : null;
    }

    const signedContent = await Promise.all(
      (content || []).map(async (item) => ({
        ...item,
        url: await signIfInternal(item.url),
        caption_url: await signIfInternal(item.caption_url),
      }))
    );

    return jsonResponse({ content: signedContent, questions: questions || [] });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
