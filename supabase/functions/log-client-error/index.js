import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser } from "../_shared/supabaseAdmin.js";

/**
 * تسجيل أخطاء العميل (ويب أو أندرويد) بجدول بسيط تقدر تراجعه من لوحة الأدمن -
 * بديل مبسّط عن Sentry بدون الحاجة لحساب/خدمة خارجية. المصادقة اختيارية عمداً
 * (خطأ ممكن يصير قبل ما يسجّل المستخدم دخول أصلاً، زي فشل تحميل صفحة الدخول).
 */
Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const admin = getAdminClient();
    const user = await getAuthenticatedUser(req, admin); // قد يكون null، وهذا مقبول هنا

    const { platform, message, context } = await req.json();
    if (!platform || !["web", "android"].includes(platform) || !message) {
      return jsonResponse({ error: "platform (web/android) و message مطلوبان" }, 400);
    }

    await admin.from("client_errors").insert({
      platform,
      user_id: user ? user.id : null,
      message: String(message).slice(0, 2000),
      context: context || null,
    });

    return jsonResponse({ status: "logged" });
  } catch (e) {
    return jsonResponse({ status: "ignored" });
  }
});
