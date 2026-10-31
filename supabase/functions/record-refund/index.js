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

    const { purchaseId, note } = await req.json();
    if (!purchaseId) {
      return jsonResponse({ error: "purchaseId مطلوب" }, 400);
    }

    const { data, error } = await admin.rpc("record_refund", {
      p_purchase_id: purchaseId,
      p_recorded_by: user.id,
      p_note: note || "",
    });

    if (error) {
      const knownErrors = {
        purchase_not_found: "عملية الشراء غير موجودة",
      };
      return jsonResponse({ error: knownErrors[error.message] || error.message }, 400);
    }

    return jsonResponse(data);
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
