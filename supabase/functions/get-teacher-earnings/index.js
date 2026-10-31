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
    const body = await req.json().catch(() => ({}));
    // المدرس يشوف رصيده هو فقط، الأدمن يقدر يشوف أي مدرس
    const teacherId = role === "admin" && body.teacherId ? body.teacherId : user.id;

    if (role !== "admin" && teacherId !== user.id) {
      return jsonResponse({ error: "ما عندك صلاحية" }, 403);
    }

    const { data, error } = await admin.rpc("get_teacher_earnings", { p_teacher_id: teacherId });
    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    const balanceDue = Number(data.total_earned) - Number(data.total_paid_out);
    return jsonResponse({ ...data, balance_due: Math.round(balanceDue * 100) / 100 });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
