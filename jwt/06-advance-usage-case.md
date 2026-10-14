# Étape 6 — Cas d'Usage Avancés des JWT

> **Objectif** : Maîtriser les usages avancés de JWT dans des architectures modernes — microservices distribués, chiffrement de payload, WebSockets, fédération d'identité et Zero Trust.

---

## Sommaire

1. [JWT dans les microservices](#61-jwt-dans-les-microservices)
2. [Nested JWT (JWE)](#62-nested-jwt-jwe)
3. [JWT et WebSockets](#63-jwt-et-websockets)
4. [Federated Identity](#64-federated-identity)
5. [Zero Trust et JWT](#65-zero-trust-et-jwt)

---

## 6.1 JWT dans les Microservices

### Le problème de l'identité distribuée

Dans une architecture monolithique, l'identité de l'utilisateur est vérifiée une fois à l'entrée et propagée via la mémoire de la session. Dans les microservices, chaque service est un processus indépendant : il faut une convention pour transporter et valider l'identité à travers les appels inter-services.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Architecture microservices                   │
│                                                                 │
│  Client ──JWT──> API Gateway ──JWT──> Service A                │
│                       │                   │                     │
│                       │              ──JWT──> Service B         │
│                       │                   │                     │
│                       │              ──JWT──> Service C         │
│                                                                 │
│  Question : quel JWT circule entre les services ?              │
└─────────────────────────────────────────────────────────────────┘
```

Deux approches principales s'opposent.

---

### Approche 1 — Propagation directe du token utilisateur

Le token JWT de l'utilisateur est transmis tel quel d'un service à l'autre via le header `Authorization`.

```javascript
// Service A appelle Service B en propageant le token de l'utilisateur
async function callServiceB(userToken, data) {
  const response = await fetch("http://service-b/api/resource", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${userToken}`,  // token original propagé
      "Content-Type": "application/json",
    },
    body: JSON.stringify(data),
  });
  return response.json();
}
```

```
Avantages :
  ✓ Simple à implémenter
  ✓ Chaque service valide la signature lui-même
  ✓ Contexte utilisateur disponible partout

Inconvénients :
  ✗ Si le token expire entre deux appels, la chaîne se rompt
  ✗ Chaque service doit avoir accès à la clé de vérification
  ✗ Pas de distinction entre "appel utilisateur" et "appel service"
  ✗ Surface d'attaque : un service compromis peut réutiliser le token
```

---

### Approche 2 — Token Exchange (RFC 8693)

Le RFC 8693 définit un protocole pour qu'un service échange un token entrant contre un nouveau token adapté au contexte suivant. C'est la base de la délégation et de l'impersonation.

```
Flux Token Exchange :

  Utilisateur → JWT_user → Service A
  Service A   → [POST /oauth2/token] avec JWT_user
                → Authorization Server émet JWT_service_a
  Service A   → JWT_service_a → Service B
```

**Implémentation du Token Exchange :**

```python
# Service A demande un token pour appeler Service B
import httpx

async def exchange_token_for_service(incoming_user_token: str, target_service: str) -> str:
    """
    RFC 8693 — Token Exchange Request.
    Échange le token utilisateur contre un token de service avec scope limité.
    """
    response = await httpx.post(
        "https://auth.monapp.com/oauth2/token",
        data={
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "subject_token": incoming_user_token,
            "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
            "audience": target_service,               # scope réduit au service cible
            "requested_token_type": "urn:ietf:params:oauth:token-type:jwt",
            "scope": "read:resource",                 # permissions minimales
        },
        auth=(CLIENT_ID, CLIENT_SECRET),              # identité du Service A
    )
    data = response.json()
    return data["access_token"]
```

**Structure du token échangé :**

```json
{
  "sub": "user_42",
  "act": {
    "sub": "service-a"
  },
  "aud": "service-b",
  "scope": "read:resource",
  "exp": 1700001000,
  "iat": 1700000100
}
```

Le claim `act` (actor) indique quel service agit **au nom** de l'utilisateur — traçabilité complète dans les logs.

---

### Approche 3 — mTLS + JWT (authentification inter-services)

Pour les environnements haute sécurité, combiner mTLS (Mutual TLS) avec JWT donne deux couches d'authentification :

- **mTLS** : chaque service prouve son identité par un certificat X.509 → authentification de la **machine**
- **JWT** : porte l'identité de l'**utilisateur** ou du **service appelant**

```python
# Service A appelle Service B avec mTLS + JWT
import ssl
import httpx

# Certificat client du Service A (émis par PKI interne)
ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ssl_context.load_cert_chain("service-a.crt", "service-a.key")
ssl_context.load_verify_locations("internal-ca.crt")  # CA interne

async def call_with_mtls(token: str, url: str):
    async with httpx.AsyncClient(verify=ssl_context) as client:
        response = await client.get(
            url,
            headers={"Authorization": f"Bearer {token}"},
        )
    return response.json()
```

**Validation côté Service B :**

```python
def verify_mtls_and_jwt(request):
    # 1. mTLS vérifié par le reverse proxy (Nginx/Envoy) — cert client validé
    client_cert_cn = request.headers.get("X-Client-Cert-CN")  # injecté par le proxy
    
    if client_cert_cn not in ALLOWED_SERVICES:
        raise PermissionError(f"Service non autorisé : {client_cert_cn}")
    
    # 2. JWT vérifié par le service lui-même
    token = request.headers["Authorization"].replace("Bearer ", "")
    payload = jwt.decode(token, PUBLIC_KEY, algorithms=["RS256"])
    
    # 3. Vérifier la cohérence : le service déclaré dans le JWT correspond au certificat
    if payload.get("azp") != client_cert_cn:  # azp = authorized party
        raise SecurityError("Incohérence cert/JWT")
    
    return payload
```

---

### Partage de clés publiques entre microservices — JWKS Endpoint

Plutôt que de distribuer la clé publique manuellement à chaque service, exposer un endpoint JWKS (JSON Web Key Set) :

```python
# auth-service : exposition de la clé publique via JWKS
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import base64, json

def get_jwks():
    """Endpoint GET /.well-known/jwks.json"""
    with open("public_key.pem", "rb") as f:
        public_key = serialization.load_pem_public_key(f.read(), backend=default_backend())
    
    pub_numbers = public_key.public_key().public_numbers()
    
    def int_to_base64url(n):
        length = (n.bit_length() + 7) // 8
        return base64.urlsafe_b64encode(n.to_bytes(length, "big")).rstrip(b"=").decode()
    
    jwks = {
        "keys": [{
            "kty": "RSA",
            "use": "sig",
            "alg": "RS256",
            "kid": "key-2024-01",           # Key ID — permet la rotation
            "n": int_to_base64url(pub_numbers.n),
            "e": int_to_base64url(pub_numbers.e),
        }]
    }
    return json.dumps(jwks)

# Chaque microservice récupère la clé au démarrage (avec cache)
import httpx
from cachetools import TTLCache

_jwks_cache = TTLCache(maxsize=10, ttl=3600)  # cache 1h

async def get_verification_key(kid: str):
    if kid not in _jwks_cache:
        async with httpx.AsyncClient() as client:
            res = await client.get("https://auth-service/.well-known/jwks.json")
            jwks = res.json()
        for key_data in jwks["keys"]:
            _jwks_cache[key_data["kid"]] = load_rsa_public_key(key_data)
    return _jwks_cache.get(kid)
```

---

## 6.2 Nested JWT (JWE)

### JWT ≠ chiffrement

Un JWT signé (JWS) garantit l'**intégrité** et l'**authenticité** du payload, mais pas sa **confidentialité**. Quiconque intercepte le token peut décoder le payload (Base64URL n'est pas du chiffrement).

```bash
# N'importe qui peut décoder le payload d'un JWT signé
echo "eyJzdWIiOiJ1c2VyXzQyIiwicm9sZSI6ImFkbWluIn0" | base64 -d
# → {"sub":"user_42","role":"admin"}
```

**Quand le payload contient des données ultra-sensibles** (numéro de sécurité sociale, données médicales, informations financières), il faut chiffrer le token — c'est le JWE (JSON Web Encryption).

---

### Structure d'un JWE

Un JWE a **5 parties** séparées par des points :

```
BASE64URL(header)
. BASE64URL(encrypted_key)
. BASE64URL(initialization_vector)
. BASE64URL(ciphertext)
. BASE64URL(authentication_tag)
```

```json
// Header JWE typique
{
  "alg": "RSA-OAEP-256",   // algorithme pour chiffrer la clé symétrique
  "enc": "A256GCM",         // algorithme pour chiffrer le contenu
  "typ": "JWT"
}
```

| Champ | Rôle |
|-------|------|
| `alg` | Chiffrement de la **Content Encryption Key (CEK)** |
| `enc` | Chiffrement symétrique du **payload** avec la CEK |
| CEK | Clé symétrique aléatoire générée pour chaque token |

---

### Sign-then-Encrypt (Nested JWT)

La bonne pratique est **d'abord signer, puis chiffrer** :

1. Créer un JWT signé (JWS) avec le payload sensible
2. Chiffrer ce JWS entier dans un JWE

```
Plaintext payload → [signer avec clé privée RS256] → JWS
JWS → [chiffrer avec clé publique RSA-OAEP] → JWE (Nested JWT)
```

```python
# Avec python-jose — Nested JWT Sign-then-Encrypt
from jose import jws, jwe
from jose.constants import ALGORITHMS
import json, time

# Clés RSA (asymétriques)
SIGNING_PRIVATE_KEY  = open("signing_private.pem").read()   # pour signer
ENCRYPT_PUBLIC_KEY   = open("encrypt_public.pem").read()    # pour chiffrer

SIGNING_PUBLIC_KEY   = open("signing_public.pem").read()    # pour vérifier
ENCRYPT_PRIVATE_KEY  = open("encrypt_private.pem").read()   # pour déchiffrer

def create_nested_jwt(payload: dict) -> str:
    """Sign-then-Encrypt : JWS enveloppé dans JWE."""
    
    # 1. Signer le payload → JWS
    signed_token = jws.sign(
        payload,
        SIGNING_PRIVATE_KEY,
        algorithm=ALGORITHMS.RS256
    )
    
    # 2. Chiffrer le JWS → JWE
    encrypted_token = jwe.encrypt(
        signed_token.encode("utf-8"),  # le JWS devient le plaintext du JWE
        ENCRYPT_PUBLIC_KEY,
        algorithm=ALGORITHMS.RSA_OAEP_256,
        encryption=ALGORITHMS.A256GCM,
    )
    
    return encrypted_token.decode("utf-8")

def decode_nested_jwt(nested_jwt: str) -> dict:
    """Decrypt-then-Verify."""
    
    # 1. Déchiffrer le JWE → récupérer le JWS
    signed_token = jwe.decrypt(nested_jwt, ENCRYPT_PRIVATE_KEY)
    
    # 2. Vérifier la signature du JWS → récupérer le payload
    payload = jws.verify(
        signed_token,
        SIGNING_PUBLIC_KEY,
        algorithms=[ALGORITHMS.RS256]
    )
    
    return json.loads(payload)
```

```javascript
// Avec jose (Node.js) — Nested JWT
import { SignJWT, CompactEncrypt, jwtVerify, compactDecrypt, importPKCS8, importSPKI } from "jose";

async function createNestedJWT(payload) {
  const signingKey   = await importPKCS8(process.env.SIGNING_PRIVATE_KEY, "RS256");
  const encryptKey   = await importSPKI(process.env.ENCRYPT_PUBLIC_KEY,   "RSA-OAEP-256");

  // 1. Signer
  const signedJwt = await new SignJWT(payload)
    .setProtectedHeader({ alg: "RS256" })
    .setIssuedAt()
    .setExpirationTime("15m")
    .sign(signingKey);

  // 2. Chiffrer (le JWS signé est le plaintext)
  const encoder = new TextEncoder();
  const encryptedJwt = await new CompactEncrypt(encoder.encode(signedJwt))
    .setProtectedHeader({ alg: "RSA-OAEP-256", enc: "A256GCM", cty: "JWT" })
    .encrypt(encryptKey);

  return encryptedJwt;
}

async function decodeNestedJWT(token) {
  const decryptKey = await importPKCS8(process.env.ENCRYPT_PRIVATE_KEY, "RSA-OAEP-256");
  const verifyKey  = await importSPKI(process.env.SIGNING_PUBLIC_KEY,   "RS256");

  // 1. Déchiffrer
  const { plaintext } = await compactDecrypt(token, decryptKey);
  const signedJwt = new TextDecoder().decode(plaintext);

  // 2. Vérifier la signature
  const { payload } = await jwtVerify(signedJwt, verifyKey, {
    algorithms: ["RS256"],
  });

  return payload;
}
```

### Choix des algorithmes JWE

| `alg` (chiffrement de la CEK) | `enc` (chiffrement du contenu) | Usage recommandé |
|-------------------------------|-------------------------------|-----------------|
| `RSA-OAEP-256` | `A256GCM` | Standard moderne, recommandé |
| `ECDH-ES+A256KW` | `A256GCM` | Plus performant, courbes elliptiques |
| `A256KW` | `A256CBC-HS512` | Symétrique pur, secret partagé |
| `RSA1_5` | — | ❌ Obsolète, vulnérable (Bleichenbacher) |

> ⚠️ **Ne jamais utiliser `RSA1_5`** — vulnérable à l'attaque de Bleichenbacher. Toujours `RSA-OAEP` ou `ECDH-ES`.

---

### Quand utiliser JWE ?

```
JWS (signature seule) → cas général : intégrité + authenticité
JWE (chiffrement)     → données sensibles visibles en transit :
  - Données médicales / PHI (HIPAA)
  - Informations financières (PCI-DSS)
  - PII (RGPD — minimisation)
  - Tokens d'API traversant des proxies/CDN de tiers
  - Claims confidentiels entre parties (salaire, score de crédit...)
```

---

## 6.3 JWT et WebSockets

### Le problème spécifique des WebSockets

Le protocole WebSocket établit une connexion persistante via un handshake HTTP initial (upgrade). Après cet upgrade, il n'y a plus de headers HTTP classiques — impossible d'envoyer `Authorization: Bearer` sur chaque message.

```
HTTP Request  → GET /ws  HTTP/1.1
               Upgrade: websocket
               Connection: Upgrade
               (pas de corps, authentification ici seulement)
               
WebSocket ←──────────────────── connexion bidirectionnelle établie
Messages  ←──────────────────── frames binaires/texte, sans headers HTTP
```

---

### Approche 1 — Token dans le query string (à éviter en production)

```javascript
// Client
const ws = new WebSocket(`wss://api.monapp.com/ws?token=${accessToken}`);
```

**Côté serveur :**

```python
# Django Channels
from channels.middleware import BaseMiddleware
from urllib.parse import parse_qs
import jwt

class JWTAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        query_string = scope.get("query_string", b"").decode()
        params = parse_qs(query_string)
        token = params.get("token", [None])[0]
        
        if token:
            try:
                payload = jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])
                scope["user_id"] = payload["sub"]
            except jwt.InvalidTokenError:
                # Fermer la connexion immédiatement
                await send({"type": "websocket.close", "code": 4001})
                return
        
        await super().__call__(scope, receive, send)
```

**Pourquoi éviter le query string :**

```
Risques :
  ✗ Loggé par défaut dans les access logs (Nginx, Apache, AWS ALB...)
  ✗ Apparaît dans l'historique du navigateur
  ✗ Transmis dans le header Referer si redirection
  ✗ Accessible via JavaScript (window.location.search)
  ✗ Capturé par les outils d'analyse (Google Analytics, Datadog RUM...)

Acceptable uniquement si :
  → Logs désactivés ou filtrés pour cette route
  → Token de très courte durée (< 30 secondes, one-time)
  → Environnement de développement
```

---

### Approche 2 — Token dans le handshake HTTP (recommandée)

Utiliser les headers du handshake initial, avant l'upgrade WebSocket.

```javascript
// Client — via sous-protocole (Sec-WebSocket-Protocol hack)
// Note : l'API WebSocket browser ne permet pas d'envoyer de headers custom
// La convention est d'encoder le token dans un sous-protocole fictif

const ws = new WebSocket("wss://api.monapp.com/ws", [
  "access-token",
  accessToken,  // envoyé dans Sec-WebSocket-Protocol
]);
```

```python
# Serveur — extraction du token depuis Sec-WebSocket-Protocol
class JWTWebSocketMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        headers = dict(scope.get("headers", []))
        
        # Lire le header Sec-WebSocket-Protocol
        subprotocols = scope.get("subprotocols", [])
        
        token = None
        if len(subprotocols) >= 2 and subprotocols[0] == "access-token":
            token = subprotocols[1]
        
        if not token:
            await send({"type": "websocket.close", "code": 4001})
            return
        
        try:
            payload = jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])
            scope["user"] = payload
        except jwt.ExpiredSignatureError:
            await send({"type": "websocket.close", "code": 4002})  # 4002 = token expired
            return
        except jwt.InvalidTokenError:
            await send({"type": "websocket.close", "code": 4003})
            return
        
        await super().__call__(scope, receive, send)
```

---

### Approche 3 — Token dans le premier message (protocole applicatif)

La connexion WebSocket s'ouvre sans authentification. Le premier message doit être un message d'authentification. Si non reçu dans un délai imparti, la connexion est fermée.

```javascript
// Client
const ws = new WebSocket("wss://api.monapp.com/ws");

ws.onopen = () => {
  // Premier message = authentification
  ws.send(JSON.stringify({
    type: "auth",
    token: tokenStore.get(),
  }));
};

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.type === "auth_error") {
    ws.close(4001, "Authentification échouée");
    return;
  }
  // Traiter les messages normaux...
};
```

```python
# Serveur — Consumer Django Channels
import asyncio
import json
import jwt

class AuthenticatedConsumer(WebsocketConsumer):
    AUTH_TIMEOUT = 5  # secondes pour s'authentifier
    
    async def connect(self):
        self.authenticated = False
        self.auth_task = asyncio.ensure_future(self._auth_timeout())
        await self.accept()
    
    async def _auth_timeout(self):
        await asyncio.sleep(self.AUTH_TIMEOUT)
        if not self.authenticated:
            await self.close(code=4008)  # Auth timeout
    
    async def receive(self, text_data):
        data = json.loads(text_data)
        
        if not self.authenticated:
            if data.get("type") != "auth":
                await self.send(json.dumps({"type": "auth_error", "reason": "auth_required"}))
                await self.close(4001)
                return
            
            try:
                payload = jwt.decode(data["token"], settings.JWT_SECRET, algorithms=["HS256"])
                self.user_id = payload["sub"]
                self.authenticated = True
                self.auth_task.cancel()
                await self.send(json.dumps({"type": "auth_ok"}))
            except jwt.InvalidTokenError as e:
                await self.send(json.dumps({"type": "auth_error", "reason": str(e)}))
                await self.close(4001)
            return
        
        # Traitement des messages normaux post-authentification
        await self.handle_message(data)
```

---

### Gestion de l'expiration sur une connexion longue

Une connexion WebSocket peut rester ouverte des heures. Il faut gérer le renouvellement du token pendant la vie de la connexion.

```javascript
// Client — renouvellement proactif sur WebSocket actif
class AuthenticatedWebSocket {
  constructor(url) {
    this.url = url;
    this.ws = null;
    this.refreshTimer = null;
  }

  async connect() {
    const token = await this.getValidToken();
    this.ws = new WebSocket(this.url, ["access-token", token]);
    this.ws.onopen = () => this.scheduleTokenRefresh();
    this.ws.onclose = () => clearTimeout(this.refreshTimer);
  }

  scheduleTokenRefresh() {
    const token = tokenStore.get();
    const exp = getTokenExpiry(token) - Date.now() - 60_000;  // 60s de marge
    
    this.refreshTimer = setTimeout(async () => {
      const newToken = await refreshAccessToken();
      // Notifier le serveur du nouveau token via message
      this.ws.send(JSON.stringify({ type: "token_refresh", token: newToken }));
      this.scheduleTokenRefresh();  // planifier le prochain
    }, Math.max(exp, 0));
  }
}
```

---

## 6.4 Federated Identity

### SAML vs JWT/OIDC — Comparaison

Avant OIDC, le standard dominant de fédération d'identité était SAML 2.0. Comprendre les différences explique pourquoi JWT/OIDC a largement pris le dessus dans les architectures modernes.

| Critère | SAML 2.0 | OIDC + JWT |
|---------|----------|------------|
| Format | XML signé (verbeux) | JSON + JWT (compact) |
| Transport | HTTP POST (formulaires HTML) | HTTP redirect + Bearer |
| Adapté mobile/SPA | ❌ Non (nécessite browser redirect) | ✓ Oui |
| Complexité | Élevée (XML, assertions, bindings) | Modérée |
| Interopérabilité | Enterprise (AD FS, Okta) | Universal |
| Performances | Faibles (XML parsing) | Bonnes |
| Adoption | Legacy enterprise | Standard actuel |

**Quand encore utiliser SAML :**
- Intégration avec des SI d'entreprise anciens (Active Directory Federation Services)
- Conformité imposée par un partenaire corporate
- Migration progressive (SAML → OIDC bridge)

---

### OpenID Connect (OIDC) — le protocole

OIDC est une couche d'identité construite **au-dessus** d'OAuth 2.0. Il définit deux tokens JWT :

```
ID Token  → qui est l'utilisateur (identité)
           Claims standards : sub, name, email, picture, locale...

Access Token → ce que l'utilisateur peut faire (autorisation)
               Claims : scope, aud, exp, custom claims...
```

**Discovery Document — la clé de l'interopérabilité :**

Chaque IdP conforme OIDC expose un endpoint `.well-known/openid-configuration` qui décrit son API :

```bash
curl https://accounts.google.com/.well-known/openid-configuration
```

```json
{
  "issuer": "https://accounts.google.com",
  "authorization_endpoint": "https://accounts.google.com/o/oauth2/v2/auth",
  "token_endpoint": "https://oauth2.googleapis.com/token",
  "jwks_uri": "https://www.googleapis.com/oauth2/v3/certs",
  "userinfo_endpoint": "https://openidconnect.googleapis.com/v1/userinfo",
  "id_token_signing_alg_values_supported": ["RS256"],
  ...
}
```

---

### Intégration Auth0

```javascript
// Node.js / Express — vérification d'un token Auth0
const { auth } = require("express-oauth2-jwt-bearer");

// Middleware Auth0 — vérifie signature via JWKS Auth0 + audience + issuer
const checkJwt = auth({
  audience: "https://api.monapp.com",           // votre API identifier
  issuerBaseURL: "https://votre-tenant.auth0.com",
  tokenSigningAlg: "RS256",
});

// Routes protégées
app.get("/api/protected", checkJwt, (req, res) => {
  res.json({ user: req.auth.payload });
});
```

```python
# Python — vérification manuelle d'un token Auth0
import jwt
from jwt import PyJWKClient

AUTH0_DOMAIN   = "votre-tenant.auth0.com"
AUTH0_AUDIENCE = "https://api.monapp.com"

# JWKS client avec cache intégré
jwks_client = PyJWKClient(f"https://{AUTH0_DOMAIN}/.well-known/jwks.json")

def verify_auth0_token(token: str) -> dict:
    # Récupérer la clé publique correspondant au kid du token
    signing_key = jwks_client.get_signing_key_from_jwt(token)
    
    payload = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience=AUTH0_AUDIENCE,
        issuer=f"https://{AUTH0_DOMAIN}/",
    )
    return payload
```

---

### Intégration Keycloak (auto-hébergé)

```python
# Keycloak — vérification avec JWKS discovery
from functools import lru_cache
import httpx, jwt
from jwt import PyJWKClient

KEYCLOAK_URL   = "https://keycloak.monapp.com"
REALM          = "mon-realm"
CLIENT_ID      = "mon-api"

JWKS_URL = f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/certs"

@lru_cache(maxsize=1)
def get_jwks_client():
    return PyJWKClient(JWKS_URL, cache_jwk_set=True, lifespan=3600)

def verify_keycloak_token(token: str) -> dict:
    client = get_jwks_client()
    signing_key = client.get_signing_key_from_jwt(token)
    
    payload = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience=CLIENT_ID,
        issuer=f"{KEYCLOAK_URL}/realms/{REALM}",
        options={"verify_exp": True},
    )
    
    # Claims Keycloak spécifiques
    roles = payload.get("realm_access", {}).get("roles", [])
    client_roles = payload.get("resource_access", {}).get(CLIENT_ID, {}).get("roles", [])
    
    return {**payload, "roles": roles + client_roles}
