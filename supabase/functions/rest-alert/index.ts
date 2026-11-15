// Supabase Edge Function name: rest-alert
// Dashboard: Edge Functions → Create function → name it rest-alert → paste this file → Deploy.
//
// Precision: the function returns immediately and waits with setTimeout inside
// EdgeRuntime.waitUntil. Hosted functions are stopped after 150s on the Free
// plan and 400s on paid plans, so before that limit this function calls itself
// (action "continue") and keeps waiting. A rest of up to 5 minutes still sends
// within about a second of fire_at. If that chain is interrupted, action
// "sweep" (optional pg_cron, once a minute) sends anything already due, which
// can be up to 60 seconds late.
//
// Secrets (Edge Functions → Secrets), never commit the private key:
//   VAPID_PUBLIC_JWK   public JWK JSON
//   VAPID_PRIVATE_JWK  private JWK JSON
//   VAPID_SUBJECT      optional, default mailto:lift-log@paulwkogut.github.io

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import * as webpush from "jsr:@negrel/webpush@0.5.0";
import { createClient } from "jsr:@supabase/supabase-js@2";

const WAIT_SLICE_MS = 120_000;
const MAX_REST_MS = 300_000;

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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

function userClient(req: Request) {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("Authorization") || "" } },
    auth: { persistSession: false },
  });
}

function bearer(req: Request) {
  return (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
}

function isService(req: Request) {
  const token = bearer(req);
  const service = env("SUPABASE_SERVICE_ROLE_KEY");
  return !!service && token === service;
}

async function userId(req: Request) {
  const token = bearer(req);
  if (!token || isService(req)) return "";
  const sb = userClient(req);
  const { data, error } = await sb.auth.getUser(token);
  if (error || !data.user) return "";
  return data.user.id;
}

let appServer: webpush.ApplicationServer | null = null;

async function pushServer() {
  if (appServer) return appServer;
  const publicKey = JSON.parse(env("VAPID_PUBLIC_JWK"));
  const privateKey = JSON.parse(env("VAPID_PRIVATE_JWK"));
  const vapidKeys = await webpush.importVapidKeys({ publicKey, privateKey });
  appServer = await webpush.ApplicationServer.new({
    contactInformation: env("VAPID_SUBJECT") || "mailto:lift-log@paulwkogut.github.io",
    vapidKeys,
  });
  return appServer;
}

async function claim(id: string) {
  const due = new Date(Date.now() + 2000).toISOString();
  const { data } = await admin()
    .from("rest_alerts")
    .update({ sent_at: new Date().toISOString() })
    .eq("id", id)
    .is("sent_at", null)
    .is("cancelled_at", null)
    .lte("fire_at", due)
    .select("id,user_id,exercise_name")
    .maybeSingle();
  return data;
}

async function deliver(row: { id: string; user_id: string; exercise_name: string }) {
  const sb = admin();
  const { data: alert } = await sb
    .from("rest_alerts")
    .select("id")
    .eq("id", row.id)
    .is("cancelled_at", null)
    .maybeSingle();
  if (!alert) return;
  const { data: subs } = await sb
    .from("push_subscriptions")
    .select("id,endpoint,keys")
    .eq("user_id", row.user_id);
  if (!subs || !subs.length) return;
  const server = await pushServer();
  const DEFAULT_REST_MESSAGE = "Break is over bruh. Get back to work";
  let restBody = DEFAULT_REST_MESSAGE;
  const { data: prefs, error: prefsError } = await sb
    .from("user_settings")
    .select("rest_message")
    .eq("user_id", row.user_id)
    .maybeSingle();
  if (prefsError) console.warn(prefsError);
  const custom = prefs && typeof prefs.rest_message === "string" ? prefs.rest_message.trim() : "";
  if (custom) restBody = custom.slice(0, 80);
  // iOS 18.4+ shows this without starting the service worker, so it can
  // appear while the phone is locked. Older phones still get a classic push.
  const payload = JSON.stringify({
    web_push: 8030,
    mutable: false,
    notification: {
      title: "Rest over",
      body: restBody,
      navigate: "https://paulwkogut.github.io/lift-log/",
      mutable: false,
    },
  });
  for (const sub of subs) {
    const keys = sub.keys || {};
    if (!sub.endpoint || !keys.p256dh || !keys.auth) continue;
    const origFetch = globalThis.fetch;
    globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
      const res = await origFetch(input, init);
      try {
        const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
        if (url === sub.endpoint || url.includes("push.apple.com")) console.log("push response", res.status);
      } catch (logErr) {
        console.warn("push log", logErr);
      }
      return res;
    };
    try {
      await server.subscribe({
        endpoint: sub.endpoint,
        keys: { p256dh: keys.p256dh, auth: keys.auth },
      }).pushTextMessage(payload, {
        urgency: webpush.Urgency.High,
        ttl: 300,
      });
    } catch (err) {
      const response = err && (err as { response?: Response }).response;
      if (response) console.log("push response", response.status);
      else console.warn(err);
      const gone = err && typeof (err as { isGone?: () => boolean }).isGone === "function" &&
        (err as { isGone: () => boolean }).isGone();
      if (gone) await sb.from("push_subscriptions").delete().eq("id", sub.id);
    } finally {
      globalThis.fetch = origFetch;
    }
  }
}

