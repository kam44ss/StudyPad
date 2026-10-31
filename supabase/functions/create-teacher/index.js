import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser, getUserRole } from "../_shared/supabaseAdmin.js";

/**
 * الأدمن فقط يستدعي هذه الفنكشن ليحوّل مستخدم مسجَّل مسبقاً (صديق مدرس مثلاً)
 * إلى "مدرس" بنسبة أرباح محددة. المستخدم لازم يكون سجّل دخول بالتطبيق/الموقع
 * مرة واحدة على الأقل قبل هذا (عشان يكون له صف بجدول profiles أصلاً).
 */
Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const admin = getAdminClient();
    const caller = await getAuthenticatedUser(req, admin);
    if (!caller) {
      return jsonResponse({ error: "يجب تسجيل الدخول أولاً" }, 401);
    }

    const callerRole = await getUserRole(admin, caller.id);
    if (callerRole !== "admin") {
      return jsonResponse({ error: "هذه العملية للأدمن فقط" }, 403);
    }

    const { userId, displayName, revenueSharePercent } = await req.json();
    if (!userId || revenueSharePercent == null || revenueSharePercent < 0 || revenueSharePercent > 100) {
      return jsonResponse({ error: "بيانات غير صحيحة" }, 400);
    }

    const { data: profile, error: profileErr } = await admin
      .from("profiles")
      .select("id, role")
      .eq("id", userId)
      .single();

    if (profileErr || !profile) {
      return jsonResponse({ error: "المستخدم غير موجود - يجب أن يسجّل دخول مرة واحدة أولاً" }, 404);
    }

    const { error: roleErr } = await admin
      .from("profiles")
      .update({ role: "teacher" })
      .eq("id", userId);

    if (roleErr) {
      return jsonResponse({ error: roleErr.message }, 500);
    }

    const { error: teacherErr } = await admin.from("teachers").upsert({
      id: userId,
      display_name: displayName || "",
      revenue_share_percent: revenueSharePercent,
      status: "active",
    });

    if (teacherErr) {
      return jsonResponse({ error: teacherErr.message }, 500);
    }

    return jsonResponse({ status: "ok" });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