```

---

### Intégration AWS Cognito

```python
# Cognito — vérification avec JWKS
import jwt
from jwt import PyJWKClient

COGNITO_REGION    = "eu-west-1"
COGNITO_USER_POOL = "eu-west-1_XXXXXXXX"
COGNITO_APP_CLIENT = "votre-app-client-id"

JWKS_URL = (
    f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com"
    f"/{COGNITO_USER_POOL}/.well-known/jwks.json"
)

jwks_client = PyJWKClient(JWKS_URL)

def verify_cognito_token(token: str, token_use: str = "access") -> dict:
    """
    token_use : "access" ou "id"
    Cognito émet deux types de JWT avec des validations différentes.
    """
    signing_key = jwks_client.get_signing_key_from_jwt(token)
    
    payload = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        # Pour un access token, l'audience est l'app client
        # Pour un id token, l'audience est aussi l'app client
        options={"verify_aud": token_use == "id"},
    )
    
    # Validation Cognito spécifique
    if payload.get("token_use") != token_use:
        raise ValueError(f"token_use attendu : {token_use}, reçu : {payload.get('token_use')}")
    
    if payload.get("iss") != f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{COGNITO_USER_POOL}":
        raise ValueError("Issuer Cognito invalide")
    
    return payload
```

---

### Flux d'authentification fédérée complet (OIDC Authorization Code + PKCE)

```
Utilisateur      Browser         Votre App        IdP (Auth0/Keycloak)
     │               │                │                    │
     │──── clic ────>│                │                    │
     │               │── redirect ───>│                    │
     │               │<── /auth?code_challenge=... ────────│
     │               │──────────────────────────────────── redirect ──>│
     │<── login page ────────────────────────────────────────────────  │
     │──── credentials ──────────────────────────────────────────────> │
     │               │<── redirect avec code= ────────────────────────│
     │               │── POST /callback?code= ──>│         │
     │               │                │─── POST /token ───>│
     │               │                │    code + verifier  │
     │               │                │<── id_token         │
     │               │                │    access_token     │
     │               │                │    refresh_token    │
     │               │<── session ────│                    │
