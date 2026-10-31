import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * عميل بصلاحيات service_role - يتجاوز RLS بالكامل، تماماً مثل Firebase Admin SDK.
 * لا يُستخدم أبداً بالواجهة الأمامية، فقط داخل Edge Functions.
 */
export function getAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  return createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/**
 * يتحقق من الـ JWT المرسل بهيدر Authorization ويرجع بيانات المستخدم المسجل دخوله.
 * لا نثق أبداً بأي uid يُرسَل بجسم الطلب نفسه - فقط بما يثبته التوكن الموقّع.
 */
export async function getAuthenticatedUser(req, adminClient) {
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return null;
  }
  const { data, error } = await adminClient.auth.getUser(token);
  if (error || !data.user) {
    return null;
  }
  return data.user;
}

export async function getUserRole(adminClient, userId) {
  const { data, error } = await adminClient
    .from("profiles")
    .select("role")
    .eq("id", userId)
    .single();
  if (error || !data) return null;
  return data.role;
}
