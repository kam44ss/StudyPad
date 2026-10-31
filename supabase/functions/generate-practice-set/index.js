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

    const { mode, subject, count, bundleId } = await req.json();
    if (!mode || !["daily", "custom", "mock_exam", "review"].includes(mode)) {
      return jsonResponse({ error: "mode يجب أن يكون daily أو custom أو mock_exam أو review" }, 400);
    }

    const { data, error } = await admin.rpc("generate_practice_set", {
      p_student_id: user.id,
      p_mode: mode,
      p_subject: subject || null,
      p_count: count || 10,
      p_bundle_id: bundleId || null,
    });

    if (error) {
      const knownErrors = {
        bundle_id_required: "bundleId مطلوب لامتحان شامل",
        bundle_not_fully_purchased: "لازم تشتري الحزمة كاملة أولاً لهذا الامتحان",
      };
      return jsonResponse({ error: knownErrors[error.message] || error.message }, 400);
    }

    return jsonResponse(data);
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
