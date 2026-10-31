import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser, getUserRole } from "../_shared/supabaseAdmin.js";

// إعدادات WhatsApp Cloud API الرسمية من Meta - راجع developers.facebook.com/docs/whatsapp
// قبل الإطلاق للتأكد من آخر نسخة API (v23.0 وقت كتابة هذا الكود)
const WHATSAPP_TOKEN = Deno.env.get("WHATSAPP_TOKEN"); // Permanent Access Token من System User
const WHATSAPP_PHONE_NUMBER_ID = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
const WHATSAPP_API_VERSION = "v23.0";

/**
 * ملاحظة مهمة جداً (تحققت منها بالبحث قبل الكتابة): رسائل نصية حرة (type: "text")
 * تشتغل فقط خلال 24 ساعة من آخر رسالة أرسلها المستخدم للرقم التجاري. أي إشعار
 * استباقي منك (تفعيل كود، درس جديد) يصير خارج هذا الإطار غالباً، فلازم يُرسل
 * كـ "قالب رسالة" (template) معتمد مسبقاً من Meta - وإلا الإرسال يفشل.
 * أنشئ القالب من Meta Business Manager > WhatsApp Manager > Message Templates
 * قبل استخدام templateName هنا.
 */
async function sendWhatsAppTemplate(toPhone, templateName, languageCode, bodyParams) {
  const url = `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${WHATSAPP_PHONE_NUMBER_ID}/messages`;

  const payload = {
    messaging_product: "whatsapp",
    to: toPhone,
    type: "template",
    template: {
      name: templateName,
      language: { code: languageCode || "ar" },
      components: bodyParams && bodyParams.length
        ? [{ type: "body", parameters: bodyParams.map((p) => ({ type: "text", text: String(p) })) }]
        : undefined,
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${WHATSAPP_TOKEN}`,
    },
    body: JSON.stringify(payload),
  });

  const data = await res.json();
  return { ok: res.ok, data };
}

/**
 * يستخدمها المدرس/الأدمن لإرسال إشعار لطالب معيّن (مثلاً: "درس جديد نُشر").
 * يتطلب أن يكون الطالب مسجّل رقم هاتفه بملفه الشخصي.
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
    if (role !== "admin" && role !== "teacher") {
      return jsonResponse({ error: "هذه العملية للمدرسين والأدمن فقط" }, 403);
    }

    const { studentId, templateName, languageCode, bodyParams } = await req.json();
    if (!studentId || !templateName) {
      return jsonResponse({ error: "studentId و templateName مطلوبان" }, 400);
    }

    if (!WHATSAPP_TOKEN || !WHATSAPP_PHONE_NUMBER_ID) {
      return jsonResponse({ error: "إعدادات WhatsApp غير مضبوطة على السيرفر بعد" }, 500);
    }

    const { data: profile, error: profileErr } = await admin
      .from("profiles")
      .select("phone")
      .eq("id", studentId)
      .single();

    if (profileErr || !profile || !profile.phone) {
      return jsonResponse({ error: "الطالب ما سجّل رقم هاتف بحسابه" }, 400);
    }

    const result = await sendWhatsAppTemplate(profile.phone, templateName, languageCode, bodyParams);

    if (!result.ok) {
      return jsonResponse({ error: "فشل إرسال رسالة WhatsApp", details: result.data }, 502);
    }

    return jsonResponse({ status: "sent" });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
