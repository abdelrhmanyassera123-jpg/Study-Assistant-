// =====================================================================
// Web Push مشترك بين send-reminders وlecture-worker.
// Web Push shared by send-reminders and lecture-worker.
// =====================================================================

const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:support@studyassistant.app";

export const pushConfigured = () => !!VAPID_PUBLIC_KEY && !!VAPID_PRIVATE_KEY;

// =====================================================================
// Web Push — تشفير الرسالة وتوقيع VAPID (RFC 8291 / 8188 / 8292)
// Web Push — message encryption and VAPID signing (RFC 8291 / 8188 / 8292)
// =====================================================================

export class PushGoneError extends Error {}

export async function sendWebPush(
  sub: { endpoint: string; p256dh: string; auth: string },
  payload: {
    title: string;
    body: string;
    tag: string;
    silent?: boolean;
    vibrate?: number[];
    /// الصفحة اللي التنبيه بيفتحها لما يتداس عليه.
    /// The page the notification opens when tapped.
    url?: string;
    /// أزرار جوه التنبيه، وكل زرار ليه صفحة.
    /// Buttons inside the notification, each with its own page.
    actions?: { action: string; title: string; url: string }[];
  },
): Promise<void> {
  const endpointOrigin = new URL(sub.endpoint).origin;
  const vapidHeader = await buildVapidHeader(endpointOrigin);
  const body = await encryptPayload(sub.p256dh, sub.auth, JSON.stringify(payload));

  const res = await fetch(sub.endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Encoding": "aes128gcm",
      TTL: "300",
      Authorization: vapidHeader,
    },
    body,
  });

  if (res.status === 404 || res.status === 410) {
    throw new PushGoneError(`subscription gone (${res.status})`);
  }
  if (!res.ok) {
    throw new Error(`push service responded ${res.status}: ${await res.text()}`);
  }
}

async function buildVapidHeader(audience: string): Promise<string> {
  const header = b64url(new TextEncoder().encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const payload = b64url(new TextEncoder().encode(JSON.stringify({
    aud: audience,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: VAPID_SUBJECT,
  })));
  const signingInput = `${header}.${payload}`;

  const privateKey = await crypto.subtle.importKey(
    "jwk",
    vapidPrivateJwk(),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    new TextEncoder().encode(signingInput),
  );

  const jwt = `${signingInput}.${b64url(new Uint8Array(signature))}`;
  return `vapid t=${jwt}, k=${VAPID_PUBLIC_KEY}`;
}

/// بيحوّل المفتاح الخاص الخام (32 بايت) لصيغة JWK عشان SubtleCrypto يقدر
/// يستورده — المفتاح العام مشتق من نفس نقطة EC المخزّنة في VAPID_PUBLIC_KEY.
/// Turns the raw private scalar (32 bytes) into JWK form so SubtleCrypto can
/// import it — the public key is the same EC point stored in
/// VAPID_PUBLIC_KEY.
function vapidPrivateJwk(): JsonWebKey {
  const pub = b64urlDecode(VAPID_PUBLIC_KEY); // 0x04 || X(32) || Y(32)
  const x = pub.slice(1, 33);
  const y = pub.slice(33, 65);
  const d = b64urlDecode(VAPID_PRIVATE_KEY);
  return {
    kty: "EC",
    crv: "P-256",
    x: b64url(x),
    y: b64url(y),
    d: b64url(d),
    ext: true,
  };
}

/// تشفير الحمولة حسب RFC 8291 (aes128gcm واحدة، مفيش padding زيادة).
/// Encrypts the payload per RFC 8291 (a single aes128gcm record, no extra
/// padding).
async function encryptPayload(
  p256dhB64: string,
  authB64: string,
  plaintext: string,
): Promise<Uint8Array> {
  const uaPublicRaw = b64urlDecode(p256dhB64); // 65 bytes
  const authSecret = b64urlDecode(authB64); // 16 bytes

  const serverKeyPair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true,
    ["deriveBits"],
  );
  const asPublicRaw = new Uint8Array(
    await crypto.subtle.exportKey("raw", serverKeyPair.publicKey),
  );

  const uaPublicKey = await crypto.subtle.importKey(
    "raw",
    uaPublicRaw,
    { name: "ECDH", namedCurve: "P-256" },
    false,
    [],
  );
  const sharedSecret = new Uint8Array(
    await crypto.subtle.deriveBits(
      { name: "ECDH", public: uaPublicKey },
      serverKeyPair.privateKey,
      256,
    ),
  );

  const prkKey = await hmacSha256(authSecret, sharedSecret);
  const keyInfo = concatBytes([
    new TextEncoder().encode("WebPush: info"),
    new Uint8Array([0]),
    uaPublicRaw,
    asPublicRaw,
  ]);
  const ikm = (await hmacSha256(prkKey, concatBytes([keyInfo, new Uint8Array([1])])))
    .slice(0, 32);

  const salt = crypto.getRandomValues(new Uint8Array(16));
  const prk = await hmacSha256(salt, ikm);

  const cekInfo = concatBytes([
    new TextEncoder().encode("Content-Encoding: aes128gcm"),
    new Uint8Array([0]),
  ]);
  const cek = (await hmacSha256(prk, concatBytes([cekInfo, new Uint8Array([1])]))).slice(0, 16);

  const nonceInfo = concatBytes([
    new TextEncoder().encode("Content-Encoding: nonce"),
    new Uint8Array([0]),
  ]);
  const nonce = (await hmacSha256(prk, concatBytes([nonceInfo, new Uint8Array([1])]))).slice(0, 12);

  const recordPlain = concatBytes([new TextEncoder().encode(plaintext), new Uint8Array([2])]);
  const cekKey = await crypto.subtle.importKey("raw", cek, { name: "AES-GCM" }, false, ["encrypt"]);
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, cekKey, recordPlain),
  );

  const recordSize = new Uint8Array(4);
  new DataView(recordSize.buffer).setUint32(0, 4096, false);

  return concatBytes([
    salt,
    recordSize,
    new Uint8Array([asPublicRaw.length]),
    asPublicRaw,
    ciphertext,
  ]);
}

async function hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, data));
}

function concatBytes(chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((n, c) => n + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

function b64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(value.length + ((4 - (value.length % 4)) % 4), "=");
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}
