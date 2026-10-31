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

    const { agentId } = await req.json();
    if (!agentId) {
      return jsonResponse({ error: "agentId مطلوب" }, 400);
    }

    const { data, error } = await admin.rpc("get_agent_earnings", { p_agent_id: agentId });
    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    const balanceDue = Number(data.total_earned) - Number(data.total_paid_out);
    return jsonResponse({ ...data, balance_due: Math.round(balanceDue * 100) / 100 });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
