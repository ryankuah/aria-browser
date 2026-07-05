import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { api, internal } from "./_generated/api";

const http = httpRouter();

http.route({
  path: "/api/google/oauth/callback",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    const url = new URL(request.url);
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    if (!code || !state) {
      return new Response("Missing Google OAuth code or state.", { status: 400 });
    }

    try {
      await ctx.runAction(api.google.completeOAuth, { code, state });
      return redirectToBrowserOAuthCallback("success");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Google OAuth failed.";
      return redirectToBrowserOAuthCallback("error", message);
    }
  }),
});

http.route({
  path: "/api/google/pubsub/gmail",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if (!(await verifyPubSubRequest(request))) {
      return new Response("Unauthorized Pub/Sub push.", { status: 401 });
    }

    const payload = await request.json().catch(() => null);
    const rawData = payload?.message?.data;
    const decoded = typeof rawData === "string" ? decodePubSubData(rawData) : {};
    const emailAddress = typeof decoded.emailAddress === "string" ? decoded.emailAddress : undefined;
    const historyId = typeof decoded.historyId === "string" ? decoded.historyId : undefined;
    const pubSubMessageId =
      typeof payload?.message?.messageId === "string"
        ? payload.message.messageId
        : typeof payload?.message?.message_id === "string"
          ? payload.message.message_id
          : undefined;
    const publishedAt = parsePubSubPublishTime(payload?.message?.publishTime ?? payload?.message?.publish_time);

    if (emailAddress) {
      const googleAccountId = await ctx.runQuery(internal.google.resolveGoogleAccountByEmail, {
        email: emailAddress,
      });
      if (googleAccountId) {
        await ctx.runMutation(internal.google.recordGmailPubSubNotification, {
          googleAccountId,
          historyId,
          pubSubMessageId,
          publishedAt,
        });
        await ctx.scheduler.runAfter(0, internal.google.syncGmail, { googleAccountId, historyId });
      }
    }

    return new Response(null, { status: 204 });
  }),
});

http.route({
  path: "/api/google/calendar/watch",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const resourceState = request.headers.get("x-goog-resource-state") ?? "unknown";
    const channelId = request.headers.get("x-goog-channel-id") ?? undefined;

    if (channelId && resourceState !== "sync") {
      const googleAccountId = await ctx.runQuery(internal.google.resolveGoogleAccountByCalendarChannel, {
        channelId,
      });
      if (googleAccountId) {
        await ctx.scheduler.runAfter(0, internal.google.syncCalendars, { googleAccountId });
      }
    }

    return new Response(null, { status: 204 });
  }),
});

function decodePubSubData(value: string) {
  try {
    return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(value), (char) => char.charCodeAt(0))));
  } catch {
    return {};
  }
}

function parsePubSubPublishTime(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

async function verifyPubSubRequest(request: Request) {
  const audience = process.env.GOOGLE_PUBSUB_AUDIENCE;
  if (!audience) {
    return true;
  }
  const authorization = request.headers.get("authorization");
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) {
    return false;
  }
  return await verifyGoogleJwt(token, audience);
}

async function verifyGoogleJwt(token: string, audience: string) {
  const parts = token.split(".");
  if (parts.length !== 3) {
    return false;
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = parseJwtPart(encodedHeader) as { alg?: string; kid?: string };
  const payload = parseJwtPart(encodedPayload) as { aud?: string | string[]; iss?: string; exp?: number; iat?: number };
  if (header.alg !== "RS256" || !header.kid) {
    return false;
  }
  if (payload.iss !== "https://accounts.google.com" && payload.iss !== "accounts.google.com") {
    return false;
  }
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audiences.includes(audience)) {
    return false;
  }
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp < nowSeconds || (payload.iat && payload.iat > nowSeconds + 60)) {
    return false;
  }

  const jwks = await fetch("https://www.googleapis.com/oauth2/v3/certs").then((response) => response.json());
  const jwk = (jwks.keys as Array<JsonWebKey & { kid?: string }> | undefined)?.find((key) => key.kid === header.kid);
  if (!jwk) {
    return false;
  }
  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64UrlToBytes(encodedSignature),
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
  );
}

function parseJwtPart(value: string) {
  try {
    return JSON.parse(new TextDecoder().decode(base64UrlToBytes(value)));
  } catch {
    return {};
  }
}

function base64UrlToBytes(value: string) {
  return Uint8Array.from(atob(value.replaceAll("-", "+").replaceAll("_", "/").padEnd(Math.ceil(value.length / 4) * 4, "=")), (char) =>
    char.charCodeAt(0),
  );
}

function redirectToBrowserOAuthCallback(status: "success" | "error", message?: string) {
  const callbackUrl = new URL("com.ryankuah.browser://google/oauth/callback");
  callbackUrl.searchParams.set("status", status);
  if (message) {
    callbackUrl.searchParams.set("message", message);
  }
  const escapedCallbackUrl = escapeHTML(callbackUrl.toString());
  const title = status === "success" ? "Google account connected" : "Google connection failed";
  const body =
    status === "success"
      ? "Google account connected. Returning to Browser."
      : "Google connection failed. Returning to Browser.";

  return new Response(
    `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>${title}</title>
    <meta http-equiv="refresh" content="0; url=${escapedCallbackUrl}">
  </head>
  <body>
    <p>${body}</p>
    <script>window.location.href = ${JSON.stringify(callbackUrl.toString())};</script>
    <p><a href="${escapedCallbackUrl}">Return to Browser</a></p>
  </body>
</html>`,
    {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8" },
    },
  );
}

function escapeHTML(value: string) {
  return value.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

export default http;
