import { getAdminClient } from "../_shared/supabaseAdmin.js";
import { verify as verifyJwt } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const ZAINCASH_SECRET = Deno.env.get("ZAINCASH_SECRET");
const SITE_URL = Deno.env.get("SITE_URL") || "http://localhost:5000";

async function importSecretKey(secretString) {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secretString),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );
}

function redirectTo(status, orderId) {
  const url = new URL(`${SITE_URL.replace(/\/$/, "")}/payment-result.html`);
  url.searchParams.set("status", status);
  if (orderId) url.searchParams.set("order", orderId);
  return Response.redirect(url.toString(), 302);
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const token = url.searchParams.get("token");

    if (!token) {
      return redirectTo("error");
    }

    let decoded;
    try {
      const key = await importSecretKey(ZAINCASH_SECRET);
      decoded = await verifyJwt(token, key);
    } catch (e) {
      return redirectTo("invalid_signature");
    }

    const orderId = decoded.orderid || decoded.orderId;
    if (!orderId) {
      return redirectTo("error");
    }

    const admin = getAdminClient();
    const success = decoded.status === "success";

    const { error } = await admin.rpc("record_zaincash_result", {
      p_order_id: orderId,
      p_success: success,
    });

    if (error) {
      return redirectTo("error", orderId);
    }

    return redirectTo(success ? "success" : "failed", orderId);
  } catch (e) {
    return redirectTo("error");
  }
});