```

**PKCE (Proof Key for Code Exchange) — pourquoi c'est obligatoire pour les SPAs :**

```javascript
// Génération du code_verifier et code_challenge (PKCE)
function generatePKCE() {
  // code_verifier : chaîne aléatoire 43-128 caractères
  const verifier = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
  
  // code_challenge = BASE64URL(SHA256(verifier))
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  
  return crypto.subtle.digest("SHA-256", data).then((hash) => {
    const challenge = btoa(String.fromCharCode(...new Uint8Array(hash)))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
    return { verifier, challenge };
  });
}
```

---

## 6.5 Zero Trust et JWT

### Le modèle Zero Trust

Le paradigme Zero Trust abandonne le modèle "château fort" (réseau interne = zone de confiance) au profit du principe :

```
"Ne jamais faire confiance, toujours vérifier."

Implication pour les JWT :
  - Chaque service vérifie le JWT sur chaque requête
  - Même les appels "internes" sont authentifiés
  - L'identité est portée par le token, pas par l'IP ou le réseau
  - Principe de moindre privilège : scope minimal par token
```

---

### JWT comme preuve d'identité Zero Trust

Dans une architecture Zero Trust, le JWT remplace la confiance implicite du réseau :

```
Architecture classique (périmètre) :
  Internet → [Firewall] → Zone interne
  Service A appelle Service B → pas d'auth (même réseau = confiance)

