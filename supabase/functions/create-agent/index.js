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

    const { name, phone, commissionPercent } = await req.json();
    if (!name || commissionPercent == null || commissionPercent < 0 || commissionPercent > 100) {
      return jsonResponse({ error: "بيانات الوكيل غير صحيحة" }, 400);
    }

    const { data, error } = await admin
      .from("agents")
      .insert({ name, phone: phone || "", commission_percent: commissionPercent, created_by: user.id })
      .select("id")
      .single();

    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    return jsonResponse({ agentId: data.id });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
