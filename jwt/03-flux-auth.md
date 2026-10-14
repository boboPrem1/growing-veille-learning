# Maîtriser les JWT en profondeur
### Cours complet — Étape 3 : Flux d'authentification et d'autorisation

> **Prérequis :** Étapes 1 et 2 complétées — anatomie JWT, algorithmes de signature (HMAC/ECDSA/RSA), JWK/JWKS, et distinction JWS vs JWE.  
> **Objectif :** Comprendre les flux réels d'authentification et d'autorisation dans lesquels les JWT s'inscrivent : du login à OAuth2, jusqu'à OpenID Connect.

---

## 3.1 — Flux JWT standard

### Vue d'ensemble

Le flux JWT standard repose sur un cycle en quatre temps : émission, stockage, présentation, vérification. C'est le patron de base sur lequel tous les systèmes plus complexes (OAuth2, OIDC) s'appuient.

```
CLIENT                          AUTH SERVER                   API SERVER
   │                                │                              │
   │── POST /auth/login ───────────►│                              │
   │   { email, password }          │                              │
   │                                │  1. Vérifie les credentials  │
   │                                │  2. Émet access_token (15min)│
   │                                │  3. Émet refresh_token (7j)  │
   │◄── 200 OK ─────────────────────│                              │
   │    { access_token,             │                              │
   │      refresh_token,            │                              │
   │      token_type: "Bearer",     │                              │
   │      expires_in: 900 }         │                              │
   │                                │                              │
   │  [Client stocke les tokens]    │                              │
   │                                │                              │
   │── GET /api/profile ────────────┼─────────────────────────────►│
   │   Authorization: Bearer <AT>   │                              │
   │                                │                         4. Vérifie sig
   │                                │                         5. Vérifie exp
   │                                │                         6. Vérifie aud
   │◄───────────────────────────────┼──────────── 200 OK ──────────│
   │                                │                              │
   │  [access_token expire]         │                              │
   │                                │                              │
   │── POST /auth/refresh ─────────►│                              │
   │   { refresh_token: "..." }     │                              │
   │                                │  7. Vérifie le refresh token │
   │                                │  8. Émet un nouvel AT        │
   │◄── 200 OK { access_token } ────│                              │
```

---

### Étape 1 — Login et émission des tokens

#### La réponse d'authentification

```json
HTTP/1.1 200 OK
Content-Type: application/json

{
  "access_token": "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0yMDI0LTAzIn0...",
  "refresh_token": "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6InJlZi0yMDI0LTAzIn0...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

| Champ | Description |
|---|---|
| `access_token` | Token à courte durée de vie, présenté à chaque requête API |
| `refresh_token` | Token à longue durée de vie, utilisé uniquement pour renouveler l'access token |
| `token_type` | Toujours `"Bearer"` dans les systèmes JWT standards |
| `expires_in` | Durée de validité de l'access token en secondes (ici : 15 min) |

#### Payload type d'un access token

```json
{
  "iss": "https://auth.tenxyte.io",
  "sub": "user_01HV4MXYZ9K3Q7BWRN",
  "aud": "https://api.tenxyte.io",
  "exp": 1711929800,
  "iat": 1711928900,
  "jti": "01HV4N2XZ3K4Q8CWSN9PTDFGE",
  "role": "editor",
  "tenant_id": "tenant_abc123"
}
```

#### Implémentation côté serveur — émission (Python / Django)

```python
import jwt
import uuid
from datetime import datetime, timezone, timedelta
from django.conf import settings

def issue_tokens(user) -> dict:
    now = datetime.now(timezone.utc)
    jti_access = str(uuid.uuid4())
    jti_refresh = str(uuid.uuid4())

    access_payload = {
        "iss": settings.JWT_ISSUER,
        "sub": str(user.id),
        "aud": settings.JWT_AUDIENCE,
        "iat": now,
        "exp": now + timedelta(minutes=15),
        "nbf": now,
        "jti": jti_access,
        "role": user.role,
        "tenant_id": str(user.tenant_id),
    }

    refresh_payload = {
        "iss": settings.JWT_ISSUER,
        "sub": str(user.id),
        "aud": settings.JWT_ISSUER,          # L'audience du refresh est l'auth server lui-même
        "iat": now,
        "exp": now + timedelta(days=7),
        "nbf": now,
        "jti": jti_refresh,
        "type": "refresh",                   # Claim custom pour distinguer les types
    }

    access_token = jwt.encode(
        access_payload,
        settings.JWT_PRIVATE_KEY,
        algorithm="ES256"
    )
    refresh_token = jwt.encode(
        refresh_payload,
        settings.JWT_REFRESH_PRIVATE_KEY,    # Clé séparée pour les refresh tokens
        algorithm="ES256"
    )

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "Bearer",
        "expires_in": 900,
    }
