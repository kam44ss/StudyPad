import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser } from "../_shared/supabaseAdmin.js";
import { create as createJwt, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

// راجع docs.zaincash.iq قبل الإطلاق الفعلي للتأكد من آخر نسخة API (v1 المستخدمة هنا
// موثقة وواسعة الانتشار، وفيه v2 أحدث بنظام OAuth2 قد تحتاجه حسب نوع حسابك)
const ZAINCASH_MSISDN = Deno.env.get("ZAINCASH_MSISDN");
const ZAINCASH_MERCHANT_ID = Deno.env.get("ZAINCASH_MERCHANT_ID");
const ZAINCASH_SECRET = Deno.env.get("ZAINCASH_SECRET");
const ZAINCASH_PRODUCTION = Deno.env.get("ZAINCASH_PRODUCTION") === "true";
const SITE_URL = Deno.env.get("SITE_URL") || "http://localhost:5000";

const BASE_URL = ZAINCASH_PRODUCTION ? "https://api.zaincash.iq" : "https://test.zaincash.iq";

async function signJwt(payload, secretString, expiresInSeconds) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secretString),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  return createJwt(
    { alg: "HS256", typ: "JWT" },
    { ...payload, exp: getNumericDate(expiresInSeconds) },
    key
  );
}

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const admin = getAdminClient();
    const user = await getAuthenticatedUser(req, admin);
    if (!user) {
      return jsonResponse({ error: "يجب تسجيل الدخول أولاً" }, 401);
    }

    const { lessonId, bundleId, discountCode } = await req.json();
    if ((!lessonId && !bundleId) || (lessonId && bundleId)) {
      return jsonResponse({ error: "حدد lessonId أو bundleId، وليس الاثنين" }, 400);
    }

    let teacherId, price, title;

    if (lessonId) {
      const { data: lesson, error: lessonErr } = await admin
        .from("lessons")
        .select("id, teacher_id, title, price")
        .eq("id", lessonId)
        .single();
      if (lessonErr || !lesson) {
        return jsonResponse({ error: "الدرس غير موجود" }, 404);
      }
      teacherId = lesson.teacher_id;
      price = lesson.price;
      title = lesson.title;
    } else {
      const { data: bundle, error: bundleErr } = await admin
        .from("bundles")
        .select("id, teacher_id, title, price")
        .eq("id", bundleId)
        .single();
      if (bundleErr || !bundle) {
        return jsonResponse({ error: "الحزمة غير موجودة" }, 404);
      }
      teacherId = bundle.teacher_id;
      price = bundle.price;
      title = bundle.title;
    }

    const originalPrice = price;
    let appliedDiscountCode = null;

    if (discountCode) {
      const { data: discountResult, error: discountErr } = await admin.rpc("validate_discount_code", {
        p_code: discountCode,
      });
      if (discountErr) {
        const knownErrors = {
          invalid_discount_code: "كود الخصم غير صحيح",
          discount_code_disabled: "كود الخصم معطّل",
          discount_code_expired: "انتهت صلاحية كود الخصم",
          discount_code_exhausted: "استُنفد عدد استخدامات كود الخصم",
        };
        return jsonResponse({ error: knownErrors[discountErr.message] || discountErr.message }, 400);
      }
      price = Math.round(price * (1 - discountResult.percent_off / 100) * 100) / 100;
      appliedDiscountCode = discountCode.toUpperCase();
    }

    const { data: order, error: orderErr } = await admin
      .from("zaincash_orders")
      .insert({
        student_id: user.id,
        lesson_id: lessonId || null,
        bundle_id: bundleId || null,
        teacher_id: teacherId,
        amount: price,
        original_amount: originalPrice,
        discount_code: appliedDiscountCode,
        status: "pending",
      })
      .select("id")
      .single();

    if (orderErr || !order) {
      return jsonResponse({ error: "تعذر إنشاء طلب الدفع" }, 500);
    }

    const token = await signJwt(
      {
        amount: price,
        serviceType: `${bundleId ? "Bundle" : "Lesson"}: ${title}`.slice(0, 200),
        msisdn: ZAINCASH_MSISDN,
        orderId: order.id,
        redirectUrl: `${SITE_URL.replace(/\/$/, "")}/functions/v1/zaincash-redirect`,
      },
      ZAINCASH_SECRET,
      4 * 60 * 60 // 4 ساعات صلاحية
    );

    const initRes = await fetch(`${BASE_URL}/transaction/init`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token, merchantId: ZAINCASH_MERCHANT_ID, lang: "ar" }),
    });

    const initData = await initRes.json();

    if (!initData.id) {
      await admin.from("zaincash_orders").update({ status: "init_failed" }).eq("id", order.id);
      return jsonResponse({ error: "تعذر إنشاء عملية الدفع، حاول مرة أخرى" }, 500);
    }

    await admin
      .from("zaincash_orders")
      .update({ zaincash_transaction_id: initData.id })
      .eq("id", order.id);

    return jsonResponse({ payUrl: `${BASE_URL}/transaction/pay?id=${initData.id}` });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
