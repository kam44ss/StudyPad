import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser } from "../_shared/supabaseAdmin.js";

/** الطالب ينشئ رابط متابعة لولي أمره - يقدر ينشئ أكثر من واحد (مثلاً للأب والأم) */
Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const admin = getAdminClient();
    const user = await getAuthenticatedUser(req, admin);
    if (!user) {
      return jsonResponse({ error: "يجب تسجيل الدخول أولاً" }, 401);
    }

    const { data, error } = await admin
      .from("parent_view_tokens")
      .insert({ student_id: user.id })
      .select("token")
      .single();

    if (error || !data) {
      return jsonResponse({ error: error ? error.message : "فشل الإنشاء" }, 500);
    }

    return jsonResponse({ token: data.token });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