```

> **Bonne pratique :** utiliser des clés séparées pour signer les access tokens et les refresh tokens. Cela limite la surface d'attaque et facilite la rotation indépendante.

---

### Étape 2 — Stockage côté client

Le stockage des tokens est l'une des décisions les plus critiques en termes de sécurité frontend.

#### Tableau comparatif des stratégies de stockage

| Stratégie | XSS | CSRF | Vol physique | Recommandation |
|---|---|---|---|---|
| `localStorage` | ❌ Vulnérable | ✅ Protégé | ❌ Visible | ❌ À éviter |
| `sessionStorage` | ❌ Vulnérable | ✅ Protégé | ✅ Session seule | ⚠️ Acceptable sous conditions |
| Cookie `HttpOnly` | ✅ Protégé | ❌ Vulnérable | Selon `Secure` | ✅ Pour refresh token |
| Cookie `HttpOnly` + `SameSite=Strict` | ✅ Protégé | ✅ Protégé | Selon `Secure` | ✅ Recommandé |
| Mémoire (variable JS) | ✅ Protégé | ✅ Protégé | ✅ Volatil | ✅ Pour access token |

#### Stratégie recommandée : mémoire + cookie HttpOnly

```
Access Token  → Variable JS en mémoire (pas de persistence)
               ✅ Invisible au XSS
               ✅ Perdu à la fermeture de l'onglet (bonne chose)

Refresh Token → Cookie HttpOnly + Secure + SameSite=Strict
               ✅ Inaccessible au JavaScript
               ✅ Envoyé automatiquement par le navigateur
               ✅ SameSite=Strict bloque le CSRF
```

```javascript
// Côté client — stocker l'access token en mémoire uniquement
let accessToken = null;

async function login(email, password) {
    const res = await fetch('/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
        credentials: 'include'  // inclure les cookies (pour le refresh token)
    });

    const data = await res.json();
    accessToken = data.access_token;  // En mémoire, jamais dans localStorage
    scheduleTokenRefresh(data.expires_in);
}

// Rafraîchir l'access token avant expiration
function scheduleTokenRefresh(expiresIn) {
    // Rafraîchir 60 secondes avant l'expiration
    setTimeout(refreshAccessToken, (expiresIn - 60) * 1000);
}

async function refreshAccessToken() {
    const res = await fetch('/auth/refresh', {
        method: 'POST',
        credentials: 'include'  // Le refresh token est dans le cookie HttpOnly
    });

    if (res.ok) {
        const data = await res.json();
        accessToken = data.access_token;
        scheduleTokenRefresh(data.expires_in);
    } else {
        // Refresh token expiré ou révoqué → rediriger vers login
        accessToken = null;
        window.location.href = '/login';
    }
}
```

---

### Étape 3 — Requêtes avec `Authorization: Bearer`

```
GET /api/contracts HTTP/1.1
Host: api.tenxyte.io
Authorization: Bearer eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0yMDI0LTAzIn0...
Accept: application/json
```

Le header `Authorization` avec le schéma `Bearer` est défini par la RFC 6750. L'API extrait le token, le valide, et utilise les claims pour prendre ses décisions d'autorisation.

---

### Étape 4 — Vérification côté serveur

La vérification d'un JWT entrant doit impérativement valider **dans cet ordre** :

```
1. FORMAT          → Le token est-il syntaxiquement valide (3 parties, Base64URL) ?
2. ALGORITHME      → L'alg du header est-il dans la liste blanche autorisée ?
                     (rejeter 'none', rejeter les alg non attendus)