Architecture Zero Trust :
  Toute requête = suspecte par défaut
  Service A appelle Service B → JWT signé avec claims précis
  Service B vérifie : signature + exp + aud + scope + claims contextuels
```

**Claims contextuels Zero Trust :**

```json
{
  "sub": "service-payment",
  "aud": "service-fraud-detection",
  "scope": "fraud:check",
  "iat": 1700000000,
  "exp": 1700000060,    // 60 secondes — token à très courte durée de vie
  "jti": "uuid-unique",
  
  // Claims Zero Trust supplémentaires
  "client_id": "service-payment",
  "az_reason": "process_transaction",   // raison applicative de l'appel
  "transaction_id": "txn_abc123",       // contexte de la transaction
  "risk_score": 12,                     // score de risque au moment de l'émission
  "device_id": "pod-payment-xyz",       // identité de l'instance (Kubernetes pod)
  "region": "eu-west-1"
}
```

---

### SPIFFE / SPIRE

**SPIFFE** (Secure Production Identity Framework for Everyone) est un standard ouvert pour l'identité des workloads dans des environnements dynamiques (Kubernetes, VMs, lambdas).

**SPIRE** est l'implémentation de référence de SPIFFE.

#### Le problème que SPIFFE résout

Imaginez 50 microservices dans Kubernetes. Le service `payment` doit appeler le service `fraud-detection`. Comment `fraud-detection` sait-il que c'est **vraiment** `payment` qui l'appelle, et pas un attaquant qui a déployé un pod malveillant dans le cluster ?

```
Sans SPIFFE — solutions manuelles et fragiles :

  Option 1 : API keys partagées entre services
  → Cauchemar de gestion (rotation, fuites, qui a accès à quoi)

  Option 2 : JWT custom entre services
  → Vous gérez manuellement : distribution des clés, rotation, autorisation…

  Option 3 : mTLS manuel
  → Vous gérez une PKI complète vous-même
  → Rotation, renouvellement, révocation = emploi à temps plein