async function hold(id: string) {
  if (!id) return;
  const sb = admin();
  const { data: row } = await sb
    .from("rest_alerts")
    .select("id,fire_at,sent_at,cancelled_at,created_at")
    .eq("id", id)
    .maybeSingle();
  if (!row || row.sent_at || row.cancelled_at) return;
  const fire = new Date(row.fire_at).getTime();
  const age = Date.now() - new Date(row.created_at).getTime();
  if (!Number.isFinite(fire) || age > 10 * 60 * 1000 || fire - Date.now() > MAX_REST_MS + 15_000) return;
  const remaining = fire - Date.now();
  if (remaining > 1000) {
    const slice = Math.min(remaining, WAIT_SLICE_MS);
    await new Promise((resolve) => setTimeout(resolve, slice));
    const { data: again } = await sb
      .from("rest_alerts")
      .select("id,fire_at,sent_at,cancelled_at")
      .eq("id", id)
      .maybeSingle();
    if (!again || again.sent_at || again.cancelled_at) return;
    if (new Date(again.fire_at).getTime() - Date.now() > 1000) {
      await fetch(env("SUPABASE_URL") + "/functions/v1/rest-alert", {
        method: "POST",
        headers: {
          Authorization: "Bearer " + env("SUPABASE_SERVICE_ROLE_KEY"),
          apikey: env("SUPABASE_SERVICE_ROLE_KEY"),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ action: "continue", id }),
      });
      return;
    }
  }
  const claimed = await claim(id);
  if (claimed) await deliver(claimed);
}

async function sweep() {
  const { data } = await admin()
    .from("rest_alerts")
    .select("id")
    .is("sent_at", null)
    .is("cancelled_at", null)
    .lte("fire_at", new Date().toISOString())
    .limit(50);
  for (const row of data || []) {
    const claimed = await claim(row.id);
    if (claimed) await deliver(claimed);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false }, 405);
  try {
    const body = await req.json().catch(() => ({}));
    const action = body && body.action;
    if (action === "continue") {
      if (!isService(req)) return json({ ok: false }, 401);
      EdgeRuntime.waitUntil(hold(String(body.id || "")).catch((err) => console.warn(err)));
      return json({ ok: true });
    }
    if (action === "sweep") {
      if (!isService(req)) return json({ ok: false }, 401);
      EdgeRuntime.waitUntil(sweep().catch((err) => console.warn(err)));
      return json({ ok: true });
    }
    const uid = await userId(req);
    if (!uid) return json({ ok: false }, 401);
    const sb = userClient(req);
    if (action === "cancel") {
      const now = new Date().toISOString();
      const recent = new Date(Date.now() - 15000).toISOString();
      await sb.from("rest_alerts")
        .update({ cancelled_at: now })
        .eq("user_id", uid)
        .is("sent_at", null)
        .is("cancelled_at", null);
      await sb.from("rest_alerts")
        .update({ cancelled_at: now })
        .eq("user_id", uid)
        .is("cancelled_at", null)
        .gte("sent_at", recent);
      return json({ ok: true });
    }
    if (action === "schedule") {
      const fireAtMs = Number(body.fireAt);
      const delay = fireAtMs - Date.now();
      if (!Number.isFinite(fireAtMs) || delay < -2000 || delay > MAX_REST_MS + 5000) {
        return json({ ok: false, error: "Rest time is out of range" }, 400);
      }
      const name = String(body.exerciseName || "").trim().slice(0, 80);
      await sb.from("rest_alerts")
        .update({ cancelled_at: new Date().toISOString() })
        .eq("user_id", uid)
        .is("sent_at", null)
        .is("cancelled_at", null);
      const { data, error } = await sb.from("rest_alerts").insert({
        user_id: uid,
        exercise_name: name,
        fire_at: new Date(fireAtMs).toISOString(),
      }).select("id").single();
      if (error || !data) {
        return json({ ok: false, error: (error && error.message) || "Couldn't save the alert", code: error && error.code }, 200);
      }
      EdgeRuntime.waitUntil(hold(data.id).catch((err) => console.warn(err)));
      return json({ ok: true, id: data.id });
    }
    return json({ ok: false }, 400);
  } catch (err) {
    console.warn(err);
    return json({ ok: false }, 200);
  }
});