3. SIGNATURE       → La signature est-elle cryptographiquement valide ?
4. EXPIRATION      → exp est-il dans le futur ? (avec tolérance de ±60s)
5. NOT BEFORE      → nbf est-il dans le passé ?
6. ISSUER          → iss correspond-il à l'émetteur attendu ?
7. AUDIENCE        → aud contient-il ce serveur ?
8. TYPE DE TOKEN   → S'il y a un claim 'type', est-ce bien un 'access' token ?
                     (pas un refresh token présenté à l'API)
```

```python
import jwt
from jwt.exceptions import (
    ExpiredSignatureError, InvalidSignatureError,
    InvalidAudienceError, DecodeError
)
from django.conf import settings

ALLOWED_ALGORITHMS = ["ES256"]  # Liste blanche explicite

def verify_access_token(token: str) -> dict:
    try:
        # Récupérer la clé publique (via JWKS ou fichier)
        public_key = get_current_public_key()

        payload = jwt.decode(
            token,
            public_key,
            algorithms=ALLOWED_ALGORITHMS,     # CRITIQUE : ne pas laisser l'header décider
            audience=settings.JWT_AUDIENCE,    # Valider l'audience
            issuer=settings.JWT_ISSUER,        # Valider l'issuer
            options={
                "require": ["exp", "iat", "sub", "jti", "aud", "iss"],
                "verify_exp": True,
                "verify_nbf": True,
                "leeway": 60,                  # Tolérance horloge : 60 secondes
            }
        )

        # Vérification supplémentaire : s'assurer que ce n'est pas un refresh token
        if payload.get("type") == "refresh":
            raise ValueError("Refresh token présenté à l'API — rejeté")

        return payload

    except ExpiredSignatureError:
        raise AuthError("Token expiré", code="TOKEN_EXPIRED")
    except InvalidSignatureError:
        raise AuthError("Signature invalide", code="INVALID_SIGNATURE")
    except InvalidAudienceError:
        raise AuthError("Audience incorrecte", code="INVALID_AUDIENCE")
    except DecodeError as e:
        raise AuthError(f"Token malformé : {e}", code="MALFORMED_TOKEN")
```

---

## 3.2 — Access Token vs Refresh Token

### Pourquoi deux tokens ?

La séparation est une décision d'ingénierie sécuritaire fondée sur le **principe du moindre privilège dans le temps** :

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Un seul token longue durée — problème :                        │
│  Si compromis → l'attaquant a accès pendant 30 jours            │
│  Si révoqué → l'utilisateur légitime doit se re-authentifier   │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Deux tokens — solution :                                       │
│  Access token compromis → dommage limité à 15 minutes           │
│  Refresh token révoquer → seulement l'auth server en est notifié│
│  L'accès à l'API ne nécessite jamais le refresh token           │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Caractéristiques comparées

| Caractéristique | Access Token | Refresh Token |
|---|---|---|
| Durée de vie typique | 5 – 15 minutes | 7 – 30 jours |
| Présenté à | API Server (chaque requête) | Auth Server uniquement |
| Audience | Services métier | Auth Server |
| Stockage recommandé | Mémoire JS | Cookie HttpOnly |
| Contenu | Claims d'autorisation (rôle, tenant…) | Identité minimale (sub, jti) |
| Révocation | Impossible sans blocklist | Possible (suppression en BDD) |
| Vérification | Locale (signature) | Base de données obligatoire |
| Clé de signature | Clé publique distribuée | Clé dédiée, non distribuée |

---

### Refresh Token Rotation

La rotation du refresh token est une pratique de sécurité qui consiste à **émettre un nouveau refresh token à chaque utilisation** et à invalider l'ancien.

```
Flux normal :

  Client ──── RT_1 ────► Auth Server
  Auth Server :
    1. Valide RT_1
    2. Invalide RT_1 (marque comme consommé en BDD)
    3. Émet AT_2 (nouvel access token)
    4. Émet RT_2 (nouveau refresh token)
  Client ◄──── AT_2 + RT_2 ────

  Prochaine rotation :
  Client ──── RT_2 ────► Auth Server
  ... etc.
```

#### Implémentation en base de données

```python
from django.db import models, transaction
import uuid

class RefreshToken(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey('User', on_delete=models.CASCADE)
    jti = models.CharField(max_length=100, unique=True, db_index=True)
    family = models.UUIDField(db_index=True)    # Identifiant de famille (pour reuse detection)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    revoked = models.BooleanField(default=False)
    revoked_at = models.DateTimeField(null=True, blank=True)
    replaced_by_jti = models.CharField(max_length=100, null=True)  # Traçabilité

    class Meta:
        indexes = [
            models.Index(fields=['jti', 'revoked']),
            models.Index(fields=['family']),
        ]

@transaction.atomic
def rotate_refresh_token(old_jti: str) -> tuple[str, str]:
    """Rotation atomique — invalide l'ancien et émet le nouveau."""
    try:
        old_token = RefreshToken.objects.select_for_update().get(
            jti=old_jti,
            revoked=False,
        )
    except RefreshToken.DoesNotExist:
        raise AuthError("Refresh token invalide ou déjà révoqué")

    if old_token.expires_at < now():
        raise AuthError("Refresh token expiré")

    # Émettre le nouveau refresh token
    new_jti = str(uuid.uuid4())
    RefreshToken.objects.create(
        user=old_token.user,
        jti=new_jti,
        family=old_token.family,    # Même famille pour la reuse detection
        expires_at=now() + timedelta(days=7),
    )

    # Invalider l'ancien
    old_token.revoked = True
    old_token.revoked_at = now()
    old_token.replaced_by_jti = new_jti
    old_token.save()

    # Émettre les nouveaux tokens JWT
    access_token = issue_access_token(old_token.user)
    refresh_token = issue_refresh_token(old_token.user, jti=new_jti, family=old_token.family)

    return access_token, refresh_token
```

---

### Détection de réutilisation (Reuse Detection)

La détection de réutilisation est la contre-mesure aux attaques où un refresh token volé est utilisé en parallèle par l'attaquant.

```
Scénario d'attaque sans reuse detection :

  Utilisateur légitime :  RT_1 → AT_2 + RT_2
  Attaquant (a volé RT_1): RT_1 → AT_2' + RT_2'   ✓ Accepté !
  → L'attaquant a un accès valide indéfiniment

Scénario avec reuse detection :

  Utilisateur légitime :  RT_1 → AT_2 + RT_2      ✓ RT_1 invalidé
  Attaquant (a volé RT_1): RT_1 → REJETÉ
    → RT_1 est déjà révoqué → ALERTE : réutilisation détectée !

Réponse au détection de réutilisation — RÉVOQUER TOUTE LA FAMILLE :

  La famille est le groupe de tokens issus d'une même session.
  Si une réutilisation est détectée → TOUS les tokens de cette famille
  sont révoqués → l'utilisateur légitime EST déconnecté.
  → Il doit se re-authentifier avec email + mot de passe.
  → L'attaquant perd tous ses tokens de la même famille.
```

```python
@transaction.atomic
def rotate_with_reuse_detection(old_jti: str) -> tuple[str, str]:
    try:
        old_token = RefreshToken.objects.select_for_update().get(jti=old_jti)
    except RefreshToken.DoesNotExist:
        raise AuthError("Token introuvable", code="INVALID_TOKEN")

    # ⚠️ TOKEN DÉJÀ RÉVOQUÉ → RÉUTILISATION DÉTECTÉE
    if old_token.revoked:
        # Révoquer toute la famille (session compromise)
        RefreshToken.objects.filter(
            family=old_token.family,
            revoked=False
        ).update(revoked=True, revoked_at=now())

        # Logger l'incident de sécurité
        security_logger.critical(
            "REFRESH TOKEN REUSE DETECTED",
            extra={
                "jti": old_jti,
                "family": str(old_token.family),
                "user_id": str(old_token.user_id),
            }
        )

        raise AuthError(
            "Session compromise détectée. Reconnexion requise.",
            code="SESSION_COMPROMISED"
        )

    # Rotation normale...
    return rotate_refresh_token(old_jti)
```

> **Impact UX :** La reuse detection peut provoquer de faux positifs dans des cas légitimes (double-clic, requête réseau retentée, token utilisé simultanément sur deux onglets). Il est recommandé d'ajouter une tolérance de quelques secondes ou une fenêtre de déduplication par `jti`.

---

## 3.3 — OAuth 2.0 et JWT

### OAuth2 : un framework d'autorisation déléguée

OAuth 2.0 (RFC 6749) n'est pas un protocole d'authentification — c'est un **framework d'autorisation** qui permet à un tiers d'accéder à des ressources en votre nom, sans partager votre mot de passe.

```
Acteurs OAuth2 :

  Resource Owner      → L'utilisateur qui possède les données
  Client              → L'application qui veut accéder aux données
  Authorization Server → Émet les tokens (souvent appelé IdP)
  Resource Server     → L'API qui protège les données
```

Le JWT joue le rôle de **Bearer Token** dans OAuth2 — un token opaque ou structuré que le client présente au Resource Server pour accéder aux ressources.

---

### Grant Types (Flux d'obtention de tokens)

#### `client_credentials` — Machine to Machine

Le flux le plus simple : pas d'utilisateur. Une application s'authentifie directement avec son `client_id` et `client_secret`.

```
Client (service backend)            Authorization Server
        │                                   │
        │── POST /oauth/token ─────────────►│
        │   grant_type=client_credentials   │
        │   client_id=svc_invoicing         │
        │   client_secret=...               │
        │   scope=read:contracts            │
        │                                   │
        │◄── { access_token, expires_in } ──│
        │                                   │
        │── GET /api/contracts ────────────►│  Resource Server
            Authorization: Bearer <AT>
```

**Cas d'usage :** communication service à service, tâches planifiées (cron), webhooks sortants, workers.

**Payload typique :**
```json
{
  "iss": "https://auth.tenxyte.io",
  "sub": "svc_invoicing",         // sub = client_id pour M2M
  "aud": "https://api.tenxyte.io",
  "scope": "read:contracts write:invoices",
  "exp": 1711932000,
  "iat": 1711928400,
  "jti": "01HV4N2XZ3K4Q8CWSN9PTDFGE"
}
```

---

#### `authorization_code` — Flux humain (avec PKCE)

C'est le flux standard pour les applications avec utilisateurs. Le code d'autorisation est échangé contre des tokens.

```
Navigateur / App     Auth Server           Resource Server
      │                    │                       │
      │── GET /authorize ─►│                      │
      │   response_type=code                      │
      │   client_id=app_dashboard                 │
      │   redirect_uri=https://app.io/callback    │
      │   scope=openid profile                    │
      │   code_challenge=S256(verifier)  (PKCE)   │
      │   state=random_csrf_token                 │
      │                   │                       │
      │   [Utilisateur se connecte et consent]    │
      │                   │                       │
      │◄── 302 redirect ──│                       │
      │    ?code=AUTH_CODE                        │
      │    &state=random_csrf_token               │
      │                   │                       │
      │── POST /token ────►│                      │
      │   grant_type=authorization_code           │
      │   code=AUTH_CODE                          │
      │   code_verifier=original_verifier (PKCE)  │
      │                   │                       │
      │◄── { access_token, │                      │
      │      refresh_token,│                      │
      │      id_token }   │                       │
      │                   │                       │
      │── GET /api/me ────────────────────────────►
          Authorization: Bearer <access_token>
```

**PKCE — Proof Key for Code Exchange (RFC 7636)**

PKCE protège contre l'interception du `code` par une application malveillante sur le même appareil.

```
1. Génération du verifier (aléatoire, 43-128 chars) :
   code_verifier = base64url(random_bytes(32))

2. Calcul du challenge :
   code_challenge = base64url(sha256(code_verifier))

3. La requête /authorize envoie le challenge.
4. La requête /token envoie le verifier.
5. Le serveur vérifie : sha256(verifier) == challenge
   → Un intercepteur du code sans le verifier ne peut pas obtenir de token.
```

> ✅ **PKCE est obligatoire depuis 2023** pour les clients publics (RFC 9700). Les SPAs et applications mobiles doivent systématiquement utiliser PKCE.

---

#### `implicit` — DÉPRÉCIÉ

```
⚠️  DÉPRÉCIÉ par OAuth 2.0 Security Best Current Practice (RFC 9700, 2023)

L'implicit flow retournait l'access_token directement dans le fragment URL
(#access_token=...), ce qui l'exposait aux :
  - Logs du serveur (Referer header)
  - History du navigateur
  - Scripts tiers injectés
  - Attaques de type token leakage via redirects

REMPLAÇANT : authorization_code + PKCE, qui peut être utilisé par les
SPAs sans secret client.
```

---

#### `device_flow` — Appareils sans navigateur

Flux conçu pour les téléviseurs, terminaux, IoT, CLIs.

```
Appareil (CLI/TV)         Auth Server              Navigateur utilisateur
       │                      │                           │
       │── POST /device ──────►│                           │
       │   client_id=cli_app   │                           │
       │                      │                           │
       │◄── { device_code,    │                           │
       │      user_code,       │                           │
       │      verification_url │                           │
       │      interval: 5 }   │                           │
       │                      │                           │
       │  [Affiche à l'utilisateur :]                      │
       │  "Allez sur https://auth.io/device"               │
       │  "Entrez le code : BFKD-QTRL"                    │
       │                      │◄── POST (user_code) ──────│
       │                      │    [Utilisateur consent]  │
       │                      │                           │
       │── POST /token ───────►│  (polling toutes les 5s) │
       │   grant_type=device   │                           │
       │   device_code=...     │                           │
       │                      │  [Après consentement]     │
       │◄── { access_token } ──│                           │
```

---

### Introspection endpoint vs vérification locale

#### Vérification locale (stateless)

```
API Server reçoit le JWT
    │
    ▼
Vérifie la signature cryptographiquement
Vérifie exp, iss, aud localement
    │
    ▼
Décision → aucun appel réseau requis

✅ Très rapide (sub-milliseconde)
✅ Pas de dépendance à l'auth server pendant la requête
❌ Ne peut pas savoir si le token a été révoqué avant exp
```

#### Introspection endpoint (RFC 7662)

```
API Server reçoit un token opaque (ou JWT)
    │
    ▼
POST /oauth/introspect
Authorization: Basic <api_credentials>
{ "token": "<token_reçu>" }
    │
    ▼
Auth Server répond :
{
  "active": true,
  "sub": "user_1234",
  "scope": "read:contracts",
  "exp": 1711932000,
  "client_id": "app_dashboard"
}

✅ Révocation en temps réel (si active: false → token révoqué)
✅ Fonctionne avec des tokens opaques (non-JWT)
❌ Latence ajoutée (appel HTTP synchrone)
❌ L'auth server est un point de défaillance unique
❌ Scalabilité limitée (charge sur l'auth server)
```

#### Stratégie hybride recommandée

```python
def verify_token_hybrid(token: str, require_fresh: bool = False) -> dict:
    """
    Vérification locale avec introspection conditionnelle.
    
    require_fresh=True → forcer l'introspection (ex: opérations sensibles)
    require_fresh=False → vérification locale suffisante
    """
    # Toujours vérifier localement d'abord
    payload = verify_access_token(token)

    # Pour les opérations critiques (virement, suppression de compte...)
    if require_fresh:
        introspection_result = introspect_token(token)
        if not introspection_result.get("active"):
            raise AuthError("Token révoqué", code="TOKEN_REVOKED")

    return payload

# Usage
payload = verify_token_hybrid(token, require_fresh=False)  # API standard
payload = verify_token_hybrid(token, require_fresh=True)   # Opération critique
```

---

## 3.4 — OpenID Connect (OIDC)

### OIDC : la couche d'identité sur OAuth2

OpenID Connect (OIDC) est une **couche d'identité construite sur OAuth2** (OpenID Connect Core 1.0, 2014). Là où OAuth2 se limite à l'autorisation ("que peut faire cette app ?"), OIDC ajoute l'**authentification** ("qui est cet utilisateur ?").

```
                    OAuth 2.0
         ┌─────────────────────────────┐
         │  Autorisation déléguée      │
         │  access_token               │
         │  refresh_token              │
         └─────────────────────────────┘
                        ▲
                        │  OIDC ajoute
         ┌─────────────────────────────┐
         │  Identité de l'utilisateur  │
         │  id_token (JWT)             │
         │  /userinfo endpoint         │
         │  Discovery endpoint         │
         └─────────────────────────────┘
```

---

### Les trois tokens dans OIDC

| Token | Format | Usage | Audience | Durée |
|---|---|---|---|---|
| `access_token` | JWT ou opaque | Accéder aux ressources (API) | Resource Server | 5–60 min |
| `id_token` | JWT obligatoire | Identifier l'utilisateur (côté client) | Client (app) | 5–60 min |
| `refresh_token` | Opaque ou JWT | Renouveler l'access et l'id token | Auth Server | 7–30 jours |

> **Erreur critique :** Ne jamais envoyer l'`id_token` à une API. Il n'est pas fait pour cela — son audience (`aud`) est le `client_id` de l'application, pas le Resource Server.

---

### Le `id_token` : claims spécifiques OIDC

L'`id_token` est un JWT contenant les claims d'identité de l'utilisateur. Il inclut les registered claims JWT standard plus des claims OIDC spécifiques.

```json
{
  "iss": "https://auth.tenxyte.io",
  "sub": "user_01HV4MXYZ9K3Q7BWRN",
  "aud": "client_dashboard_app",
  "exp": 1711932000,
  "iat": 1711928400,
  "auth_time": 1711928300,
  "nonce": "xK9mP2qRs7vL4nW1",
  "at_hash": "MTIzNDU2Nzg5MDEyMzQ1Ng",
  "azp": "client_dashboard_app",
  "email": "bobo@tenxyte.io",
  "email_verified": true,
  "name": "Bobo",
  "locale": "fr-BJ"
}
```

#### Claims OIDC spécifiques

**`nonce` — Protection contre le rejeu**

```
Génération côté client (avant la requête /authorize) :
  nonce = base64url(random_bytes(16))

La valeur est incluse dans la requête /authorize :
  GET /authorize?...&nonce=xK9mP2qRs7vL4nW1

L'auth server l'intègre dans l'id_token.

Vérification côté client :
  id_token.nonce == nonce_généré_localement ?
    OUI → id_token légitime
    NON → rejeu ou CSRF → rejeter

Sans nonce, un attaquant pourrait :
  1. Obtenir un id_token valide d'une autre session
  2. Le rejouer pour s'authentifier comme cette personne
```

**`at_hash` — Lien entre id_token et access_token**

```
at_hash = base64url(sha256(access_token)[0:16])

Vérification :
  1. Le client reçoit simultanément access_token et id_token
  2. Calcule sha256(access_token), prend les 16 premiers octets
  3. Encode en Base64URL
  4. Compare avec id_token.at_hash

Si at_hash correspond → les deux tokens proviennent du même flux
  (protection contre la substitution d'access token)
```

**`azp` — Authorized Party**

```json
{ "azp": "client_dashboard_app" }
```

Indique le `client_id` auquel le token a été délivré quand l'audience contient plusieurs valeurs. Permet de vérifier que l'app qui présente le token est bien celle pour qui il a été émis (protection contre les attaques de confusion de client).

**`auth_time` — Heure d'authentification**

```json
{ "auth_time": 1711928300 }
```

Timestamp de la dernière authentification interactive (avec mot de passe). Distinct de `iat` (date d'émission du token). Permet d'implémenter des politiques comme "exiger une re-authentification si la dernière auth date de plus de 2 heures".

---

### Différences access_token / id_token / refresh_token en pratique

```
┌──────────────────────────────────────────────────────────────────┐
│  FLUX COMPLET OIDC                                               │
│                                                                  │
│  1. App reçoit : access_token + id_token + refresh_token         │
│                                                                  │
│  2. id_token → utilisé PAR L'APP UNIQUEMENT                     │
│     - Décoder (sans appel réseau) pour obtenir sub, email, name  │
│     - Vérifier nonce, aud == client_id, iss, exp                 │
│     - NE PAS envoyer à l'API                                    │
│     - NE PAS utiliser pour autoriser (c'est le rôle du AT)      │
│                                                                  │
│  3. access_token → envoyé à l'API                               │
│     - Authorization: Bearer <access_token>                       │
│     - L'API le valide et lit les scopes/rôles                   │
│     - Jamais lu par l'application cliente (traité comme opaque)  │
│                                                                  │
│  4. refresh_token → stocké sécuritairement (Cookie HttpOnly)    │
│     - Utilisé uniquement pour appeler /token (auth server)       │
│     - Jamais envoyé à l'API métier                              │
└──────────────────────────────────────────────────────────────────┘
```

---

### Discovery Endpoint — `/.well-known/openid-configuration`

Le Discovery endpoint (RFC 8414 / OpenID Connect Discovery 1.0) est une URL standardisée qui expose la **configuration complète** d'un Authorization Server sous forme de document JSON.

```
GET https://auth.tenxyte.io/.well-known/openid-configuration

HTTP/1.1 200 OK
Content-Type: application/json
```

```json
{
  "issuer": "https://auth.tenxyte.io",
  "authorization_endpoint": "https://auth.tenxyte.io/oauth/authorize",
  "token_endpoint": "https://auth.tenxyte.io/oauth/token",
  "userinfo_endpoint": "https://auth.tenxyte.io/userinfo",
  "jwks_uri": "https://auth.tenxyte.io/.well-known/jwks.json",
  "introspection_endpoint": "https://auth.tenxyte.io/oauth/introspect",
  "revocation_endpoint": "https://auth.tenxyte.io/oauth/revoke",
  "end_session_endpoint": "https://auth.tenxyte.io/logout",
  "device_authorization_endpoint": "https://auth.tenxyte.io/oauth/device",

  "response_types_supported": ["code", "token", "id_token", "code token"],
  "grant_types_supported": [
    "authorization_code",
    "client_credentials",
    "refresh_token",
    "urn:ietf:params:oauth:grant-type:device_code"
  ],
  "subject_types_supported": ["public", "pairwise"],

  "id_token_signing_alg_values_supported": ["ES256", "RS256"],
  "token_endpoint_auth_methods_supported": [
    "client_secret_basic",
    "client_secret_post",
    "private_key_jwt"
  ],

  "scopes_supported": ["openid", "profile", "email", "offline_access"],
  "claims_supported": [
    "sub", "iss", "aud", "exp", "iat",
    "name", "email", "email_verified",
    "locale", "picture", "nonce", "at_hash", "azp"
  ],

  "code_challenge_methods_supported": ["S256"],
  "require_pkce": true
}
```

#### Comment utiliser le discovery endpoint

```python
import httpx
from functools import lru_cache

@lru_cache(maxsize=1)
def get_oidc_config(issuer: str) -> dict:
    """
    Découverte automatique de la configuration OIDC.
    Résultat mis en cache (TTL implicite de la session).
    """
    discovery_url = f"{issuer.rstrip('/')}/.well-known/openid-configuration"
    response = httpx.get(discovery_url, timeout=5)
    response.raise_for_status()
    config = response.json()

    # Vérification minimale de sécurité
    if config.get("issuer") != issuer:
        raise SecurityError(
            f"Issuer mismatch: attendu {issuer}, obtenu {config['issuer']}"
        )

    return config

# Usage dans un client OIDC
config = get_oidc_config("https://auth.tenxyte.io")

auth_url = config["authorization_endpoint"]
token_url = config["token_endpoint"]
jwks_uri = config["jwks_uri"]
```

#### Ce que les clients OIDC font automatiquement

Les bibliothèques OIDC de référence (python-oauth2, node-openid-client, Auth.js…) utilisent le discovery endpoint pour :

1. **Construire l'URL d'autorisation** sans configuration manuelle des endpoints.
2. **Récupérer les clés publiques** via `jwks_uri` pour valider les tokens.
3. **Vérifier les capacités** de l'auth server (PKCE supporté ? quels alg ?).
4. **Actualiser la configuration** si elle change (rotation d'endpoints).

---

### Validation complète d'un `id_token` (spec OIDC)

La spécification OIDC Core définit une séquence de validation obligatoire plus stricte que celle d'un JWT générique :

```
1. Vérifier que le token est un JWT bien formé
2. Vérifier alg contre id_token_signing_alg_values_supported du discovery
3. Vérifier la signature avec la clé publique depuis jwks_uri
4. Vérifier iss == issuer du discovery
5. Vérifier que aud contient le client_id de l'application
6. Si aud est multi-valeurs : vérifier que azp == client_id
7. Vérifier exp > maintenant
8. Vérifier iat (rejeter si trop vieux, ex : > 1 heure)
9. Si nonce présent dans la requête /authorize :
   vérifier que nonce dans l'id_token == nonce envoyé
10. Vérifier at_hash si un access_token est fourni simultanément
11. Si auth_time requis : vérifier que auth_time est suffisamment récent
```

```python
import jwt
import hashlib
import base64

def validate_id_token(
    id_token: str,
    access_token: str | None = None,
    expected_nonce: str | None = None,
    client_id: str = settings.OIDC_CLIENT_ID,
) -> dict:
    config = get_oidc_config(settings.OIDC_ISSUER)
    keys = get_jwks(config["jwks_uri"])

    # Décodage et validation du JWT (signature, exp, iss, aud)
    payload = jwt.decode(
        id_token,
        keys,
        algorithms=config["id_token_signing_alg_values_supported"],
        audience=client_id,
        issuer=config["issuer"],
        options={
            "require": ["sub", "iat", "exp", "iss", "aud"],
            "verify_exp": True,
            "leeway": 60,
        }
    )

    # Vérification azp si aud est multi-valeur
    if isinstance(payload.get("aud"), list):
        if payload.get("azp") != client_id:
            raise OIDCError("azp mismatch — possible token confusion attack")

    # Vérification nonce
    if expected_nonce:
        if payload.get("nonce") != expected_nonce:
            raise OIDCError("nonce mismatch — possible replay attack")
    elif "nonce" not in payload:
        # Si on a envoyé un nonce mais qu'il est absent du token
        raise OIDCError("nonce absent du id_token")

    # Vérification at_hash (si access_token fourni)
    if access_token and "at_hash" in payload:
        at_bytes = access_token.encode("ascii")
        digest = hashlib.sha256(at_bytes).digest()
        at_hash = base64.urlsafe_b64encode(digest[:16]).rstrip(b"=").decode()
        if at_hash != payload["at_hash"]:
            raise OIDCError("at_hash invalide — possible substitution d'access token")

    return payload
```

---

## Récapitulatif de l'Étape 3

```
┌────────────────────────────────────────────────────────────────────┐
│  FLUX JWT STANDARD                                                 │
│  Login → AT (mémoire) + RT (cookie HttpOnly) → Bearer → Verify    │
│  Vérification : format → alg → sig → exp → iss → aud → type       │
├────────────────────────────────────────────────────────────────────┤
│  ACCESS vs REFRESH TOKEN                                           │
│  AT : court (15min), présenté à l'API, vérification locale        │
│  RT : long (7j), présenté uniquement à l'auth server, en BDD      │
│  Rotation → invalider l'ancien à chaque usage                     │
│  Reuse detection → révoquer toute la famille si RT réutilisé      │
├────────────────────────────────────────────────────────────────────┤
│  OAUTH2                                                            │
│  client_credentials → M2M, pas d'utilisateur                     │
│  authorization_code + PKCE → flux humain standard (SPA, mobile)   │
│  device_flow → CLI, TV, IoT                                       │
│  implicit → DÉPRÉCIÉ, ne pas utiliser                             │
│  Introspection → révocation temps réel, coût réseau               │
│  Vérification locale → rapide, pas de révocation                  │
├────────────────────────────────────────────────────────────────────┤
│  OIDC                                                              │
│  id_token → pour l'APP (identité), jamais envoyé à l'API          │
│  access_token → pour l'API (autorisation)                         │
│  nonce → anti-rejeu, obligatoire                                  │
│  at_hash → lie id_token et access_token                           │
│  azp → anti-confusion de client (multi-audience)                  │
│  /.well-known/openid-configuration → auto-discovery de l'IdP      │
└────────────────────────────────────────────────────────────────────┘
```

### Points de contrôle — vérifiez votre compréhension

1. Pourquoi le refresh token ne doit-il **jamais** être envoyé à une API métier ?
2. Quelle est la différence entre la rotation du refresh token et la détection de réutilisation ? L'une suffit-elle sans l'autre ?
3. Une SPA veut implémenter OAuth2. Quel grant type utiliser, et pourquoi PKCE est-il obligatoire ?
4. Votre API reçoit un `id_token` OIDC dans le header `Authorization`. Quelle erreur architecturale cela révèle-t-il ?
5. À quoi sert `at_hash` dans un `id_token` ? Quelle attaque empêche-t-il ?
6. Un utilisateur se connecte sur deux onglets simultanément. La reuse detection peut-elle générer un faux positif ? Comment l'atténuer ?
7. Quelle est la différence entre `iat` et `auth_time` dans un `id_token` OIDC ?
8. Pourquoi l'introspection endpoint est-il nécessaire pour certains scénarios malgré son coût réseau ?

---

*Cours rédigé pour le programme **Maîtriser les JWT en profondeur** — Étape 3 : Flux d'authentification et d'autorisation.*  
*Références : RFC 6749 (OAuth2), RFC 6750 (Bearer Tokens), RFC 7662 (Introspection), RFC 7636 (PKCE), RFC 9700 (OAuth2 Security BCP), OpenID Connect Core 1.0, OpenID Connect Discovery 1.0.*