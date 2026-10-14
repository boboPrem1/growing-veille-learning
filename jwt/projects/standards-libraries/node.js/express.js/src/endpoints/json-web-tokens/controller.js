import jwt from "jsonwebtoken";
import crypto from "crypto";

const SECRET = process.env.JWT_SECRET; // ≥ 256 bits depuis les variables d'env
const REFRESH_SECRET = process.env.REFRESH_SECRET;

// ── Generation ──
function generateTokens(userId, role) {
  const accessToken = jwt.sign({ sub: userId, role }, SECRET, {
    algorithm: "HS256",
    expiresIn: "15m",
    issuer: "api.monapp.com",
    audience: "monapp-client",
    jwtid: crypto.randomUUID(),
  });

  const refreshToken = jwt.sign(
    {
      sub: userId,
      type: "refresh",
    },
    REFRESH_SECRET,
    {
      algorithm: "HS256",
      expiresIn: "7d",
      jwtid: crypto.randomUUID(),
      issuer: "api.monapp.com",
      audience: "monapp-client",
    },
  );

  return { accessToken, refreshToken };
}

// Verification
function verifyToken(token, secret) {
  return jwt.verify(token, secret, {
    algorithms: ["HS256"], // Never ommit the whitelist
    issuer: "api.monapp.com", // validate the iss claim
    audience: "monapp-client", // validate the aud claim
    clockTolerance: 30, // clockskew, 30 secondes for clock tolerance
  });
}

export const Index = (req, res) => {
  const tokens = generateTokens("user5214", "editor");
  const payload = verifyToken(tokens.accessToken, SECRET);
  const refresh_payload = verifyToken(tokens.refreshToken, REFRESH_SECRET);

  res.status(200).json({
    tokens,
    payload,
    refresh_payload,
  });
};
