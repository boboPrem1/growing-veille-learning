# Étape 5 — Implémentation Pratique des JWT

> **Objectif** : Passer de la théorie à la pratique — implémenter JWT de zéro, maîtriser les librairies standard, construire un système complet côté serveur et client, et gérer proprement la rotation et la révocation.

---

## Sommaire

1. [Implémenter JWT from scratch](#51-implémenter-jwt-from-scratch)
2. [Utiliser les librairies standard](#52-utiliser-les-librairies-standard)
3. [Implémentation côté serveur](#53-implémentation-côté-serveur)
4. [Implémentation côté client](#54-implémentation-côté-client)
5. [Rotation et révocation](#55-rotation-et-révocation)

---

## 5.1 Implémenter JWT from scratch

Implémenter JWT manuellement au moins une fois est fondamental : cela démystifie le token, révèle qu'il n'y a aucune magie, et ancre la compréhension des vecteurs d'attaque vus à l'étape 4.

### La structure d'un JWT rappelée

```
BASE64URL(header) . BASE64URL(payload) . BASE64URL(signature)
```

La **signature** est calculée sur `BASE64URL(header) + "." + BASE64URL(payload)`.

---

### Implémentation en Python (sans librairie tierce)

```python
import base64
import hashlib
import hmac
import json
import time

SECRET = b"mon_secret_tres_long_et_aleatoire_256bits"

# ──────────────────────────────────────────────
# Helpers Base64URL (RFC 4648 §5)
# Base64URL = Base64 avec + → -, / → _, sans padding =
# ──────────────────────────────────────────────

def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")

def b64url_decode(data: str) -> bytes:
    # Rajouter le padding supprimé
    padding = 4 - len(data) % 4
    if padding != 4:
        data += "=" * padding
    return base64.urlsafe_b64decode(data)

# ──────────────────────────────────────────────
# Création du token
# ──────────────────────────────────────────────

def create_jwt(payload: dict, secret: bytes) -> str:
    # 1. Header — toujours le même pour HS256
    header = {"alg": "HS256", "typ": "JWT"}
    
    # 2. Encoder header et payload en Base64URL
    header_b64  = b64url_encode(json.dumps(header, separators=(",", ":")).encode())
    payload_b64 = b64url_encode(json.dumps(payload, separators=(",", ":")).encode())
    
    # 3. Message à signer = header_b64 + "." + payload_b64
    signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    
    # 4. Signature HMAC-SHA256
    signature = hmac.new(secret, signing_input, hashlib.sha256).digest()
    signature_b64 = b64url_encode(signature)
    
    return f"{header_b64}.{payload_b64}.{signature_b64}"

# ──────────────────────────────────────────────
# Vérification du token (sans librairie)
# ──────────────────────────────────────────────

def verify_jwt(token: str, secret: bytes) -> dict:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Token malformé : doit avoir 3 parties séparées par '.'")
    
    header_b64, payload_b64, signature_b64 = parts
    
    # 1. Vérifier l'algorithme AVANT toute validation de signature
    header = json.loads(b64url_decode(header_b64))
    if header.get("alg") != "HS256":
        raise ValueError(f"Algorithme non supporté : {header.get('alg')}")
    
    # 2. Recalculer la signature attendue
    signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    expected_sig = hmac.new(secret, signing_input, hashlib.sha256).digest()
    
    # 3. Comparaison en temps constant (protection contre timing attacks)
    try:
        actual_sig = b64url_decode(signature_b64)
    except Exception:
        raise ValueError("Signature mal encodée")
    
    if not hmac.compare_digest(expected_sig, actual_sig):
        raise ValueError("Signature invalide — token falsifié ou secret incorrect")
    
    # 4. Décoder le payload (seulement APRÈS validation de signature)
    payload = json.loads(b64url_decode(payload_b64))
    
    # 5. Valider les claims temporels
    now = int(time.time())
    
    if "exp" in payload and now > payload["exp"]:
        raise ValueError(f"Token expiré depuis {now - payload['exp']} secondes")
    
    if "nbf" in payload and now < payload["nbf"]:
        raise ValueError("Token pas encore valide (nbf)")
    
    return payload

# ──────────────────────────────────────────────
# Démonstration
# ──────────────────────────────────────────────

if __name__ == "__main__":
    payload = {
        "sub": "user_42",
        "role": "editor",
        "iat": int(time.time()),
        "exp": int(time.time()) + 900,  # 15 minutes
    }
    
    token = create_jwt(payload, SECRET)
    print(f"Token généré :\n{token}\n")
    
    # Afficher les parties décodées
    parts = token.split(".")
    print(f"Header  : {json.loads(b64url_decode(parts[0]))}")
    print(f"Payload : {json.loads(b64url_decode(parts[1]))}")
    print(f"Sig     : {parts[2][:20]}...\n")
    
    # Vérification valide
    decoded = verify_jwt(token, SECRET)
    print(f"Vérification OK : {decoded}\n")
    
    # Test falsification : modifier le payload directement
    tampered = parts[0] + "." + b64url_encode(b'{"sub":"admin","role":"superadmin"}') + "." + parts[2]
    try:
        verify_jwt(tampered, SECRET)
    except ValueError as e:
        print(f"Falsification détectée : {e}")
```

**Output attendu :**
```
Token généré :
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzQyIiwicm9sZSI6ImVkaXRvciIsImlhdCI6...

Header  : {'alg': 'HS256', 'typ': 'JWT'}
Payload : {'sub': 'user_42', 'role': 'editor', 'iat': ..., 'exp': ...}
Sig     : xK9mN2pQ...

Vérification OK : {'sub': 'user_42', 'role': 'editor', ...}

Falsification détectée : Signature invalide — token falsifié ou secret incorrect
```

---

### Implémentation en Node.js (sans librairie tierce)

```javascript
const crypto = require("crypto");

const SECRET = Buffer.from("mon_secret_tres_long_et_aleatoire_256bits", "utf8");

// ──────────────────────────────────────────────
// Helpers Base64URL
// ──────────────────────────────────────────────

const b64urlEncode = (data) =>
  Buffer.from(data)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

const b64urlDecode = (str) => {
  // Restaurer le padding Base64 standard
  str = str.replace(/-/g, "+").replace(/_/g, "/");
  while (str.length % 4) str += "=";
  return Buffer.from(str, "base64");
};

// ──────────────────────────────────────────────
// Création
// ──────────────────────────────────────────────

function createJwt(payload, secret) {
  const header = { alg: "HS256", typ: "JWT" };

  const headerB64  = b64urlEncode(JSON.stringify(header));
  const payloadB64 = b64urlEncode(JSON.stringify(payload));

  const signingInput = `${headerB64}.${payloadB64}`;

  const signature = crypto
    .createHmac("sha256", secret)
    .update(signingInput)
    .digest();

  return `${signingInput}.${b64urlEncode(signature)}`;
}

// ──────────────────────────────────────────────
// Vérification
// ──────────────────────────────────────────────

function verifyJwt(token, secret) {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Token malformé");

  const [headerB64, payloadB64, signatureB64] = parts;

  // Valider l'algorithme
  const header = JSON.parse(b64urlDecode(headerB64).toString("utf8"));
  if (header.alg !== "HS256") throw new Error(`Algorithme non supporté : ${header.alg}`);

  // Recalculer la signature
  const signingInput = `${headerB64}.${payloadB64}`;
  const expectedSig = crypto
    .createHmac("sha256", secret)
    .update(signingInput)
    .digest();

  const actualSig = b64urlDecode(signatureB64);

  // Comparaison en temps constant
  if (!crypto.timingSafeEqual(expectedSig, actualSig)) {
    throw new Error("Signature invalide");
  }

  // Décoder le payload (seulement après validation)
  const payload = JSON.parse(b64urlDecode(payloadB64).toString("utf8"));

  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && now > payload.exp) throw new Error("Token expiré");
  if (payload.nbf && now < payload.nbf) throw new Error("Token pas encore valide");

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
console.log("Vérifié :", decoded);
```

### Points critiques à retenir de l'implémentation manuelle

| Point | Détail |
|-------|--------|
| `hmac.compare_digest` / `timingSafeEqual` | Comparaison en temps constant — évite les timing attacks |
| Algorithme validé **avant** la signature | Protège contre `alg: none` et confusion |
| Payload décodé **après** signature valide | Jamais de lecture de claims sur token non validé |
| Base64URL ≠ Base64 | Supprimer `+`, `/`, `=` — erreur classique |

---

## 5.2 Utiliser les Librairies Standard

### Node.js

#### `jsonwebtoken` — la référence historique

```bash
npm install jsonwebtoken
```

```javascript
const jwt = require("jsonwebtoken");

const SECRET = process.env.JWT_SECRET; // ≥ 256 bits depuis les variables d'env

// ── Génération ──
function generateTokens(userId, role) {
  const accessToken = jwt.sign(
    { sub: userId, role },
    SECRET,
    {
      algorithm: "HS256",
      expiresIn: "15m",      // raccourci pratique
      issuer: "api.monapp.com",
      audience: "monapp-client",
      jwtid: crypto.randomUUID(),  // jti pour révocation
    }
  );

  const refreshToken = jwt.sign(
    { sub: userId, type: "refresh" },
    process.env.REFRESH_SECRET,
    { algorithm: "HS256", expiresIn: "7d", jwtid: crypto.randomUUID() }
  );

  return { accessToken, refreshToken };
}

// ── Vérification avec options complètes ──
function verifyToken(token) {
  return jwt.verify(token, SECRET, {
    algorithms: ["HS256"],           // whitelist — jamais omis
    issuer: "api.monapp.com",        // valide le claim iss
    audience: "monapp-client",       // valide le claim aud
    clockTolerance: 30,              // 30 secondes de tolérance horloge (clockSkew)
  });
  // Lance TokenExpiredError, JsonWebTokenError, NotBeforeError selon le cas
}
```

#### `jose` — moderne, standards IETF, supporte RS256/ES256 nativement

```bash
npm install jose
```

```javascript
import { SignJWT, jwtVerify, generateSecret } from "jose";

// Générer une clé sécurisée (ou charger depuis env)
const secret = new TextEncoder().encode(process.env.JWT_SECRET);

// ── Génération ──
const token = await new SignJWT({ sub: "user_42", role: "editor" })
  .setProtectedHeader({ alg: "HS256" })
  .setIssuedAt()
  .setExpirationTime("15m")
  .setIssuer("https://api.monapp.com")
  .setAudience("monapp-client")
  .setJti(crypto.randomUUID())
  .sign(secret);

// ── Vérification ──
const { payload } = await jwtVerify(token, secret, {
  algorithms: ["HS256"],
  issuer: "https://api.monapp.com",
  audience: "monapp-client",
  clockTolerance: 30,
});
```

`jose` est préférable pour les nouveaux projets : supporte ESM, Edge Runtime (Cloudflare Workers, Deno), et les algorithmes modernes (ES256, EdDSA).

---

### Python — `PyJWT`

```bash
pip install PyJWT
```

```python
import jwt
import uuid
from datetime import datetime, timedelta, timezone

SECRET_KEY = os.environ["JWT_SECRET"]  # ≥ 256 bits

# ── Génération ──
def generate_access_token(user_id: str, role: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "role": role,
        "iat": now,
        "exp": now + timedelta(minutes=15),
        "iss": "https://api.monapp.com",
        "aud": "monapp-client",
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")

# ── Vérification avec toutes les options ──
def verify_access_token(token: str) -> dict:
    return jwt.decode(
        token,
        SECRET_KEY,
        algorithms=["HS256"],          # whitelist stricte
        issuer="https://api.monapp.com",
        audience="monapp-client",
        leeway=30,                     # clockSkew de 30 secondes
        options={
            "verify_exp": True,
            "verify_iat": True,
            "require": ["sub", "exp", "jti"],  # claims obligatoires
        },
    )
    # Lance : ExpiredSignatureError, InvalidSignatureError,
    #         DecodeError, InvalidAudienceError...
```

---

### Java — `jjwt` (JJWT)

```xml
<!-- pom.xml -->
<dependency>
    <groupId>io.jsonwebtoken</groupId>
    <artifactId>jjwt-api</artifactId>
    <version>0.12.6</version>
</dependency>
```

```java
import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import java.security.Key;
import java.util.Date;
import java.util.UUID;

public class JwtService {

    private final Key key = Keys.hmacShaKeyFor(
        System.getenv("JWT_SECRET").getBytes(StandardCharsets.UTF_8)
    );

    // Génération
    public String generateToken(String userId, String role) {
        return Jwts.builder()
            .subject(userId)
            .claim("role", role)
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + 900_000)) // 15 min
            .issuer("https://api.monapp.com")
            .audience().add("monapp-client").and()
            .id(UUID.randomUUID().toString())  // jti
            .signWith(key, Jwts.SIG.HS256)
            .compact();
    }

    // Vérification
    public Claims verifyToken(String token) {
        return Jwts.parser()
            .verifyWith((SecretKey) key)
            .requireIssuer("https://api.monapp.com")
            .requireAudience("monapp-client")
            .clockSkewSeconds(30)
            .build()
            .parseSignedClaims(token)
            .getPayload();
        // Lance : ExpiredJwtException, MalformedJwtException, SecurityException...
    }
}
```

---

### Go — `golang-jwt/jwt`

```bash
go get github.com/golang-jwt/jwt/v5
```

```go
package auth

import (
    "os"
    "time"
    "github.com/golang-jwt/jwt/v5"
    "github.com/google/uuid"
)

var secretKey = []byte(os.Getenv("JWT_SECRET"))

type Claims struct {
    UserID string `json:"sub"`
    Role   string `json:"role"`
    jwt.RegisteredClaims
}

// Génération
func GenerateToken(userID, role string) (string, error) {
    claims := Claims{
        UserID: userID,
        Role:   role,
        RegisteredClaims: jwt.RegisteredClaims{
            Issuer:    "https://api.monapp.com",
            Audience:  jwt.ClaimStrings{"monapp-client"},
            IssuedAt:  jwt.NewNumericDate(time.Now()),
            ExpiresAt: jwt.NewNumericDate(time.Now().Add(15 * time.Minute)),
            ID:        uuid.NewString(),  // jti
        },
    }

    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString(secretKey)
}

// Vérification
func VerifyToken(tokenStr string) (*Claims, error) {
    token, err := jwt.ParseWithClaims(
        tokenStr,
        &Claims{},
        func(token *jwt.Token) (interface{}, error) {
            // Valider l'algorithme explicitement
            if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
                return nil, fmt.Errorf("algorithme inattendu : %v", token.Header["alg"])
            }
            return secretKey, nil
        },
        jwt.WithIssuer("https://api.monapp.com"),
        jwt.WithAudience("monapp-client"),
        jwt.WithLeeway(30*time.Second),
        jwt.WithExpirationRequired(),
    )

    if err != nil {
        return nil, err
    }

    return token.Claims.(*Claims), nil
}
```

### Tableau comparatif des librairies

| Librairie | Langage | Points forts | Notes |
|-----------|---------|-------------|-------|
| `jsonwebtoken` | Node.js | Mature, répandu | API synchrone, moins flexible |
| `jose` | Node.js/TS | ESM, Edge, RS256/ES256 | Recommandé nouveaux projets |
| `passport-jwt` | Node.js | Intégration Express | Wrapper de `jsonwebtoken` |
| `PyJWT` | Python | Simple, Pythonique | Vérifier que `cryptography` est installé pour RS256 |
| `python-jose` | Python | Plus complet (JWE, JWKS) | Légèrement plus lourd |
| `jjwt` | Java | Fluent API, JJWT 0.12+ | Migrer depuis 0.9 si c'est le cas |
| `nimbus-jose-jwt` | Java | Le plus complet JVM | Souvent utilisé avec Spring Security |
| `golang-jwt/jwt` | Go | Idiomatique, léger | Fork maintenu de `dgrijalva/jwt-go` |

---

## 5.3 Implémentation Côté Serveur

### Middleware de vérification réutilisable

#### Express.js (Node.js)

```javascript
// middleware/auth.js
const jwt = require("jsonwebtoken");

const JWT_CONFIG = {
  algorithms: ["HS256"],
  issuer: process.env.JWT_ISSUER,
  audience: process.env.JWT_AUDIENCE,
  clockTolerance: 30,
};

/**
 * Middleware d'authentification JWT.
 * Attache req.user si le token est valide.
 */
function authenticate(req, res, next) {
  // 1. Extraire le token (supporte Bearer header ET cookie httpOnly)
  let token;

  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith("Bearer ")) {
    token = authHeader.slice(7);
  } else if (req.cookies?.access_token) {
    token = req.cookies.access_token;
  }

  if (!token) {
    return res.status(401).json({ error: "Token manquant" });
  }

  // 2. Vérifier
  try {
    req.user = jwt.verify(token, process.env.JWT_SECRET, JWT_CONFIG);
    next();
  } catch (err) {
    return handleJwtError(err, res);
  }
}

/**
 * Middleware d'autorisation par rôle.
 * À utiliser après authenticate().
 */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!roles.includes(req.user?.role)) {
      return res.status(403).json({
        error: "Accès refusé",
        required: roles,
        current: req.user?.role,
      });
    }
    next();
  };
}

// ── Utilisation ──
// router.get("/admin", authenticate, requireRole("admin"), handler)
// router.get("/profile", authenticate, handler)

module.exports = { authenticate, requireRole };
```

#### Django (Python) — Middleware + décorateur

```python
# auth/middleware.py
import jwt
from django.http import JsonResponse
from functools import wraps

JWT_OPTIONS = {
    "algorithms": ["HS256"],
    "issuer": settings.JWT_ISSUER,
    "audience": settings.JWT_AUDIENCE,
    "leeway": 30,
    "options": {"require": ["sub", "exp", "jti"]},
}

def get_token_from_request(request):
    """Extrait le token depuis le header Authorization ou le cookie."""
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        return auth_header[7:]
    return request.COOKIES.get("access_token")

def jwt_required(view_func):
    """Décorateur — protège une vue Django."""
    @wraps(view_func)
    def wrapper(request, *args, **kwargs):
        token = get_token_from_request(request)
        if not token:
            return JsonResponse({"error": "Token manquant"}, status=401)

        try:
            payload = jwt.decode(token, settings.JWT_SECRET, **JWT_OPTIONS)
        except jwt.ExpiredSignatureError:
            return JsonResponse({"error": "Token expiré"}, status=401)
        except jwt.InvalidTokenError as e:
            return JsonResponse({"error": f"Token invalide : {e}"}, status=401)

        request.jwt_payload = payload
        return view_func(request, *args, **kwargs)
    return wrapper

def role_required(*roles):
    """Décorateur — autorise uniquement certains rôles."""
    def decorator(view_func):
        @wraps(view_func)
        @jwt_required
        def wrapper(request, *args, **kwargs):
            if request.jwt_payload.get("role") not in roles:
                return JsonResponse({"error": "Accès refusé"}, status=403)
            return view_func(request, *args, **kwargs)
        return wrapper
    return decorator

# ── Utilisation ──
# @role_required("admin", "superadmin")
# def admin_view(request): ...
```

---

### Gestion des erreurs JWT

Chaque librairie lève des exceptions spécifiques. Les traiter précisément permet de retourner des messages utiles (pour le debugging) sans exposer d'informations sensibles.

```javascript
// Node.js — gestion complète
function handleJwtError(err, res) {
  if (err.name === "TokenExpiredError") {
    // Le token était valide mais est expiré — client doit rafraîchir
    return res.status(401).json({
      error: "token_expired",
      message: "Session expirée, veuillez vous reconnecter",
      expiredAt: err.expiredAt,
    });
  }

  if (err.name === "JsonWebTokenError") {
    // Signature invalide, token malformé, algorithme non whitelisté...
    return res.status(401).json({
      error: "token_invalid",
      message: "Token invalide",
      // Ne pas exposer err.message en production (peut donner des infos)
    });
  }

  if (err.name === "NotBeforeError") {
    // nbf dans le futur
    return res.status(401).json({
      error: "token_not_active",
      message: "Token pas encore actif",
      date: err.date,
    });
  }

  // Erreur inattendue — logger côté serveur, réponse générique au client
  console.error("Erreur JWT inattendue :", err);
  return res.status(500).json({ error: "Erreur interne" });
}
```

```python
# Python — hiérarchie des exceptions PyJWT
try:
    payload = jwt.decode(token, SECRET, algorithms=["HS256"])

except jwt.ExpiredSignatureError:
    # exp dépassé
    raise AuthError("token_expired", "Session expirée")

except jwt.ImmatureSignatureError:
    # nbf dans le futur
    raise AuthError("token_not_active", "Token pas encore valide")

except jwt.InvalidAudienceError:
    raise AuthError("token_invalid", "Audience incorrecte")

except jwt.InvalidIssuerError:
    raise AuthError("token_invalid", "Issuer incorrect")

except jwt.DecodeError:
    # Token malformé (Base64 invalide, pas 3 parties...)
    raise AuthError("token_malformed", "Token malformé")

except jwt.InvalidTokenError as e:
    # Catch-all pour toutes les autres erreurs JWT
    raise AuthError("token_invalid", "Token invalide")
```

---

### Blacklist / Révocation avec Redis

```python
# auth/revocation.py
import redis
import time

r = redis.Redis(host="localhost", port=6379, db=0, decode_responses=True)

BLACKLIST_PREFIX = "jwt:blacklist:"

def revoke_token(jti: str, exp: int):
    """Ajoute un jti à la blacklist jusqu'à son expiration naturelle."""
    ttl = exp - int(time.time())
    if ttl > 0:
        r.setex(f"{BLACKLIST_PREFIX}{jti}", ttl, "revoked")

def is_revoked(jti: str) -> bool:
    """Vérifie si un jti est dans la blacklist."""
    return r.exists(f"{BLACKLIST_PREFIX}{jti}") > 0

def revoke_all_user_tokens(user_id: str, before_timestamp: int = None):
    """
    Révocation globale par user_id (stratégie par version).
    Stocke un timestamp — tous les tokens émis avant ce timestamp sont invalides.
    """
    ts = before_timestamp or int(time.time())
    r.set(f"jwt:user_revoke:{user_id}", ts, ex=86400 * 30)  # 30 jours

def is_user_token_revoked(user_id: str, iat: int) -> bool:
    """Vérifie si le token a été émis avant la révocation globale de l'user."""
    revoke_ts = r.get(f"jwt:user_revoke:{user_id}")
    if revoke_ts and iat < int(revoke_ts):
        return True
    return False

# ── Intégration dans le middleware ──
def verify_with_revocation(token: str) -> dict:
    payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
    
    jti = payload.get("jti")
    if not jti:
        raise ValueError("jti manquant — token non révocable")
    
    # Vérifier la blacklist par jti
    if is_revoked(jti):
        raise ValueError("Token révoqué")
    
    # Vérifier la révocation globale de l'utilisateur
    if is_user_token_revoked(payload["sub"], payload["iat"]):
        raise ValueError("Session utilisateur révoquée")
    
    return payload
```

---

## 5.4 Implémentation Côté Client

### Stockage sécurisé : `httpOnly` cookie vs mémoire JS

```
┌─────────────────────────────────────────────────────────────┐
│                    Comparaison des stratégies               │
├──────────────────┬───────────────────┬──────────────────────┤
│ Stockage         │ Vulnérable XSS ?  │ Vulnérable CSRF ?    │
├──────────────────┼───────────────────┼──────────────────────┤
│ localStorage     │ ✗ OUI (fatal)     │ ✗ NON                │
│ sessionStorage   │ ✗ OUI (fatal)     │ ✗ NON                │
│ httpOnly Cookie  │ ✓ NON             │ ✗ OUI (mitiger CSRF) │
│ Mémoire JS (RAM) │ ✓ NON*            │ ✓ NON                │
└──────────────────┴───────────────────┴──────────────────────┘
* Perdu au refresh de page
```

**Stratégie recommandée (production) :**
- **Access token** → mémoire JS (variable module, non persistée)
- **Refresh token** → cookie `httpOnly` + `Secure` + `SameSite=Strict`

```javascript
// auth/tokenStore.js — Access token en mémoire uniquement
let _accessToken = null;

export const tokenStore = {
  get: ()        => _accessToken,
  set: (token)   => { _accessToken = token; },
  clear: ()      => { _accessToken = null; },
};
```

```python
# Django — émettre les cookies sécurisés
def login_view(request):
    # ... vérification credentials ...
    
    access_token  = generate_access_token(user.id, user.role)
    refresh_token = generate_refresh_token(user.id)
    
    response = JsonResponse({"access_token": access_token})
    
    # Refresh token en cookie httpOnly — jamais accessible au JS
    response.set_cookie(
        key="refresh_token",
        value=refresh_token,
        httponly=True,
        secure=True,          # HTTPS uniquement
        samesite="Strict",    # protège contre CSRF
        max_age=7 * 24 * 3600,  # 7 jours
        path="/api/auth/",    # scope minimal
    )
    return response
```

---

### Refresh silencieux en arrière-plan

```javascript
// auth/tokenManager.js
import { tokenStore } from "./tokenStore";

const ACCESS_TOKEN_MARGIN = 60; // Rafraîchir 60 secondes avant expiration

let refreshTimer = null;

/**
 * Décoder l'expiration sans vérification (on fait confiance à notre propre serveur ici).
 * La vérification réelle est côté serveur.
 */
function getTokenExpiry(token) {
  if (!token) return null;
  const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
  return payload.exp * 1000; // en ms
}

/**
 * Effectue le refresh et planifie le prochain.
 */
async function doRefresh() {
  try {
    // Le refresh token est dans le cookie httpOnly — envoyé automatiquement
    const res = await fetch("/api/auth/refresh", {
      method: "POST",
      credentials: "include",  // inclure les cookies
    });

    if (!res.ok) {
      // Refresh token expiré ou révoqué → déconnexion
      handleLogout();
      return;
    }

    const { access_token } = await res.json();
    tokenStore.set(access_token);
    scheduleRefresh(access_token);
  } catch {
    handleLogout();
  }
}

/**
 * Planifie le prochain refresh automatique.
 */
export function scheduleRefresh(token) {
  if (refreshTimer) clearTimeout(refreshTimer);

  const expiry = getTokenExpiry(token);
  if (!expiry) return;

  const now = Date.now();
  const delay = expiry - now - ACCESS_TOKEN_MARGIN * 1000;

  if (delay <= 0) {
    doRefresh();  // Déjà expiré ou imminent
  } else {
    refreshTimer = setTimeout(doRefresh, delay);
  }
}

export function cancelRefresh() {
  if (refreshTimer) clearTimeout(refreshTimer);
  refreshTimer = null;
}

function handleLogout() {
  tokenStore.clear();
  cancelRefresh();
  window.location.href = "/login";
}
```

---

### Intercepteur Axios — gestion de l'expiration

```javascript
// api/axiosInstance.js
import axios from "axios";
import { tokenStore, scheduleRefresh } from "../auth/tokenManager";

const api = axios.create({ baseURL: "/api" });

// ── Intercepteur de requête — injecter le token ──
api.interceptors.request.use((config) => {
  const token = tokenStore.get();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// ── Intercepteur de réponse — gérer les 401 ──
let isRefreshing = false;
let pendingRequests = [];  // requêtes en attente pendant le refresh

api.interceptors.response.use(
  (response) => response,  // succès → passer directement
  async (error) => {
    const originalRequest = error.config;

    if (error.response?.status !== 401 || originalRequest._retried) {
      return Promise.reject(error);
    }

    if (isRefreshing) {
      // Un refresh est déjà en cours — mettre la requête en file d'attente
      return new Promise((resolve, reject) => {
        pendingRequests.push({ resolve, reject });
      }).then((token) => {
        originalRequest.headers.Authorization = `Bearer ${token}`;
        return api(originalRequest);
      });
    }

    originalRequest._retried = true;
    isRefreshing = true;

    try {
      const res = await fetch("/api/auth/refresh", {
        method: "POST",
        credentials: "include",
      });

      if (!res.ok) throw new Error("Refresh échoué");

      const { access_token } = await res.json();
      tokenStore.set(access_token);
      scheduleRefresh(access_token);

      // Débloquer les requêtes en attente
      pendingRequests.forEach(({ resolve }) => resolve(access_token));
      pendingRequests = [];

      originalRequest.headers.Authorization = `Bearer ${access_token}`;
      return api(originalRequest);
    } catch (refreshError) {
      pendingRequests.forEach(({ reject }) => reject(refreshError));
      pendingRequests = [];
      window.location.href = "/login";
      return Promise.reject(refreshError);
    } finally {
      isRefreshing = false;
    }
  }
);

export default api;
```

**Diagramme de séquence — refresh silencieux :**

```
Client          Axios Interceptor     Auth Server       API Server
  │                    │                   │                 │
  │── GET /profile ───>│                   │                 │
  │                    │── Bearer token ──>│                 │
  │                    │<── 401 Expired ───│                 │
  │                    │                   │                 │
  │                    │── POST /refresh ─>│                 │
  │                    │   (cookie httpOnly)│                │
  │                    │<── new access_token│                │
  │                    │                   │                 │
  │                    │── GET /profile ────────────────────>│
  │                    │   Bearer new_token │                │
  │<── 200 + data ─────────────────────────────────────────│
```

---

## 5.5 Rotation et Révocation

### Pourquoi les JWT sont "stateless" mais la révocation est "stateful"

Le JWT est conçu pour être **auto-suffisant** — le serveur n'a pas besoin de base de données pour valider un token. C'est sa force principale (scalabilité, performance) et sa faiblesse principale (impossibilité de révocation instantanée).

```
Modèle session traditionnel (stateful) :
  Serveur stocke : session_id → {user, rôle, expiration}
  Révocation      : delete session_id → immédiat ✓
  Coût            : lookup DB/Redis à chaque requête

Modèle JWT (stateless) :
  Serveur stocke : rien
  Révocation      : impossible sans état externe ✗
  Coût            : vérification cryptographique uniquement
```

**La révocation de JWT nécessite de réintroduire de l'état.** Le but est de minimiser la taille de cet état.

---

### Stratégie 1 — Short-lived tokens (approche minimale)

La stratégie la plus simple : access tokens très courts (5-15 min), pas de révocation individuelle.

```
Avantages :
  ✓ Pas d'état côté serveur
  ✓ Simple à implémenter
  ✓ Fenêtre d'exploitation limitée (token volé = 15 min max)

Inconvénients :
  ✗ Pas de révocation immédiate (si compte compromis, 15 min d'exposition)
  ✗ Refresh fréquent nécessaire
  ✗ Inadapté aux opérations critiques (banking, santé)

Idéal pour : APIs publiques, applications non critiques
```

---

### Stratégie 2 — Blacklist par `jti` (révocation individuelle)

```python
# Cycle de vie complet d'un token avec jti

# 1. Émission — chaque token a un jti unique
payload = {
    "sub": user_id,
    "jti": str(uuid.uuid4()),   # ex: "a3f2c1d4-..."
    "exp": ...,
}

# 2. Vérification — consulter la blacklist
def is_valid(token):
    payload = jwt.decode(...)
    if redis.exists(f"blacklist:{payload['jti']}"):
        raise TokenRevokedException()
    return payload

# 3. Révocation (logout ou changement de mot de passe)
def revoke(payload):
    ttl = payload["exp"] - int(time.time())
    redis.setex(f"blacklist:{payload['jti']}", max(ttl, 0), "1")
    # Le TTL auto-purge l'entrée Redis quand le token aurait expiré de toute façon
```

**Dimensionnement Redis :**
```
Hypothèse : 10 000 utilisateurs actifs, 1 logout/jour, access token 15 min
→ Entrées blacklist simultanées ≈ 10 000
→ Taille : ~50 octets/entrée × 10 000 ≈ 500 KB — négligeable
```

---

### Stratégie 3 — Token versioning (révocation globale par user)

Au lieu de blacklister token par token, stocker un compteur/version par utilisateur. Toute session antérieure est invalidée d'un coup.

```python
# Modèle utilisateur
class User(models.Model):
    token_version = models.IntegerField(default=1)
    # Incrémenter = invalide TOUS les tokens précédents de cet utilisateur

# À l'émission
payload = {
    "sub": str(user.id),
    "ver": user.token_version,  # claim de version
    "exp": ...,
}

# À la vérification
def verify_with_version(payload):
    user = User.objects.get(id=payload["sub"])
    
    if payload.get("ver") != user.token_version:
        raise TokenRevokedException("Session révoquée — reconnexion requise")
    
    return payload

# Révocation globale (ex : changement de mot de passe, compromission)
def revoke_all_sessions(user):
    user.token_version += 1
    user.save()
    # TOUS les tokens existants sont immédiatement invalides
```

**Avantages/inconvénients :**
```
✓ Un seul entier en DB par utilisateur
✓ Révocation instantanée de toutes les sessions
✓ Idéal pour "déconnecter tous les appareils"
✗ Lookup DB à chaque requête (perd le caractère stateless)
✗ Révocation individuelle impossible (tout ou rien)
```

---

### Stratégie 4 — Rotation des refresh tokens (Refresh Token Rotation)

À chaque utilisation d'un refresh token, en émettre un nouveau et invalider l'ancien. Détecte la réutilisation (signe d'une compromission).

```javascript
// POST /api/auth/refresh
async function refreshHandler(req, res) {
  const oldRefreshToken = req.cookies.refresh_token;
  if (!oldRefreshToken) return res.status(401).json({ error: "Refresh token manquant" });

  let payload;
  try {
    payload = verifyToken(oldRefreshToken, REFRESH_SECRET);
  } catch {
    return res.status(401).json({ error: "Refresh token invalide" });
  }

  const { jti: oldJti, sub: userId } = payload;

  // Vérifier que le refresh token n'a pas déjà été utilisé
  const stored = await db.refreshTokens.findOne({ jti: oldJti });
  
  if (!stored || stored.used) {
    // ⚠️ ALERTE SÉCURITÉ : refresh token déjà utilisé → possible vol
    // Révoquer TOUTE la famille de tokens de cet utilisateur
    await db.refreshTokens.updateMany(
      { userId, family: stored?.family },
      { $set: { revoked: true } }
    );
    console.error(`SECURITY: Refresh token réutilisé pour user ${userId}`);
    return res.status(401).json({ error: "Session compromise — reconnexion requise" });
  }

  // Marquer l'ancien comme utilisé
  await db.refreshTokens.updateOne({ jti: oldJti }, { $set: { used: true } });

  // Émettre les nouveaux tokens
  const newJti = crypto.randomUUID();
  const newAccessToken  = generateAccessToken(userId);
  const newRefreshToken = generateRefreshToken(userId, newJti);

  // Sauvegarder le nouveau refresh token
  await db.refreshTokens.insertOne({
    jti: newJti,
    userId,
    family: stored.family,  // garder la même "famille" pour la détection
    used: false,
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 7 * 24 * 3600 * 1000),
  });

  res.cookie("refresh_token", newRefreshToken, {
    httpOnly: true, secure: true, sameSite: "Strict",
    maxAge: 7 * 24 * 3600 * 1000, path: "/api/auth/",
  });

  return res.json({ access_token: newAccessToken });
}
```

---

### Choisir la bonne stratégie

```
Application                    │ Stratégie recommandée
───────────────────────────────┼──────────────────────────────────────────
Blog, site vitrine, API simple │ Short-lived tokens uniquement (15 min)
SaaS, application web standard │ Short-lived + Refresh Token Rotation
Fintech, santé, données sensibles│ Short-lived + jti blacklist + versioning
Microservices distribués       │ Short-lived + validation JWKS centralisée
Appli mobile                   │ Short-lived + Refresh Token Rotation
                               │ + détection de réutilisation
```

---

## Récapitulatif — Architecture JWT Complète

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUX COMPLET                                │
│                                                                     │
│  1. Login                                                           │
│     Client → POST /auth/login → Serveur                            │
│     ← access_token (JSON body, 15 min)                             │
│     ← Set-Cookie: refresh_token=...; httpOnly; Secure              │
│                                                                     │
│  2. Requête authentifiée                                            │
│     Client → GET /api/resource                                      │
│              Authorization: Bearer <access_token>                   │
│     Serveur → vérifie signature + exp + jti blacklist              │
│     ← 200 OK + données                                             │
│                                                                     │
│  3. Refresh silencieux (access token expiré ou J-60s)              │
│     Client → POST /auth/refresh (cookie envoyé automatiquement)    │
│     Serveur → vérifie refresh token, émet nouveaux tokens          │
│     ← nouveau access_token + nouveau cookie refresh_token          │
│                                                                     │
│  4. Logout                                                          │
│     Client → POST /auth/logout                                      │
│     Serveur → jti access dans blacklist Redis                       │
│     Serveur → refresh token marqué "used" en DB                    │
│     ← Clear-Cookie: refresh_token                                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

*Cours rédigé dans le cadre d'une série sur les JSON Web Tokens — Étape 5 sur N.*