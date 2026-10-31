import { jsonResponse, handleOptions } from "../_shared/cors.js";
import { getAdminClient, getAuthenticatedUser, getUserRole } from "../_shared/supabaseAdmin.js";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // بدون أحرف متشابهة (0/O, 1/I)

function generateCode() {
  let raw = "";
  for (let i = 0; i < 10; i++) {
    raw += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
  }
  return raw.match(/.{1,5}/g).join("-"); // مثال: AB3XZ-9KLMN
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

    const { lessonId, bundleId, count, isPaid, expiresInDays, agentId } = await req.json();

    if (!count || count < 1 || count > 500) {
      return jsonResponse({ error: "بيانات غير صحيحة (العدد بين 1 و500)" }, 400);
    }
    if ((!lessonId && !bundleId) || (lessonId && bundleId)) {
      return jsonResponse({ error: "حدد lessonId أو bundleId، وليس الاثنين" }, 400);
    }

    let teacherId, priceValue;

    if (lessonId) {
      const { data: lesson, error: lessonErr } = await admin
        .from("lessons")
        .select("id, teacher_id, price")
        .eq("id", lessonId)
        .single();
      if (lessonErr || !lesson) {
        return jsonResponse({ error: "الدرس غير موجود" }, 404);
      }
      teacherId = lesson.teacher_id;
      priceValue = lesson.price;
    } else {
      const { data: bundle, error: bundleErr } = await admin
        .from("bundles")
        .select("id, teacher_id, price")
        .eq("id", bundleId)
        .single();
      if (bundleErr || !bundle) {
        return jsonResponse({ error: "الحزمة غير موجودة" }, 404);
      }
      teacherId = bundle.teacher_id;
      priceValue = bundle.price;
    }

    const role = await getUserRole(admin, user.id);
    const isOwnerTeacher = role === "teacher" && teacherId === user.id;
    const isAdminCaller = role === "admin";

    if (!isOwnerTeacher && !isAdminCaller) {
      return jsonResponse({ error: "ما عندك صلاحية إنشاء أكواد لهذا العنصر" }, 403);
    }

    if (agentId) {
      const { data: agent, error: agentErr } = await admin
        .from("agents")
        .select("id")
        .eq("id", agentId)
        .single();
      if (agentErr || !agent) {
        return jsonResponse({ error: "الوكيل غير موجود" }, 404);
      }
    }

    const expiresAt = expiresInDays
      ? new Date(Date.now() + expiresInDays * 86400000).toISOString()
      : null;

    const codes = [];
    for (let i = 0; i < count; i++) {
      // نحاول عدة مرات لو صار تصادم نادر بكود موجود مسبقاً (قيد PK يمنع التكرار فعلياً)
      let inserted = false;
      for (let attempt = 0; attempt < 5 && !inserted; attempt++) {
        const code = generateCode();
        const { error: insertErr } = await admin.from("redemption_codes").insert({
          code,
          lesson_id: lessonId || null,
          bundle_id: bundleId || null,
          teacher_id: teacherId,
          agent_id: agentId || null,
          value: priceValue,
          is_paid: !!isPaid,
          created_by: user.id,
          expires_at: expiresAt,
        });
        if (!insertErr) {
          codes.push(code);
          inserted = true;
        } else if (insertErr.code !== "23505") {
          // 23505 = unique_violation فقط هذا نعيد المحاولة، أي خطأ آخر نوقف
          return jsonResponse({ error: insertErr.message }, 500);
        }
      }
    }

    return jsonResponse({ codes });
  } catch (e) {
    return jsonResponse({ error: e.message || "خطأ غير متوقع" }, 500);
  }
});
