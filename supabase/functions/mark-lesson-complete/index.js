import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser } from "../_shared/supabaseAdmin.js";

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

    const { data, error } = await admin.rpc("mark_lesson_complete", {
      p_lesson_id: lessonId,
      p_student_id: user.id,
    });

    if (error) {
      const knownErrors = { not_purchased: "لم تشترِ هذا الدرس بعد" };
      return jsonResponse({ error: knownErrors[error.message] || error.message }, 400);
    }

    const { data: streak } = await admin.rpc("record_daily_activity", { p_student_id: user.id });

    return jsonResponse({ ...data, streak: streak || null });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
