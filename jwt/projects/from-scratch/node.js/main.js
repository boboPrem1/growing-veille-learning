import crypto from "crypto";

const SECRET = Buffer.from(
  "mon_secret_tres_long_et_aleatoire_256bits",
  "utf-8",
);

// ──────────────────────────────────────────────
// Base64URL Helpers
// ──────────────────────────────────────────────

const b64url_encode = (data) => Buffer.from(data).toString("base64url");

const b64urlDecode = (str) => Buffer.from(str, "base64url");

// ──────────────────────────────────────────────
// Création
// ──────────────────────────────────────────────

function createJwt(payload, secret) {
  const header = {
    alg: "HS256",
    typ: "JWT",
  };

  const headerB64 = b64url_encode(JSON.stringify(header));
  const payloadB64 = b64url_encode(JSON.stringify(payload));

  const signingInput = `${headerB64}.${payloadB64}`;

  const signature = crypto
    .createHmac("sha256", secret)
    .update(signingInput)
    .digest();

  return `${signingInput}.${b64url_encode(signature)}`;
}

// ──────────────────────────────────────────────
// Vérification
// ──────────────────────────────────────────────

function verifyJwt(token, secret) {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Malformed token");

  const [headerB64, payloadB64, signatureB64] = parts;

  // Validate the algorithm
  const header = JSON.parse(b64urlDecode(headerB64));
  if (header.alg !== "HS256")
    throw new Error(`None supported algorithm : ${header.alg}`);

  // Recalculate the HMAC Signature
  const signingInput = `${headerB64}.${payloadB64}`;
  const expectedSig = crypto
    .createHmac("sha256", secret)
    .update(signingInput)
    .digest();

  const actualSig = b64urlDecode(signatureB64);

  // Constant time comparison
  if (!crypto.timingSafeEqual(expectedSig, actualSig)) {
    throw new Error("Invalid signature");
  }

  // Decode payload after verification
  const payload = JSON.parse(b64urlDecode(payloadB64).toString("utf-8"));

  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && now > payload.exp) throw new Error("Expired token");
  if (payload.nbf && now < payload.nbf) throw new Error("Token not valid yet");

  return payload;
}

// ──────────────────────────────────────────────
// Test
// ──────────────────────────────────────────────

const payload = {
  sub: "user_42",
  role: "editor",
  iat: Math.floor(Date.now() / 1000),
  exp: Math.floor(Date.now() / 1000) + 900,
};

const token = createJwt(payload, SECRET);
console.log("Token :", token);

const decoded = verifyJwt(token, SECRET);
console.log("Verified :", decoded);

// Try to decode an altered token body
try {
  console.log(
    `${verifyJwt(
      token.split(".")[0] +
        "." +
        b64url_encode(
          JSON.stringify({
            sub: "user_42",
            role: "admin",
            iat: Math.floor(Date.now() / 1000),
            exp: Math.floor(Date.now() / 1000) + 900,
          }),
        ) +
        "." +
        token.split(".")[2],
      SECRET,
    )}`,
  );
} catch (e) {
  console.error(e.toString());
}
