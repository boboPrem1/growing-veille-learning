import jwt from "jsonwebtoken";
import crypto from "crypto";
import { SignJWT, jwtVerify, generateSecret } from "jose";

const SECRET = new TextEncoder().encode(process.env.JWT_SECRET); // ≥ 256 bits depuis les variables d'env
const REFRESH_SECRET = new TextEncoder().encode(process.env.REFRESH_SECRET);

// ── Generation ──
async function generateTokens(userId, role) {
  const accessToken = await new SignJWT({
    sub: userId,
    role: role,
  })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("15m")
    .setIssuer("https://api.monapp.com")
    .setAudience("monapp-client")
    .setJti(crypto.randomUUID())
    .sign(SECRET);

  const refreshToken = await new SignJWT({
    sub: userId,
    type: "refresh",
  })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("7d")
    .setIssuer("https://api.monapp.com")
    .setAudience("monapp-client")
    .setJti(crypto.randomUUID())
    .sign(REFRESH_SECRET);

  return { accessToken, refreshToken };
}

// Verification
async function verifyToken(token, secret) {

    return await jwtVerify(
        token,
        secret,
        {
            algorithms: ["HS256"],
            issuer: "https://api.monapp.com",
            audience: "monapp-client",
            clockTolerance: 30
        }
    )
}

export const Index = async (req, res) => {
  const tokens = await generateTokens("user5214", "editor");
  const payload = await verifyToken(tokens.accessToken, SECRET);
  const refresh_payload = await verifyToken(tokens.refreshToken, REFRESH_SECRET);

  res.status(200).json({
    tokens,
    payload,
    refresh_payload,
  });
};