```

SPIFFE résout tout cela en fournissant une **identité cryptographique automatique** à chaque workload, sans intervention manuelle.

#### Analogie : l'état civil des microservices

```
Le monde réel                         Le monde SPIFFE
─────────────────                     ──────────────────
La mairie (délivre les papiers)     → SPIRE Server (émet les identités)
L'agent de quartier (vérifie)       → SPIRE Agent (atteste sur chaque nœud)
Votre carte d'identité              → SVID (JWT ou certificat prouvant l'identité)
Votre numéro de sécu (unique)       → SPIFFE ID : spiffe://monapp.com/service/payment
```

Comme dans le monde réel : vous n'avez pas à fabriquer votre propre carte d'identité. La mairie (SPIRE) la délivre automatiquement après avoir vérifié qui vous êtes.

#### Ce qui se passe concrètement au runtime

```
1. Le service "payment" démarre dans Kubernetes

2. L'agent SPIRE sur le nœud détecte le pod et vérifie :
   "Ce pod tourne avec le ServiceAccount 'payment',
    dans le namespace 'production' → identité confirmée"

3. SPIRE Server lui délivre un JWT-SVID signé :
   { "sub": "spiffe://monapp.com/service/payment" }

4. Quand payment appelle fraud-detection, il présente ce JWT

