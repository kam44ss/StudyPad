import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient } from "../_shared/supabaseAdmin.js";

/**
 * صفحة ولي الأمر - بدون تسجيل دخول إطلاقاً، فقط بامتلاك رابط/كود صحيح.
 * تكشف فقط تقدم الطالب (دروس، شهادات، سلسلة الأيام) - بدون أي بيانات حساسة
 * (لا بريد، لا فلوس، لا شيء مالي).
 */
Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const admin = getAdminClient();
    const { token } = await req.json();
    if (!token) {
      return jsonResponse({ error: "token مطلوب" }, 400);
    }

    const { data, error } = await admin.rpc("get_parent_view", { p_token: token });
    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    return jsonResponse(data);
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
