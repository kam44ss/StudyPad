import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser } from "../_shared/supabaseAdmin.js";

/**
 * تلميح محلي بدون أي ذكاء اصطناعي أو مفتاح API: يحذف عشوائياً كل الخيارات
 * الخاطئة إلا واحدة (فيصير الاختيار بين خيار خاطئ واحد والصحيح - نفس مبدأ
 * "50/50" ببرامج المسابقات)، بالإضافة لتلميح نصي يكتبه المدرس نفسه إن وُجد.
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

    const { questionId } = await req.json();
    if (!questionId) {
      return jsonResponse({ error: "questionId مطلوب" }, 400);
    }

    const { data, error } = await admin.rpc("get_answer_hint", {
      p_question_id: questionId,
      p_student_id: user.id,
    });

    if (error) {
      const knownErrors = {
        question_not_found: "السؤال غير موجود",
        not_purchased: "لم تشترِ هذا الدرس بعد",
      };
      return jsonResponse({ error: knownErrors[error.message] || error.message }, 400);
    }

    return jsonResponse(data);
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