5. fraud-detection vérifie le JWT auprès de SPIRE
   → "C'est bien payment → accès autorisé"

Aucun secret à distribuer manuellement.
Aucun certificat à générer à la main.
SPIRE fait tout automatiquement via les métadonnées Kubernetes
(pod name, namespace, service account).
```

#### Concepts clés

```
SPIFFE introduit le concept de SVID (SPIFFE Verifiable Identity Document)
sous deux formes :
  - X.509 SVID (certificat TLS)
  - JWT-SVID (token JWT)

Le SPIFFE ID est une URI : spiffe://trust-domain/path
  Ex: spiffe://monapp.com/service/payment
      spiffe://monapp.com/service/fraud-detection
```

**Structure d'un JWT-SVID :**

```json
{
  "iss": "https://spire-server.monapp.com",
  "sub": "spiffe://monapp.com/service/payment",    // SPIFFE ID du workload
  "aud": ["spiffe://monapp.com/service/fraud-detection"],  // destinataire autorisé
  "exp": 1700000600,
  "iat": 1700000000
}
```

**Fonctionnement de SPIRE :**

```
┌──────────────────────────────────────────────────────────────┐
│                    Architecture SPIRE                        │
│                                                              │
│  SPIRE Server                                                │
│  ├── CA interne (émet les SVIDs)                             │
│  ├── Registration entries (quels workloads ont quelle ID)    │
│  └── Trust bundles (clés publiques de vérification)          │
│                                                              │
│  SPIRE Agent (sur chaque nœud)                               │
│  ├── Atteste l'identité du workload (PID, pod name, SA...)  │
│  ├── Obtient un SVID du Server                               │
│  └── Expose le Workload API (socket Unix)                    │
│                                                              │
│  Workload (votre service)                                    │
│  ├── Demande son SVID via la Workload API                   │
│  └── Utilise le JWT-SVID pour s'authentifier                │
└──────────────────────────────────────────────────────────────┘
```

**Intégration SPIFFE dans un service Python :**

```python
# Utiliser le SDK SPIFFE pour obtenir un JWT-SVID
from spiffe import SpiffeWorkloadApiClient, JwtSvid

