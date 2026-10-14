# Étape 7 — Standards, RFCs et Écosystème JWT

> **Objectif** : Comprendre les fondations normatives de l'écosystème JWT — qui définit quoi, comment les standards s'articulent entre eux, et ce que chaque RFC apporte concrètement à l'implémenteur.

---

## Sommaire

1. [La famille JOSE (RFC 7515–7518)](#1-la-famille-jose-rfc-75157518)
2. [RFC 7519 — JSON Web Token](#2-rfc-7519--json-web-token)
3. [RFC 6749 — OAuth 2.0](#3-rfc-6749--oauth-20)
4. [RFC 6750 — Bearer Token Usage](#4-rfc-6750--bearer-token-usage)
5. [RFC 8693 — Token Exchange](#5-rfc-8693--token-exchange)
6. [OpenID Connect Core 1.0](#6-openid-connect-core-10)
7. [Comment les standards s'articulent](#7-comment-les-standards-sarticulent)
8. [Lire une RFC — guide pratique](#8-lire-une-rfc--guide-pratique)
9. [Écosystème et outils](#9-écosystème-et-outils)

---

## 1. La Famille JOSE (RFC 7515–7518)

**JOSE** — JSON Object Signing and Encryption — est le socle cryptographique sur lequel JWT est construit. Il est défini par quatre RFCs interdépendantes publiées simultanément en mai 2015.

```
┌─────────────────────────────────────────────────────────────┐
│                    Famille JOSE                             │
│                                                             │
│  RFC 7518 ─ JWA ─ "quels algorithmes sont autorisés"       │
│       ↑                  ↑                                  │
│  RFC 7515 ─ JWS     RFC 7516 ─ JWE                         │
│   "comment signer"   "comment chiffrer"                     │
│       ↑                  ↑                                  │
│  RFC 7517 ─ JWK ─ "comment représenter les clés"           │
│                          ↑                                  │
│  RFC 7519 ─ JWT ─ "structure du token applicatif"           │
└─────────────────────────────────────────────────────────────┘
```

---

### RFC 7515 — JSON Web Signature (JWS)

**Ce que ça définit :** la structure et le processus de création/vérification d'un objet JSON signé.

**Deux sérialisations définies :**

```
Compact Serialization (la plus courante — c'est le JWT que vous connaissez) :
  BASE64URL(header) . BASE64URL(payload) . BASE64URL(signature)

JSON Serialization (moins courante — multi-signatures) :
  {
    "payload": "BASE64URL(payload)",
    "signatures": [
      {
        "protected": "BASE64URL(header1)",
        "header": {"kid": "key-1"},
        "signature": "BASE64URL(sig1)"
      },
      {
        "protected": "BASE64URL(header2)",
        "signature": "BASE64URL(sig2)"
      }
    ]
  }
```

**Registre des headers JWS (section 4.1) :**

| Header | Nom complet | Rôle |
|--------|-------------|------|
| `alg` | Algorithm | Algorithme de signature (**obligatoire**) |
| `jku` | JWK Set URL | URL vers le JWKS de vérification |
| `jwk` | JSON Web Key | Clé publique inline |
| `kid` | Key ID | Identifiant de la clé (pour rotation) |
| `x5u` | X.509 URL | URL vers le certificat X.509 |
| `x5c` | X.509 Chain | Chaîne de certificats inline |
| `x5t` | X.509 Thumbprint | Empreinte SHA-1 du certificat |
| `x5t#S256` | X.509 Thumbprint S256 | Empreinte SHA-256 du certificat |
| `typ` | Type | Type du token (ex. `JWT`) |
| `cty` | Content Type | Type du contenu (ex. `JWT` pour Nested JWT) |
| `crit` | Critical | Headers que le destinataire **doit** comprendre |

**Le processus de signature (section 5) :**

```
1. Créer le header JSON : {"alg":"HS256","typ":"JWT"}
2. Encoder en BASE64URL → header_b64
3. Créer le payload JSON : {"sub":"user","exp":...}
4. Encoder en BASE64URL → payload_b64
5. Signing Input = ASCII(header_b64 + "." + payload_b64)
6. Signature = SIGN(alg, key, Signing Input)
7. Token = header_b64 + "." + payload_b64 + "." + BASE64URL(Signature)
```

**Point clé souvent mal compris :** la signature porte sur `ASCII(BASE64URL(header) || '.' || BASE64URL(payload))` — pas sur le JSON brut. Le moindre espace supplémentaire dans le JSON ne change pas la signature si le Base64URL est identique.

---

### RFC 7516 — JSON Web Encryption (JWE)

**Ce que ça définit :** la structure et le processus de chiffrement d'un payload JSON.

**Structure compacte (5 parties) :**

```
BASE64URL(header)
. BASE64URL(encrypted_key)
. BASE64URL(iv)
. BASE64URL(ciphertext)
. BASE64URL(authentication_tag)
```

**Registre des headers JWE :**

| Header | Rôle |
|--------|------|
| `alg` | Algorithme de wrapping de la CEK |
| `enc` | Algorithme de chiffrement du contenu |
| `zip` | Compression avant chiffrement (`DEF` = deflate) |
| `jku`, `jwk`, `kid` | Identité de la clé (même sémantique que JWS) |
| `epk` | Clé publique éphémère (pour ECDH-ES) |
| `apu`, `apv` | Infos pour dérivation de clé ECDH |
| `p2s`, `p2c` | Salt et itérations PBKDF2 (pour PBES2) |
| `iv`, `tag` | IV et tag d'authentification (JSON serialization) |
| `cty` | `JWT` pour Nested JWT |

**Le processus de chiffrement (section 5) :**

```
1. Générer une CEK (Content Encryption Key) aléatoire
2. Chiffrer la CEK avec la clé du destinataire → Encrypted Key
3. Générer un IV aléatoire
4. Chiffrer le plaintext avec la CEK → Ciphertext + Authentication Tag
   (AEAD = Authenticated Encryption with Associated Data)
5. Les Additional Authenticated Data (AAD) = BASE64URL(header)
   → protège le header contre la falsification même sans le déchiffrer
```

**Pourquoi deux algorithmes (`alg` + `enc`) ?**

La CEK symétrique chiffre le payload (rapide même pour de gros contenus). L'algorithme `alg` protège uniquement la petite CEK avec la clé asymétrique du destinataire. C'est le pattern **hybrid encryption**, plus efficace que le chiffrement asymétrique direct du payload entier.

---

### RFC 7517 — JSON Web Key (JWK)

**Ce que ça définit :** la représentation JSON standardisée des clés cryptographiques.

**Structure d'un JWK :**

```json
{
  "kty": "RSA",         // Key Type : RSA, EC, oct (symétrique), OKP (EdDSA)
  "use": "sig",         // Public Key Use : "sig" (signature) ou "enc" (chiffrement)
  "key_ops": ["verify"],// Key Operations : sign, verify, encrypt, decrypt, wrapKey...
  "alg": "RS256",       // Algorithm : algo prévu pour cette clé
  "kid": "key-2024-01", // Key ID : référencé dans le header JWT
  "n": "...",           // RSA modulus (Base64URL)
  "e": "AQAB",          // RSA public exponent (65537)
  // "d", "p", "q"... → partie privée (ne jamais exposer dans JWKS public)
}
```

**JWK par type de clé :**

```json
// Clé symétrique (oct) — HS256
{
  "kty": "oct",
  "k": "BASE64URL(secret_bytes)",
  "alg": "HS256"
}

// Clé EC (courbe P-256) — ES256
{
  "kty": "EC",
  "crv": "P-256",
  "x": "BASE64URL(x_coordinate)",
  "y": "BASE64URL(y_coordinate)",
  "d": "BASE64URL(private_key)"  // absent de la partie publique
}

// Clé OKP (Ed25519) — EdDSA
{
  "kty": "OKP",
  "crv": "Ed25519",
  "x": "BASE64URL(public_key)",
  "d": "BASE64URL(private_key)"  // absent de la partie publique
}
```

**JWKS (JSON Web Key Set) — ensemble de clés :**

```json
{
  "keys": [
    { "kty": "RSA", "kid": "key-2024-01", "use": "sig", "alg": "RS256", "n": "...", "e": "AQAB" },
    { "kty": "RSA", "kid": "key-2024-02", "use": "sig", "alg": "RS256", "n": "...", "e": "AQAB" }
  ]
}
```

Exposer plusieurs clés dans le JWKS permet la **rotation progressive** : l'ancienne clé reste disponible pour vérifier les tokens existants, la nouvelle est utilisée pour les nouveaux tokens.

**Rotation de clés avec `kid` :**

```python
# À la création du token — inclure le kid dans le header
header = {"alg": "RS256", "typ": "JWT", "kid": "key-2024-02"}

# À la vérification — choisir la bonne clé depuis le JWKS
def verify_with_kid(token: str) -> dict:
    header = jwt.get_unverified_header(token)
    kid = header.get("kid")
    
    # Récupérer la clé correspondante depuis le JWKS
    key = jwks_client.get_signing_key(kid)
    
    return jwt.decode(token, key.key, algorithms=["RS256"])
```

---

### RFC 7518 — JSON Web Algorithms (JWA)

**Ce que ça définit :** le registre officiel des algorithmes autorisés dans l'écosystème JOSE, leurs paramètres, et leur niveau de support requis.

**Algorithmes de signature (pour JWS) :**

| `alg` | Algorithme | Type | Recommandation |
|-------|-----------|------|----------------|
| `HS256` | HMAC + SHA-256 | Symétrique | ✓ Courant, secret partagé requis |
| `HS384` | HMAC + SHA-384 | Symétrique | Marginal gain sur HS256 |
| `HS512` | HMAC + SHA-512 | Symétrique | Marginal gain sur HS256 |
| `RS256` | RSA PKCS#1 + SHA-256 | Asymétrique | ✓ **Recommandé** production |
| `RS384` | RSA PKCS#1 + SHA-384 | Asymétrique | — |
| `RS512` | RSA PKCS#1 + SHA-512 | Asymétrique | — |
| `ES256` | ECDSA P-256 + SHA-256 | Asymétrique | ✓ **Recommandé** (plus rapide) |
| `ES384` | ECDSA P-384 + SHA-384 | Asymétrique | Usage gouvernemental |
| `ES512` | ECDSA P-521 + SHA-512 | Asymétrique | — |
| `PS256` | RSA-PSS + SHA-256 | Asymétrique | ✓ Supérieur à RS256 |
| `EdDSA` | Ed25519 / Ed448 | Asymétrique | ✓ Moderne, performant |
| `none` | Pas de signature | — | ❌ **Interdit en production** |

**Algorithmes de wrapping de clé (pour JWE `alg`) :**

| `alg` | Algorithme | Notes |
|-------|-----------|-------|
| `RSA-OAEP` | RSA-OAEP + SHA-1 | ✓ Acceptable |
| `RSA-OAEP-256` | RSA-OAEP + SHA-256 | ✓ **Recommandé** |
| `RSA1_5` | RSA PKCS#1 v1.5 | ❌ **Interdit** — Bleichenbacher |
| `A128KW` | AES Key Wrap 128 bits | Symétrique |
| `A256KW` | AES Key Wrap 256 bits | ✓ Symétrique recommandé |
| `ECDH-ES` | ECDH-ES direct | ✓ Pas d'encrypted_key |
| `ECDH-ES+A256KW` | ECDH-ES + AES-KW 256 | ✓ **Recommandé** EC |
| `PBES2-HS256+A128KW` | Password-based | Clés dérivées de mots de passe |

**Algorithmes de chiffrement de contenu (pour JWE `enc`) :**

| `enc` | Algorithme | Notes |
|-------|-----------|-------|
| `A128CBC-HS256` | AES-128-CBC + HMAC-SHA-256 | Acceptable |
| `A256CBC-HS512` | AES-256-CBC + HMAC-SHA-512 | Acceptable |
| `A128GCM` | AES-128 GCM | ✓ Recommandé |
| `A256GCM` | AES-256 GCM | ✓ **Recommandé** |

**Niveaux de support définis par JWA (section 3.1) :**

```
"Required"        → toute implémentation conforme DOIT supporter
"Recommended"     → devrait supporter (interopérabilité attendue)
"Optional"        → peut supporter
"Deprecated"      → ne devrait plus être utilisé dans les nouvelles implémentations
"Prohibited"      → ne doit jamais être utilisé (ex. alg:none avec payload sensible)
```

---

## 2. RFC 7519 — JSON Web Token

**Ce que ça définit :** la structure applicative du JWT — les claims standards, leurs sémantiques précises, et les règles de validation.

### Claims enregistrés (section 4.1)

La RFC 7519 définit 7 claims "registered" — leur sémantique est standardisée, leur présence est optionnelle sauf contrainte applicative.

| Claim | Nom | Type | Description précise |
|-------|-----|------|---------------------|
| `iss` | Issuer | StringOrURI | Émetteur du token — qui l'a créé |
| `sub` | Subject | StringOrURI | Sujet du token — pour qui il est émis |
| `aud` | Audience | StringOrURI / Array | Destinataire(s) du token — qui doit l'accepter |
| `exp` | Expiration Time | NumericDate | Timestamp Unix — après lequel le token est invalide |
| `nbf` | Not Before | NumericDate | Timestamp Unix — avant lequel le token est invalide |
| `iat` | Issued At | NumericDate | Timestamp Unix — quand le token a été créé |
| `jti` | JWT ID | String | Identifiant unique du token |

**Détails importants sur `aud` (section 4.1.3) :**

```json
// aud peut être une string...
{ "aud": "https://api.monapp.com" }

// ...ou un tableau de strings
{ "aud": ["https://api.monapp.com", "https://admin.monapp.com"] }
```

La règle de validation : le serveur **doit** rejeter le token si son propre identifiant n'est pas dans `aud`. Cette règle est la source de nombreux bugs d'intégration — ne jamais désactiver `verify_aud`.

**`NumericDate` — définition précise (section 2) :**

```
NumericDate = nombre de secondes depuis 1970-01-01T00:00:00Z UTC
              (pas de millisecondes, pas de timezone)

En Python : int(datetime.now(timezone.utc).timestamp())
En JS     : Math.floor(Date.now() / 1000)
```

**Règle de validation `exp` (section 4.1.4) :**

```
Le token est rejeté si :
  current_time > exp
  
Avec tolérance horloge (clockSkew) :
  current_time > exp + leeway

La RFC recommande une tolérance "de quelques minutes" pour
compenser les désynchronisations d'horloges entre serveurs.
```

### Claims publics et privés

```
Claims enregistrés (section 4.1) :
  → Définis par la RFC 7519, sémantique standardisée
  → iss, sub, aud, exp, nbf, iat, jti

Claims publics (section 4.2) :
  → Définis dans le registre IANA "JSON Web Token Claims"
  → Évitent les collisions de noms entre organisations
  → Exemples : email, name, phone_number (définis par OIDC)
               roles, permissions (définis par Auth0)

Claims privés (section 4.3) :
  → Définis par accord entre émetteur et récepteur
  → Risque de collision → préfixer par namespace recommandé
  → Exemple : "https://monapp.com/role": "admin"
```

**Registre IANA des claims JWT :**

```
https://www.iana.org/assignments/jwt/jwt.xhtml

Claims OIDC enregistrés (exemples) :
  name, given_name, family_name, email, email_verified,
  phone_number, address, birthdate, locale, zoneinfo,
  updated_at, nonce, auth_time, acr, amr, azp, sid
```

---

## 3. RFC 6749 — OAuth 2.0

**Ce que ça définit :** le framework d'autorisation délégué. OAuth 2.0 lui-même ne définit **pas** JWT — c'est un framework générique. JWT est devenu le format standard pour les access tokens OAuth2, mais la RFC 6749 parle de "tokens opaques".

### Les 4 grant types OAuth 2.0

**1. Authorization Code (+ PKCE) — le plus sûr, pour les apps avec serveur**

```
Client → [GET /authorize?response_type=code&...] → Auth Server
Auth Server → [redirect?code=xyz] → Client
Client → [POST /token {code=xyz, code_verifier=...}] → Auth Server
Auth Server → {access_token, refresh_token, id_token} → Client
```

**2. Client Credentials — machine-to-machine (M2M)**

```
Service → [POST /token {grant_type=client_credentials, client_id, client_secret}]
       → Auth Server
Auth Server → {access_token} → Service
```

```python
# Client Credentials en Python
import httpx

async def get_m2m_token() -> str:
    response = await httpx.post(
        "https://auth.monapp.com/oauth2/token",
        data={
            "grant_type": "client_credentials",
            "scope": "read:orders write:invoices",
        },
        auth=(CLIENT_ID, CLIENT_SECRET),
    )
    return response.json()["access_token"]
```

**3. Device Code — appareils sans navigateur (TV, CLI)**

```
Device → [POST /device/code] → {device_code, user_code, verification_uri}
Device → affiche user_code à l'utilisateur
User   → visite verification_uri sur son téléphone, entre user_code, approuve
Device → poll [POST /token {grant_type=device_code, device_code}]
       → reçoit les tokens quand l'utilisateur a approuvé
```

**4. Refresh Token — renouvellement silencieux**

```
Client → [POST /token {grant_type=refresh_token, refresh_token=xyz}]
       → Auth Server
Auth Server → {new_access_token, new_refresh_token} → Client
```

**Grant types dépréciés (ne pas utiliser) :**

```
Implicit          → remplacé par Authorization Code + PKCE
Resource Owner    → donne le mot de passe directement à l'app
Password Credentials  (le client n'est pas l'auth server)
```

### Scopes OAuth2

Le scope est une chaîne d'espaces délimitant les permissions demandées :

```
"read:profile write:orders admin:users"

Conventions courantes :
  resource:action → "orders:read", "invoices:write"
  ou namespace/action → "https://monapp.com/read:admin"
```

```python
# Vérification du scope dans un token JWT
def require_scope(required_scope: str):
    def decorator(view_func):
        @wraps(view_func)
        def wrapper(request, *args, **kwargs):
            token_scopes = request.jwt_payload.get("scope", "").split()
            if required_scope not in token_scopes:
                return JsonResponse(
                    {"error": "insufficient_scope", "required": required_scope},
                    status=403
                )
            return view_func(request, *args, **kwargs)
        return wrapper
    return decorator

# Usage
@jwt_required
@require_scope("invoices:write")
def create_invoice(request):
    ...
```

---

## 4. RFC 6750 — Bearer Token Usage

**Ce que ça définit :** comment transmettre un Bearer Token dans une requête HTTP. "Bearer" signifie que quiconque possède le token peut l'utiliser — d'où l'importance de le protéger.

### Les 3 méthodes de transmission

**Méthode 1 — Authorization Header (recommandée, section 2.1) :**

```http
GET /api/resource HTTP/1.1
Host: api.monapp.com
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyXzQyIn0.abc123
```

**Méthode 2 — Form-encoded body (section 2.2) :**

```http
POST /api/resource HTTP/1.1
Content-Type: application/x-www-form-urlencoded

access_token=eyJhbGciOiJIUzI1NiJ9...
```

Uniquement pour les requêtes avec corps. La RFC impose que le Content-Type soit `application/x-www-form-urlencoded`.

**Méthode 3 — Query parameter (section 2.3) :**

```
GET /api/resource?access_token=eyJhbGciOiJIUzI1NiJ9...
```

Déconseillé par la RFC elle-même (section 2.3) : "This method is included to document current use cases; its use is not recommended, due to its security deficiencies."

### Codes d'erreur standardisés (section 3)

La RFC 6750 définit un format de réponse d'erreur standardisé via le header `WWW-Authenticate` :

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer realm="api.monapp.com",
                  error="invalid_token",
                  error_description="Token expiré",
                  error_uri="https://docs.monapp.com/errors/token-expired"
```

| `error` | Signification | HTTP Status |
|---------|---------------|-------------|
| `invalid_request` | Requête malformée (ex. token absent) | 400 |
| `invalid_token` | Token invalide, expiré, révoqué | 401 |
| `insufficient_scope` | Token valide mais scope insuffisant | 403 |

```python
# Django — réponses d'erreur conformes RFC 6750
def unauthorized_response(error: str, description: str) -> JsonResponse:
    response = JsonResponse({"error": error, "error_description": description}, status=401)
    response["WWW-Authenticate"] = (
        f'Bearer realm="api.monapp.com",'
        f'error="{error}",'
        f'error_description="{description}"'
    )
    return response
```

---

## 5. RFC 8693 — Token Exchange

**Ce que ça définit :** un extension d'OAuth 2.0 pour échanger un token contre un autre token avec des caractéristiques différentes. Fondamental pour les architectures microservices (implémentation vue à l'étape 6.1).

### Les trois opérations

**1. Impersonation :** le service agit entièrement **au nom** de l'utilisateur

```json
Request:
{
  "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
  "subject_token": "<token_utilisateur>",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "audience": "service-b"
}

Token résultant :
{ "sub": "user_42", "aud": "service-b" }
//  ↑ même subject que l'utilisateur = impersonation
```

**2. Délégation :** le service agit pour l'utilisateur **mais en son propre nom**

```json
Request:
{
  "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
  "subject_token": "<token_utilisateur>",
  "actor_token": "<token_service_a>",        // identité de l'acteur
  "actor_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "audience": "service-b"
}

Token résultant :
{
  "sub": "user_42",
  "act": { "sub": "service-a" },   // act = actor — traçabilité complète
  "aud": "service-b"
}
```

**3. Downscoping :** réduire les permissions d'un token existant

```json
Request:
{
  "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
  "subject_token": "<token_admin>",
  "scope": "read:orders",          // scope réduit
  "audience": "service-orders"
}
```

### Token types URI définis par la RFC

| URI | Type de token |
|-----|--------------|
| `urn:ietf:params:oauth:token-type:jwt` | JWT (JWS Compact) |
| `urn:ietf:params:oauth:token-type:access_token` | Access token OAuth2 |
| `urn:ietf:params:oauth:token-type:refresh_token` | Refresh token |
| `urn:ietf:params:oauth:token-type:id_token` | ID token OIDC |
| `urn:ietf:params:oauth:token-type:saml2` | Assertion SAML 2.0 |

---

## 6. OpenID Connect Core 1.0

**Ce que ça définit :** une couche d'**identité** au-dessus d'OAuth 2.0. OAuth2 répond à "qu'est-ce que cette application peut faire ?", OIDC répond à "qui est cet utilisateur ?".

### OIDC n'est pas une RFC IETF

OIDC est une spécification de l'**OpenID Foundation**, pas de l'IETF. Elle est divisée en plusieurs documents :

| Document | Contenu |
|---------|---------|
| Core 1.0 | Flux d'authentification, ID Token, UserInfo |
| Discovery 1.0 | `.well-known/openid-configuration` |
| Dynamic Client Registration 1.0 | Enregistrement dynamique de clients |
| Session Management 1.0 | Gestion des sessions et logout |
| Front-Channel Logout 1.0 | Logout initié par l'IdP (iframe) |
| Back-Channel Logout 1.0 | Logout via webhook serveur |

### L'ID Token

L'ID Token est **toujours un JWT signé** (jamais JWE par défaut). Il contient les claims d'identité de l'utilisateur.

**Claims obligatoires de l'ID Token (section 2) :**

| Claim | Obligatoire | Description |
|-------|-------------|-------------|
| `iss` | ✓ | URL du Provider OIDC |
| `sub` | ✓ | Identifiant unique de l'utilisateur (stable, non réutilisable) |
| `aud` | ✓ | `client_id` de l'application |
| `exp` | ✓ | Expiration |
| `iat` | ✓ | Date d'émission |
| `auth_time` | Conditionnel | Heure d'authentification effective |
| `nonce` | Si demandé | Protection contre les replay attacks (CSRF dans OIDC) |
| `acr` | Optionnel | Authentication Context Class Reference |
| `amr` | Optionnel | Authentication Methods References (ex. `["pwd","otp"]`) |
| `azp` | Conditionnel | Authorized Party — si `aud` est multi-valeur |

**Claims d'identité standardisés (section 5.1) :**

```json
{
  "sub": "248289761001",
  "name": "Jean Dupont",
  "given_name": "Jean",
  "family_name": "Dupont",
  "middle_name": "Pierre",
  "nickname": "jeandupont",
  "preferred_username": "j.dupont",
  "profile": "https://example.com/~jdupont",
  "picture": "https://example.com/jdupont/me.jpg",
  "website": "https://jdupont.fr",
  "email": "jdupont@example.com",
  "email_verified": true,
  "gender": "male",
  "birthdate": "1990-01-15",
  "zoneinfo": "Africa/Porto-Novo",
  "locale": "fr-BJ",
  "phone_number": "+229123456789",
  "phone_number_verified": false,
  "address": {
    "formatted": "123 rue de la Liberté, Cotonou, Bénin",
    "country": "BJ"
  },
  "updated_at": 1700000000
}
```

### Les 3 flux OIDC

**1. Authorization Code Flow (recommandé)**

```
→ `response_type=code`
→ Retourne un code → échangé contre tokens via /token
→ Tokens jamais exposés dans l'URL
→ Compatible PKCE → recommandé pour toutes les apps
```

**2. Implicit Flow (déprécié)**

```
→ `response_type=id_token token`
→ Tokens retournés directement dans le fragment d'URL (#)
→ Exposés dans les logs, referer, history
→ À ne plus utiliser — remplacé par Auth Code + PKCE
```

**3. Hybrid Flow (rare)**

```
→ `response_type=code id_token`
→ Combinaison des deux : code ET id_token dans la réponse initiale
→ Cas d'usage : vérifier l'identité immédiatement sans attendre /token
```

### Le `nonce` — protection contre les replay attacks dans OIDC

```python
import secrets

# 1. Générer et stocker le nonce avant la redirection
nonce = secrets.token_urlsafe(32)
session["oidc_nonce"] = nonce

# 2. L'inclure dans la requête d'autorisation
auth_url = (
    f"{AUTH_SERVER}/authorize"
    f"?response_type=code&client_id={CLIENT_ID}"
    f"&redirect_uri={REDIRECT_URI}&scope=openid profile email"
    f"&nonce={nonce}"
    f"&state={state}"  # protection CSRF separate
)

# 3. Après réception de l'ID Token, vérifier le nonce
def verify_id_token(id_token: str, expected_nonce: str) -> dict:
    payload = jwt.decode(id_token, PUBLIC_KEY, algorithms=["RS256"],
                         audience=CLIENT_ID, issuer=ISSUER)
    
    if payload.get("nonce") != expected_nonce:
        raise SecurityError("Nonce invalide — possible replay attack")
    
    return payload
```

---

## 7. Comment les Standards s'Articulent

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Vue d'ensemble des standards                    │
│                                                                     │
│  OIDC Core 1.0                                                      │
│  "Qui est l'utilisateur ?"                                          │
│       └── s'appuie sur OAuth 2.0 (RFC 6749)                        │
│               "Que peut faire cette app ?"                          │
│                   └── utilise Bearer Tokens (RFC 6750)              │
│                           └── format = JWT (RFC 7519)               │
│                                   └── structure = JWS (RFC 7515)   │
│                                                ou JWE (RFC 7516)    │
│                                       algorithmes = JWA (RFC 7518)  │
│                                       clés = JWK (RFC 7517)         │
│                                                                     │
│  RFC 8693 (Token Exchange)                                          │
│       └── étend OAuth 2.0 pour les microservices                   │
└─────────────────────────────────────────────────────────────────────┘
```

**Interactions concrètes :**

```
1. Un utilisateur se connecte via OIDC (Auth0/Keycloak)
   → OIDC utilise OAuth 2.0 Authorization Code Flow (RFC 6749)
   → L'auth server retourne un ID Token + Access Token
   → Les deux sont des JWT (RFC 7519)
   → Le JWT est signé en JWS (RFC 7515)
   → L'algorithme est RS256 défini dans JWA (RFC 7518)
   → La clé publique est exposée en JWKS (RFC 7517)

2. L'Access Token est envoyé à l'API
   → Via Authorization: Bearer header (RFC 6750)
   → L'API vérifie le JWT : signature JWS + claims RFC 7519

3. L'API appelle un microservice interne
   → Token Exchange (RFC 8693) via OAuth 2.0
   → Nouveau JWT avec claim "act" pour traçabilité

4. Si le payload contient des données sensibles
   → JWT signé (JWS, RFC 7515) puis chiffré (JWE, RFC 7516)
   → Algorithmes choisis dans JWA (RFC 7518)
```

---

## 8. Lire une RFC — Guide Pratique

Les RFCs suivent une structure standard. Voici comment naviguer efficacement.

### Structure type d'une RFC

```
1. Introduction          → Contexte et motivation
2. Conventions           → Mots-clés : MUST, SHOULD, MAY (RFC 2119)
3. Terminology           → Définitions des termes clés
4. Main Content          → Le cœur normatif
5. IANA Considerations   → Registres et valeurs enregistrées
6. Security Considerations → Analyse de sécurité (TOUJOURS lire)
7. References            → Normatives (MUST) et informatives
```

### Les mots-clés RFC 2119 (RFC 8174 pour la version Unicode)

| Mot-clé | Signification | Implication |
|---------|---------------|-------------|
| **MUST** / **REQUIRED** | Obligation absolue | Non-conformité = implémentation invalide |
| **MUST NOT** / **SHALL NOT** | Interdiction absolue | Idem |
| **SHOULD** / **RECOMMENDED** | Fortement conseillé | Déviation possible avec justification |
| **SHOULD NOT** / **NOT RECOMMENDED** | Fortement déconseillé | Idem |
| **MAY** / **OPTIONAL** | Facultatif | Implémenteur libre |

**Exemple d'application à RFC 7519 :**

```
Section 4.1.1 : "The "iss" (issuer) claim [...] its value [...] SHOULD be a StringOrURI value."
→ SHOULD = recommandé mais pas obligatoire

Section 7.2 : "If any of the listed steps fail then the token MUST be rejected."
→ MUST = obligatoire pour la conformité
```

### Sections à lire en priorité

```
Pour implémenter : §4 (structure) + §5 (algorithme) + §7 (validation)
Pour la sécurité  : "Security Considerations" — toujours en fin de RFC
Pour les valeurs  : "IANA Considerations" — registres des valeurs valides
Pour comprendre   : §1 (Introduction) + §3 (Terminology)
```

### Accéder aux RFCs

```
RFC officiel  : https://www.rfc-editor.org/rfc/rfcNNNN
Format HTML   : https://www.rfc-editor.org/rfc/rfcNNNN.html
Brouillons    : https://datatracker.ietf.org/doc/draft-*/
Registres IANA: https://www.iana.org/assignments/
```

---

## 9. Écosystème et Outils

### Outils de debug

**jwt.io — décodage et vérification en ligne**
```
https://jwt.io
→ Coller un token pour décoder header + payload
→ Vérification de signature avec secret/clé publique
→ Génération de tokens de test
⚠️ Ne jamais y coller un token de production avec des données réelles
```

**jwt.ms — variante Microsoft Azure**
```
https://jwt.ms
→ Interface plus lisible pour les tokens Azure AD / Entra ID
→ Affiche les claims avec explications
```

**Step CLI — outil ligne de commande**
```bash
# Installer
brew install step

# Inspecter un token
echo "eyJ..." | step crypto jwt inspect --insecure

# Générer une clé et un token
step crypto jwk create pub.json key.json --kty RSA --size 2048
step crypto jwt sign --key key.json --iss "mon-service" --sub "user-42" --exp 1h
```

**jq + base64 — debug rapide en shell**
```bash
# Décoder un JWT sans outil externe
TOKEN="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyXzQyIn0.abc"

# Header
echo $TOKEN | cut -d'.' -f1 | base64 -d 2>/dev/null | jq .

# Payload
echo $TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq .
```

---

### Bibliothèques recommandées par langage

| Langage | Librairie | Notes |
|---------|-----------|-------|
| Node.js | `jose` | ✓ Standard actuel, ESM, Edge Runtime |
| Node.js | `jsonwebtoken` | Mature, synchrone, très répandu |
| Python | `PyJWT` + `cryptography` | ✓ Standard actuel |
| Python | `python-jose` | Plus complet (JWE, JWKS) |
| Java | `nimbus-jose-jwt` | ✓ Le plus complet JVM |
| Java | `jjwt` (0.12+) | Fluent API, bien maintenu |
| Go | `golang-jwt/jwt` | ✓ Fork maintenu de dgrijalva |
| Go | `lestrrat-go/jwx` | Plus complet (JWE, JWKS) |
| Rust | `jsonwebtoken` | ✓ Crate standard |
| PHP | `firebase/php-jwt` | ✓ Très répandu |
| Ruby | `ruby-jwt` | Standard de l'écosystème |
| .NET | `System.IdentityModel.Tokens.Jwt` | Intégré ASP.NET Core |

---

### Frameworks et middlewares

| Framework | Solution JWT native | Notes |
|-----------|--------------------|----|
| Express.js | `express-oauth2-jwt-bearer` | Auth0 officiel |
| Express.js | `passport-jwt` | Intégration Passport |
| Django | `djangorestframework-simplejwt` | Solution complète DRF |
| Django | `dj-rest-auth` | Auth complète + JWT |
| FastAPI | `python-jose` + `python-multipart` | Via dependencies |
| Spring Boot | `spring-security-oauth2-resource-server` | Intégré Spring Security |
| Rails | `devise-jwt` | Intégration Devise |
| Laravel | `tymon/jwt-auth` | Standard Laravel |

---

### Serveurs d'autorisation (IdP) à connaître

| Solution | Type | Points forts |
|----------|------|-------------|
| **Keycloak** | Open source, self-hosted | Complet, RBAC avancé, adapters officiels |
| **Auth0** | SaaS | DX excellent, riche en fonctionnalités |
| **Okta** | SaaS enterprise | Standard enterprise, SCIM, SAML |
| **AWS Cognito** | Cloud AWS | Intégration AWS native, gratuit jusqu'à 50K MAU |
| **Azure AD / Entra ID** | Cloud Azure | Standard enterprise Microsoft |
| **Google Identity** | Cloud GCP | OIDC natif, fiable |
| **Zitadel** | Open source, SaaS | Alternative moderne à Keycloak |
| **Authentik** | Open source | Self-hosted, UI moderne |
| **Dex** | Open source | Fédération d'IdP, Kubernetes-native |

---

### Checklist de conformité aux standards

```
JWT (RFC 7519) :
  ☐ Claims temporels en NumericDate (secondes, pas ms)
  ☐ sub et jti en string (pas entier)
  ☐ aud validé côté serveur
  ☐ exp toujours présent et validé
  ☐ Tolérance clockSkew configurée (30-60s)

JWS (RFC 7515) :
  ☐ Algorithme whitelisté côté serveur (jamais lu depuis token)
  ☐ alg: none rejeté explicitement
  ☐ kid utilisé pour la rotation de clés

JWA (RFC 7518) :
  ☐ RSA1_5 interdit (Bleichenbacher)
  ☐ alg: none interdit
  ☐ Clé RSA ≥ 2048 bits (RS256/PS256)
  ☐ Secret HMAC ≥ 256 bits (HS256)

RFC 6750 :
  ☐ Authorization: Bearer header utilisé (pas query string)
  ☐ WWW-Authenticate header dans les 401
  ☐ Codes d'erreur standardisés (invalid_token, insufficient_scope)

OIDC :
  ☐ nonce validé si flux OIDC
  ☐ Implicit Flow non utilisé (déprécié)
  ☐ PKCE activé pour Authorization Code Flow
```

---

## Récapitulatif des RFCs

| RFC / Spec | Titre | Ce que vous utilisez sans le savoir |
|-----------|-------|-------------------------------------|
| RFC 7519 | JWT | La structure `header.payload.signature` |
| RFC 7515 | JWS | Le processus de signature, le registre des headers |
| RFC 7516 | JWE | Le chiffrement du payload (5 parties) |
| RFC 7517 | JWK | Le format JWKS exposé par votre IdP |
| RFC 7518 | JWA | HS256, RS256, A256GCM dans vos configs |
| RFC 6749 | OAuth 2.0 | Le Authorization Code Flow de votre login |
| RFC 6750 | Bearer | `Authorization: Bearer` dans vos requêtes |
| RFC 8693 | Token Exchange | L'échange de tokens entre microservices |
| OIDC Core | OpenID Connect | L'ID Token, le `.well-known`, le UserInfo |

---

*Cours rédigé dans le cadre d'une série sur les JSON Web Tokens — Étape 7 sur N.*