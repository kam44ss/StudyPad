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

    const { code: rawCode } = await req.json();
    const code = (rawCode || "").trim().toUpperCase();
    if (!code) {
      return jsonResponse({ error: "الكود مطلوب" }, 400);
    }

    // كل منطق التحقق والمحاسبة يصير داخل دالة قاعدة بيانات واحدة (transaction ذرية حقيقية)
    const { data, error } = await admin.rpc("redeem_code", {
      p_code: code,
      p_student_id: user.id,
    });

    if (error) {
      const knownErrors = {
        invalid_code: "الكود غير صحيح",
        code_already_used: "الكود مستخدم من قبل",
        code_expired: "انتهت صلاحية الكود",
        teacher_not_found: "المدرس غير موجود",
      };
      const message = knownErrors[error.message] || error.message;
      return jsonResponse({ error: message }, 400);
    }

    return jsonResponse(data);
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