async def get_service_token(audience: str) -> str:
    """Obtient un JWT-SVID pour appeler un service cible."""
    async with SpiffeWorkloadApiClient() as client:
        jwt_svid = await client.fetch_jwt_svid(audiences=[audience])
        return jwt_svid.token

async def verify_incoming_token(token: str) -> str:
    """Vérifie un JWT-SVID entrant et retourne le SPIFFE ID de l'appelant."""
    async with SpiffeWorkloadApiClient() as client:
        jwt_svid = await client.validate_jwt_svid(
            token=token,
            audience="spiffe://monapp.com/service/fraud-detection"  # notre identité
        )
        # Retourne : "spiffe://monapp.com/service/payment"
        return str(jwt_svid.spiffe_id)

# Utilisation dans un handler
async def handle_request(request):
    caller_token = request.headers["X-SPIFFE-Token"]
    
    try:
        caller_id = await verify_incoming_token(caller_token)
    except Exception:
        return Response(status=401)
    
    # Autorisation basée sur le SPIFFE ID
    ALLOWED_CALLERS = {
        "spiffe://monapp.com/service/payment",
        "spiffe://monapp.com/service/orders",
    }
    
    if caller_id not in ALLOWED_CALLERS:
        return Response(status=403)
    
    # Traitement...
