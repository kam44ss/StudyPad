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

    const { code, percentOff, maxUses, expiresInDays } = await req.json();
    if (!code || !percentOff || percentOff <= 0 || percentOff > 100) {
      return jsonResponse({ error: "بيانات غير صحيحة" }, 400);
    }

    const expiresAt = expiresInDays
      ? new Date(Date.now() + expiresInDays * 86400000).toISOString()
      : null;

    const { error } = await admin.from("discount_codes").insert({
      code: code.trim().toUpperCase(),
      percent_off: percentOff,
      max_uses: maxUses || null,
      expires_at: expiresAt,
      created_by: user.id,
    });

    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    return jsonResponse({ status: "ok", code: code.trim().toUpperCase() });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
