import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser, getUserRole } from "../_shared/supabaseAdmin.js";

/**
 * لحل طلبات دفع "عالقة" بحالة pending - غالباً بسبب انقطاع الشبكة قبل ما
 * يرجع الطالب لصفحة النتيجة بعد الدفع الفعلي بزين كاش. الأدمن يتحقق يدوياً
 * (من لوحة زين كاش نفسها أو تواصل مع الطالب) هل الدفع تم فعلاً، ثم يقرر هنا.
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

    const role = await getUserRole(admin, user.id);
    if (role !== "admin") {
      return jsonResponse({ error: "هذه العملية للأدمن فقط" }, 403);
    }

    const { orderId, success } = await req.json();
    if (!orderId || typeof success !== "boolean") {
      return jsonResponse({ error: "orderId و success (true/false) مطلوبان" }, 400);
    }

    const { data, error } = await admin.rpc("record_zaincash_result", {
      p_order_id: orderId,
      p_success: success,
    });

    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    return jsonResponse(data);
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
