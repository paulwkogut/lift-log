// Supabase Edge Function name: send-feedback
// Dashboard: Edge Functions → Create function → name it send-feedback → paste this file → Deploy.
//
// Secrets (Edge Functions → Secrets). Do not put the address in the app or in git.
//   RESEND_API_KEY
//   FEEDBACK_TO_EMAIL
// SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY are already provided.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const CATEGORIES: Record<string, string> = {
  bug: "Bug",
  idea: "Idea",
  other: "Other",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function env(name: string) {
  return Deno.env.get(name) || "";
}

function admin() {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
}

function bearer(req: Request) {
  return (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
}

async function userFrom(req: Request) {
  const token = bearer(req);
  if (!token || token === env("SUPABASE_SERVICE_ROLE_KEY")) return null;
  const sb = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: "Bearer " + token } },
    auth: { persistSession: false },
  });
  const { data, error } = await sb.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user;
}

async function emailPaul(text: string, subject: string) {
  const key = env("RESEND_API_KEY");
  const to = env("FEEDBACK_TO_EMAIL");
  if (!key || !to) {
    console.warn("feedback email skipped: missing secret");
    return;
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "onboarding@resend.dev",
      to: [to],
      subject,
      text,
    }),
  });
  if (!res.ok) console.warn("feedback email failed", res.status);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);
  try {
    const user = await userFrom(req);
    if (!user) return json({ ok: false, error: "Not signed in." }, 401);
    const body = await req.json().catch(() => ({}));
    const category = String(body.category || "");
    const label = CATEGORIES[category];
    const message = String(body.message || "").trim().slice(0, 2000);
    const contactOk = body.contactOk === true;
    if (!label) return json({ ok: false, error: "Pick Bug, Idea, or Other." }, 400);
    if (!message) return json({ ok: false, error: "Write a message." }, 400);
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count, error: countError } = await admin()
      .from("feedback")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", since);
    if (countError) return json({ ok: false, error: "Couldn't check recent feedback." }, 200);
    if ((count || 0) >= 5) return json({ ok: false, error: "You've sent enough feedback for this hour." }, 200);
    const { error } = await admin().from("feedback").insert({
      user_id: user.id,
      user_email: user.email || null,
      category,
      message,
      contact_ok: contactOk,
    });
    if (error) return json({ ok: false, error: "Couldn't save that feedback." }, 200);
    const lines = [
      "Category: " + label,
      "Time: " + new Date().toISOString(),
    ];
    if (contactOk && user.email) lines.push("From: " + user.email);
    lines.push("", message);
    try {
      await emailPaul(lines.join("\n"), "Lift Log feedback: " + label);
    } catch (err) {
      console.warn(err);
    }
    return json({ ok: true });
  } catch (err) {
    console.warn(err);
    return json({ ok: false, error: "Couldn't send that." }, 200);
  }
});