```

---

### Intégration Envoy + SPIFFE (service mesh)

Dans un service mesh (Istio, Consul Connect), la validation JWT peut être déléguée au proxy sidecar :

```yaml
# Istio — RequestAuthentication pour valider les JWT automatiquement
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: jwt-auth
  namespace: production
spec:
  selector:
    matchLabels:
      app: fraud-detection
  jwtRules:
    - issuer: "https://spire-server.monapp.com"
      jwksUri: "https://spire-server.monapp.com/keys"
      audiences:
        - "spiffe://monapp.com/service/fraud-detection"
      forwardOriginalToken: true   # passer le token au service pour claims applicatifs

---
# AuthorizationPolicy — contrôle d'accès basé sur les claims
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-payment-only
  namespace: production
spec:
  selector:
    matchLabels:
      app: fraud-detection
  rules:
    - from:
        - source:
            requestPrincipals:
              - "https://spire-server.monapp.com/spiffe://monapp.com/service/payment"
      to:
        - operation:
            methods: ["POST"]
            paths: ["/fraud/check"]
```

---

### Quand SPIFFE/SPIRE est-il pertinent ?

```
Votre situation                         │ SPIFFE/SPIRE ?
────────────────────────────────────────┼──────────────────────────────────────
1 API + 1 SPA                           │ ✗ NON — complètement inutile
3-5 microservices simples               │ ✗ NON — JWT partagé ou API keys suffisent
10+ microservices dans Kubernetes       │ ~ PEUT-ÊTRE — commence à être pertinent
50+ services, multi-cluster, zero-trust │ ✓ OUI — c'est fait exactement pour ça
Environnement régulé (banque, santé)    │ ✓ OUI — identité cryptographique auditée
```

SPIFFE/SPIRE est un outil d'**infrastructure** pour des organisations qui gèrent des dizaines/centaines de microservices dans Kubernetes avec des exigences zero-trust. C'est typiquement mis en place par une équipe **plateforme/SRE**, pas par un développeur d'application.

Avec un service mesh (Istio), c'est encore plus transparent : le proxy sidecar Envoy obtient le SVID automatiquement, l'attache aux requêtes sortantes, vérifie les SVID entrants, et applique les règles d'autorisation. Votre code métier n'a **aucune ligne** liée à l'authentification inter-services.

### Matrice de décision — choisir son architecture d'identité

```
Contexte                              │ Solution recommandée
──────────────────────────────────────┼──────────────────────────────────────
Application web standard              │ OIDC + JWT (Auth0, Keycloak)
Microservices simples (< 10)          │ JWT partagé + JWKS centralisé
Microservices complexes (> 10)        │ Token Exchange (RFC 8693)
Kubernetes / service mesh             │ SPIFFE/SPIRE + Istio/Envoy
Données médicales / financières       │ JWE (Nested JWT) + mTLS
Partenaires enterprise legacy         │ SAML 2.0 → OIDC bridge
Applications mobiles                  │ OIDC + PKCE + Refresh Token Rotation
IoT / edge                            │ JWT-SVID ou certificats X.509 courts
```

---

## Récapitulatif — Étape 6

| Section | Concept clé | À retenir |
|---------|-------------|-----------|
| 6.1 | Microservices | Token Exchange > propagation brute ; JWKS centralisé |
| 6.2 | JWE | Sign-then-Encrypt ; `RSA-OAEP-256` + `A256GCM` ; jamais `RSA1_5` |
| 6.3 | WebSockets | Handshake > query string ; gérer l'expiration sur connexion longue |
| 6.4 | OIDC | PKCE obligatoire pour SPA ; JWKS pour vérification IdP externe |
| 6.5 | Zero Trust | Chaque requête vérifiée ; SPIFFE pour l'identité des workloads |

---

*Cours rédigé dans le cadre d'une série sur les JSON Web Tokens — Étape 6 sur N.*