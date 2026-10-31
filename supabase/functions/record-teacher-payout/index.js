import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser, getUserRole } from "../_shared/supabaseAdmin.js";

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

    const { teacherId, amount, note } = await req.json();
    if (!teacherId || !amount || amount <= 0) {
      return jsonResponse({ error: "بيانات الدفع غير صحيحة" }, 400);
    }

    const { data, error } = await admin.rpc("record_teacher_payout", {
      p_teacher_id: teacherId,
      p_amount: amount,
      p_note: note || "",
      p_recorded_by: user.id,
    });

    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    return jsonResponse(data);
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
