# Maîtriser les JWT en profondeur
### Cours complet — Étape 2 : Cryptographie appliquée aux JWT

> **Prérequis :** Étape 1 complétée — vous maîtrisez l'anatomie d'un JWT (Header, Payload, Signature) et la distinction Base64URL vs chiffrement.  
> **Objectif :** Comprendre en profondeur les algorithmes cryptographiques utilisés dans les JWT, les formats de clés, et la frontière entre signature et chiffrement.

---

## 2.1 — Algorithmes symétriques (HMAC)

### Principe général

HMAC (**Hash-based Message Authentication Code**) est une construction cryptographique qui combine une **fonction de hachage** (SHA-256, SHA-384, SHA-512) avec une **clé secrète partagée** pour produire un code d'authentification.

La propriété fondamentale : sans la clé, il est **computationnellement impossible** de produire un HMAC valide ou de distinguer un HMAC légitime d'une valeur aléatoire.

```
HMAC(K, m) = H((K ⊕ opad) ∥ H((K ⊕ ipad) ∥ m))

Où :
  K    = clé secrète
  m    = message (signing_input du JWT)
  H    = fonction de hachage (SHA-256…)
  opad = 0x5c5c5c... (outer padding)
  ipad = 0x3636363... (inner padding)
  ∥    = concaténation
  ⊕    = XOR
```

En pratique, vous n'avez jamais à implémenter cette formule — votre bibliothèque JWT le fait. Ce qui compte, c'est de comprendre ce qu'elle garantit.

---

### `HS256`, `HS384`, `HS512`

| Algorithme | Fonction de hachage | Taille de signature | Longueur clé minimale |
|---|---|---|---|
| `HS256` | SHA-256 | 256 bits (32 octets) | 256 bits (32 octets) |
| `HS384` | SHA-384 | 384 bits (48 octets) | 384 bits (48 octets) |
| `HS512` | SHA-512 | 512 bits (64 octets) | 512 bits (64 octets) |

> **Règle pratique :** La longueur de la clé doit être **au moins égale** à la taille de sortie de la fonction de hachage. Une clé HS256 de 16 octets est sous-dimensionnée et affaiblit la sécurité.

#### Génération d'une clé HS256 correcte

```bash
# Via OpenSSL (recommandé en production)
openssl rand -hex 32
# → a3f8c1d9e2b47506f1a8c3d2e9b47506f1a8c3d2e9b47506f1a8c3d2e9b47506

# Via Python
python3 -c "import secrets; print(secrets.token_hex(32))"

# Via Node.js
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

```python
# ❌ Clés faibles — exemples à NE PAS utiliser
SECRET = "secret"              # 6 octets — cassable en secondes
SECRET = "mysupersecretkey"    # 16 octets — insuffisant pour HS256
SECRET = "password123"         # donnée prévisible

# ✅ Clé correcte
import os
SECRET = os.environ["JWT_SECRET_KEY"]  # 32+ octets aléatoires, injectés en env
```

---

### Architecture HMAC : une seule clé, deux rôles

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   AUTH SERVER                         API SERVER           │
│   ┌──────────────┐                    ┌──────────────┐     │
│   │              │                    │              │     │
│   │  SECRET_KEY  │◄──── PARTAGÉE ────►│  SECRET_KEY  │     │
│   │              │                    │              │     │
│   │  Signe JWT   │                    │  Vérifie JWT │     │
│   └──────────────┘                    └──────────────┘     │
│                                                             │
│   ⚠️  Les deux parties peuvent ÉMETTRE des tokens valides  │
└─────────────────────────────────────────────────────────────┘
```

C'est la **limite architecturale fondamentale** d'HMAC : quiconque possède la clé peut non seulement **vérifier** les tokens, mais aussi en **émettre de nouveaux**. Cette propriété est acceptable dans certains contextes, dangereuse dans d'autres.

---

### Cas d'usage appropriés

#### ✅ Microservices internes (même trust boundary)

```
┌──────────────────────────────────────────────────────┐
│  Zone de confiance interne (réseau privé / VPC)      │
│                                                      │
│  Auth Service ──JWT──► Service Commandes             │
│       │                                              │
│   SECRET partagé      SECRET partagé                 │
│       │                     │                        │
│       └──── même secret ────┘                        │
│                                                      │
│  ✅ Acceptable car tous les services sont            │
│     sous le même contrôle opérationnel               │
└──────────────────────────────────────────────────────┘
```

#### ✅ API mono-domaine (un seul backend)

Application mobile ↔ Backend unique : le serveur est à la fois émetteur et vérificateur. Partager le secret avec soi-même est trivial.

#### ❌ Cas inappropriés pour HMAC

```
Auth Server ──SECRET──► Partenaire externe
                         (peut émettre des tokens en votre nom)

Auth Server ──SECRET──► 50 microservices distincts
                         (surface d'attaque x50 si l'un est compromis)

Auth Server ──SECRET──► Service tiers (SDK client)
                         (le secret peut être extrait)
```

---

### Risques et contre-mesures

| Risque | Description | Contre-mesure |
|---|---|---|
| **Secret faible** | Brute-force si < 256 bits | Générer aléatoirement via CSPRNG |
| **Secret exposé** | Dans le code, les logs, le dépôt Git | Variables d'environnement + secret manager |
| **Pas de rotation** | Un secret compromis l'est indéfiniment | Rotation planifiée avec période de chevauchement |
| **Partage étendu** | Chaque destinataire peut émettre | Réduire le nombre de parties partageant le secret |
| **Attaque timing** | Comparaison byte-à-byte exploitable | Toujours utiliser `hmac.compare_digest()` |

```python
# ❌ Comparaison naïve — vulnérable aux timing attacks
if token_signature == expected_signature:
    ...

# ✅ Comparaison en temps constant
import hmac
if hmac.compare_digest(token_signature, expected_signature):
    ...
```

---

## 2.2 — Algorithmes asymétriques (RSA / EC)

### Principe : paire de clés

La cryptographie asymétrique repose sur une **paire de clés mathématiquement liées** :

- **Clé privée** : secrète, connue uniquement de l'émetteur. Sert à **signer**.
- **Clé publique** : partageable librement. Sert à **vérifier**.

La relation est à sens unique : connaître la clé publique ne permet pas de retrouver la clé privée (propriété de trapdoor function).

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   AUTH SERVER              N'IMPORTE QUEL SERVICE          │
│   ┌──────────────┐         ┌──────────────┐                │
│   │ CLEF PRIVÉE  │         │ CLEF PUBLIQUE│                │
│   │ (secrète)    │         │ (publique)   │                │
│   │              │         │              │                │
│   │  Signe JWT   │         │  Vérifie JWT │                │
│   └──────────────┘         └──────────────┘                │
│         │                         ▲                        │
│         └──────── JWT ────────────┘  (via le client)       │
│                                                             │
│   ✅ Seul l'Auth Server peut ÉMETTRE des tokens valides    │
└─────────────────────────────────────────────────────────────┘
```

---

### RSA — `RS256`, `RS384`, `RS512`

RSA (**Rivest–Shamir–Adleman**, 1977) est basé sur la difficulté de factoriser le produit de deux grands nombres premiers.

#### Mécanisme de signature RSA-PKCS#1 v1.5

```
1. Calculer le hash du signing_input :
   h = SHA-256(base64url(header) + "." + base64url(payload))

2. Encoder le hash avec le schéma PKCS#1 v1.5 :
   EM = 0x00 0x01 [padding 0xFF...] 0x00 [DigestInfo(h)]

3. Signer (déchiffrer avec la clé privée) :
   signature = EM^d mod n
   (où d = exposant privé, n = module RSA)

4. Vérifier (chiffrer avec la clé publique) :
   EM' = signature^e mod n
   (où e = exposant public)
   Vérifier que EM' == EM
```

#### Tailles de clé RSA recommandées

| Taille | Sécurité | Recommandation |
|---|---|---|
| 1024 bits | ❌ Cassée | À proscrire absolument |
| 2048 bits | ~112 bits de sécurité | Minimum acceptable (horizon 2030) |
| 3072 bits | ~128 bits de sécurité | Recommandé pour nouvelles implémentations |
| 4096 bits | ~140 bits de sécurité | Long terme, mais plus lent |

```bash
# Générer une paire de clés RSA 4096 bits
openssl genrsa -out private_key.pem 4096
openssl rsa -in private_key.pem -pubout -out public_key.pem

# Inspecter la clé
openssl rsa -in private_key.pem -text -noout
```

#### Inconvénients de RSA

- **Clés volumineuses** : une clé RSA 4096 bits fait ~1700 caractères en PEM.
- **Opérations lentes** : la signature RSA est coûteuse en CPU.
- **PKCS#1 v1.5 a des vulnérabilités** (attaque de Bleichenbacher, 1998) — préférer RSA-PSS.

---

### RSA-PSS — `PS256`, `PS384`, `PS512`

RSA-PSS (**Probabilistic Signature Scheme**) est une version modernisée de RSA qui corrige les faiblesses de PKCS#1 v1.5.

| Propriété | RS256 (PKCS#1 v1.5) | PS256 (PSS) |
|---|---|---|
| Déterministe | ✅ (même input → même signature) | ❌ (aléatoire, plus sûr) |
| Résistant Bleichenbacher | ❌ | ✅ |
| Recommandé NIST | Acceptable | ✅ Préféré |
| Support bibliothèques | Universel | Bon (vérifier avant usage) |

> ✅ Pour les nouvelles implémentations RSA, **préférer `PS256`** à `RS256` si votre stack le supporte.

```bash
# Générer une paire de clés RSA-PSS 2048 bits
openssl genpkey -algorithm RSA-PSS -pkeyopt rsa_keygen_bits:2048 -out ps256_private.pem
openssl pkey -in ps256_private.pem -pubout -out ps256_public.pem

# Signer un message avec RSA-PSS (SHA-256)
echo -n "header.payload" | openssl dgst -sha256 -sigopt rsa_padding_mode:pss -sign ps256_private.pem -out signature.bin

# Vérifier la signature
echo -n "header.payload" | openssl dgst -sha256 -sigopt rsa_padding_mode:pss -verify ps256_public.pem -signature signature.bin
```

```bash
bobop@DESKTOP-4GAIAB2 MINGW64 ~/Documents/own/growing veille learning/jwt
$ openssl genpkey -algorithm RSA-PSS -pkeyopt rsa_keygen_bits:2048 -out ps256_private_key_first.pem
.......+..........+........+.+..+.........+.+..+.+......+.....+.+...+..+.........+...+......+.+...+..
+.........+....+..+......+.......+++++++++++++++++++++++++++++++++++++++*.........+.+...+..+.......+..
+......+....+.....+....+..+...+.......+.....+.......+......+......+..............+.......+.....+...+....+..
+......+...+................+...+......+.....+.........+.......+........+......+...............+.+.....+.+..
+...+....+...+..+++++++++++++++++++++++++++++++++++++++*............+...+...................+...
+..................+..+.+...............+.....+....+........+.......+..................+..+............
+......+...+.......+..++++++
..+.................+++++++++++++++++++++++++++++++++++++++*.+.......+.....+...+.
+++++++++++++++++++++++++++++++++++++++*...........+.+.....+.........+...+...+......+..........+...........
+...+.........+...............+.+............+..+...+.........+.+...+..............+.......++++++

bobop@DESKTOP-4GAIAB2 MINGW64 ~/Documents/own/growing veille learning/jwt
$ openssl pkey -in ps256_private_key_first.pem -pubout -out ps256_public_key_first.pem             
bobop@DESKTOP-4GAIAB2 MINGW64 ~/Documents/own/growing veille learning/jwt
$ echo -n "header.payload" | openssl dgst -sha256 -sigopt rsa_padding_mode:pss -sign ps256_private_key_first.pem -out signature.bin

bobop@DESKTOP-4GAIAB2 MINGW64 ~/Documents/own/growing veille learning/jwt
$ echo -n "header.payload" | openssl dgst -sha256 -sigopt rsa_padding_mode:pss -verify ps256_public_key_first.pem -signature signature.bin
Verified OK

bobop@DESKTOP-4GAIAB2 MINGW64 ~/Documents/own/growing veille learning/jwt

```

### ECDSA — `ES256`, `ES384`, `ES512`

ECDSA (**Elliptic Curve Digital Signature Algorithm**) repose sur les propriétés des courbes elliptiques sur des corps finis. La sécurité est basée sur la difficulté du problème du logarithme discret elliptique (ECDLP).

#### Courbes utilisées

| Algorithme | Courbe | Taille clé | Sécurité équivalente RSA |
|---|---|---|---|
| `ES256` | P-256 (secp256r1) | 256 bits | RSA-3072 |
| `ES384` | P-384 (secp384r1) | 384 bits | RSA-7680 |
| `ES512` | P-521 (secp521r1) | 521 bits | RSA-15360 |

#### Avantages d'ECDSA vs RSA

```
Taille des clés (PEM encodé) :

  RSA-2048 private key  :  ~1700 caractères
  EC P-256 private key  :   ~230 caractères   ← 7x plus compact

Vitesse de signature (benchmark approximatif) :

  RS256 (RSA-2048)  : ~1ms par signature
  ES256 (P-256)     : ~0.1ms par signature   ← 10x plus rapide

Taille de la signature dans le JWT :

  RS256  : 342 caractères (Base64URL)
  ES256  : 86 caractères (Base64URL)          ← 4x plus compact
```

#### Génération d'une paire ECDSA P-256

```bash
# Générer la clé privée EC P-256
openssl ecparam -name prime256v1 -genkey -noout -out ec_private.pem

# Extraire la clé publique
openssl ec -in ec_private.pem -pubout -out ec_public.pem

# Inspecter
openssl ec -in ec_private.pem -text -noout
```

```python
# Python — génération avec cryptography
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization

private_key = ec.generate_private_key(ec.SECP256R1())
public_key = private_key.public_key()

# Sérialiser en PEM
private_pem = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption()
)
public_pem = public_key.public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo
)
```

#### Attention : ECDSA et le nonce `k`

ECDSA utilise un nonce aléatoire `k` à chaque signature. Si `k` est réutilisé pour deux signatures avec la même clé privée, **la clé privée entière peut être reconstituée** — c'est la vulnérabilité qui a compromis la PS3 en 2010 (Sony utilisait un `k` statique).

> ✅ Vos bibliothèques JWT correctes génèrent `k` de façon cryptographiquement sécurisée. Ne jamais implémenter ECDSA manuellement.

---

### Tableau comparatif complet

| Critère | HS256 | RS256 | PS256 | ES256 |
|---|---|---|---|---|
| Type | Symétrique | Asymétrique | Asymétrique | Asymétrique |
| Clé de vérification partageable | ❌ | ✅ | ✅ | ✅ |
| Taille clé | 256 bits | 2048+ bits | 2048+ bits | 256 bits |
| Taille signature | 32 octets | 256 octets | 256 octets | ~64 octets |
| Vitesse signature | ⚡⚡⚡ | ⚡ | ⚡ | ⚡⚡⚡ |
| Sécurité post-NIST | ✅ | ✅ (PS256 préféré) | ✅ | ✅ |
| Résistance timing attack | Via compare_digest | Intrinsèque | Intrinsèque | Intrinsèque |
| Recommandé pour OAuth2/OIDC | ❌ | ✅ | ✅ | ✅ |
| Standard dans l'industrie | Courant | Très courant | Croissant | Croissant |

> **Recommandation 2026 :** `ES256` pour les nouvelles implémentations (compact, rapide, sécurisé). `RS256` pour la compatibilité maximale. `HS256` uniquement dans les systèmes mono-acteur ou microservices internes.

---

### Cas d'usage OAuth2 / OIDC / SSO

```
┌───────────────────────────────────────────────────────────────┐
│  Système SSO d'entreprise avec ES256                          │
│                                                               │
│  ┌──────────────────┐                                         │
│  │   Identity       │  Clé privée EC P-256                   │
│  │   Provider (IdP) │  → Signe tous les tokens               │
│  └──────────────────┘                                         │
│          │                                                    │
│          │  Publie clé publique sur                           │
│          │  /.well-known/jwks.json                            │
│          │                                                    │
│          ▼                                                    │
│  ┌────────────────────────────────────────────┐              │
│  │  Service A │  Service B │  Service C │ ... │              │
│  │  Vérifient avec la clé publique            │              │
│  │  Aucun ne peut émettre de tokens           │              │
│  └────────────────────────────────────────────┘              │
└───────────────────────────────────────────────────────────────┘
```

---

## 2.3 — JWK et JWKS

### JSON Web Key (RFC 7517)

Un **JWK** (JSON Web Key) est une représentation JSON standardisée d'une clé cryptographique. Au lieu de manipuler des fichiers PEM opaques, le format JWK rend les clés **lisibles, transportables et auto-descriptives**.

```json
{
  "kty": "EC",
  "crv": "P-256",
  "x": "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU",
  "y": "x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0",
  "use": "sig",
  "alg": "ES256",
  "kid": "key-2026-03"
}
```

#### Champs d'un JWK

| Champ | Signification | Valeurs courantes |
|---|---|---|
| `kty` | Key Type — type de clé | `"RSA"`, `"EC"`, `"oct"` (symétrique) |
| `use` | Intended use | `"sig"` (signature), `"enc"` (chiffrement) |
| `alg` | Algorithme cible | `"RS256"`, `"ES256"`, `"HS256"`… |
| `kid` | Key ID | Identifiant opaque libre |
| `crv` | Courbe EC | `"P-256"`, `"P-384"`, `"P-521"` |
| `x`, `y` | Coordonnées EC (clé publique) | Base64URL des coordonnées |
| `n`, `e` | Modulus + exposant RSA (clé publique) | Base64URL |
| `d` | Composante secrète (clé privée) | Base64URL — **ne jamais exposer** |

#### Clé RSA en format JWK (publique)

```json
{
  "kty": "RSA",
  "use": "sig",
  "alg": "RS256",
  "kid": "rsa-key-2026",
  "n": "pjdss8ZaDfEH6K6U7GeW2nxDqR4IP049fk1fK0lndimbMMVBdPv_hSpm8T8EtBDxrUdi1OHZfMhUixGyvJ2gEoPQ1Zp4uCFzLmIBWBPHFfLacrh8vYLxEqE5-lRr0Cz3UQ==",
  "e": "AQAB"
}
```

> `"n"` est le modulus RSA, `"e"` est l'exposant public (généralement 65537 → `"AQAB"` en Base64URL).

---

### JWKS — JSON Web Key Set

Un **JWKS** (JSON Web Key Set) est un ensemble de JWK regroupés dans un objet JSON unique. C'est le format utilisé pour publier les clés publiques d'un serveur d'authentification.

```json
{
  "keys": [
    {
      "kty": "EC",
      "crv": "P-256",
      "use": "sig",
      "alg": "ES256",
      "kid": "key-2026-03",
      "x": "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU",
      "y": "x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"
    },
    {
      "kty": "RSA",
      "use": "sig",
      "alg": "RS256",
      "kid": "rsa-key-legacy",
      "n": "pjdss8ZaDfEH6...",
      "e": "AQAB"
    }
  ]
}
```

Plusieurs clés dans un JWKS permettent de **servir simultanément plusieurs algorithmes** ou de **maintenir des clés en cours de dépréciation**.

---

### Endpoint `/.well-known/jwks.json`

C'est l'URL standard (RFC 8414) où un Authorization Server publie son JWKS. Les vérificateurs peuvent le requêter pour obtenir les clés publiques sans configuration manuelle.

```
GET https://auth.tenxyte.io/.well-known/jwks.json

HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: public, max-age=3600

{
  "keys": [...]
}
```

#### Flux de vérification avec JWKS

```
Vérificateur (API Server)
        │
        │  1. Reçoit le JWT
        │     Header: { "alg": "ES256", "kid": "key-2026-03" }
        │
        │  2. Lit le kid du header
        │
        │  3. Cherche dans le cache local → clé trouvée ?
        │     OUI → utiliser la clé en cache
        │     NON → requêter /.well-known/jwks.json
        │
        │  4. Filtre les clés par kid = "key-2026-03"
        │
        │  5. Vérifie la signature avec la clé publique EC
        │
        │  6. Valide iss, aud, exp, nbf
        │
        └─► Accès accordé ou refusé
```

#### Caching du JWKS

Le JWKS ne doit pas être re-téléchargé à chaque requête — cela serait catastrophique pour les performances. La stratégie recommandée :

```python
import time
import httpx
from functools import lru_cache

JWKS_URL = "https://auth.tenxyte.io/.well-known/jwks.json"
CACHE_TTL = 3600  # 1 heure

_jwks_cache = {"keys": None, "fetched_at": 0}

def get_jwks():
    now = time.time()
    if _jwks_cache["keys"] and (now - _jwks_cache["fetched_at"]) < CACHE_TTL:
        return _jwks_cache["keys"]
    
    response = httpx.get(JWKS_URL, timeout=5)
    response.raise_for_status()
    _jwks_cache["keys"] = response.json()["keys"]
    _jwks_cache["fetched_at"] = now
    return _jwks_cache["keys"]

def get_key_by_kid(kid: str):
    keys = get_jwks()
    matching = [k for k in keys if k.get("kid") == kid]
    
    if not matching:
        # Invalider le cache et retenter une fois
        _jwks_cache["fetched_at"] = 0
        keys = get_jwks()
        matching = [k for k in keys if k.get("kid") == kid]
    
    if not matching:
        raise ValueError(f"Clé introuvable pour kid={kid}")
    
    return matching[0]
```

> ⚠️ **Vulnérabilité SSRF :** Ne jamais utiliser un `jku` (JWK Set URL) provenant du header JWT lui-même pour télécharger les clés. Un attaquant pourrait pointer vers un serveur malveillant. Toujours hardcoder ou configurer l'URL du JWKS côté serveur.

---

### Rotation de clés avec `kid`

La rotation de clés est le processus de remplacement périodique des clés cryptographiques pour limiter l'exposition en cas de compromission.

#### Procédure de rotation sans interruption de service

```
Phase 1 — Préparation (J-7)
  ├─ Générer la nouvelle paire de clés (kid: "key-2026-06")
  └─ Ajouter la nouvelle clé publique au JWKS
     → les deux clés sont maintenant dans le JWKS

Phase 2 — Transition (J0)
  ├─ L'Auth Server commence à signer avec "key-2026-06"
  └─ Les anciens tokens signés avec "key-2026-03" sont encore valides
     → les vérificateurs trouvent "key-2026-03" dans le JWKS

Phase 3 — Dépréciation (J+30, après exp max des anciens tokens)
  └─ Retirer "key-2026-03" du JWKS
     → tous les tokens actifs sont maintenant sous "key-2026-06"

JWKS à chaque phase :

Phase 1 et 2 :          Phase 3 :
{ "keys": [             { "keys": [
    { kid: "key-2026-03" },     { kid: "key-2026-06" }
    { kid: "key-2026-06" }  ]}
]}
```

#### Fréquence de rotation recommandée

| Contexte | Fréquence |
|---|---|
| Production standard | 90 jours |
| Haute sécurité (finance, santé) | 30 jours |
| Après suspicion de compromission | Immédiate |
| Clés de signature OIDC | Selon politique IdP (souvent 24h à 30j) |

---

### Convertir entre PEM et JWK

```python
# Python — cryptography + jwcrypto
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization
import json, base64

def ec_public_key_to_jwk(public_key, kid: str) -> dict:
    pub_numbers = public_key.public_key().public_numbers()
    
    def int_to_base64url(n: int, length: int) -> str:
        return base64.urlsafe_b64encode(
            n.to_bytes(length, 'big')
        ).rstrip(b'=').decode()
    
    return {
        "kty": "EC",
        "crv": "P-256",
        "use": "sig",
        "alg": "ES256",
        "kid": kid,
        "x": int_to_base64url(pub_numbers.x, 32),
        "y": int_to_base64url(pub_numbers.y, 32),
    }
```

---

## 2.4 — Algorithmes de chiffrement : JWE

### Distinction JWS vs JWE

C'est la frontière que beaucoup ignorent et qui mène aux vulnérabilités les plus graves.

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  JWS — JSON Web Signature (RFC 7515)                          │
│  "JWT standard"                                               │
│                                                                │
│  eyJhbGciOiJFUzI1NiJ9                                         │
│  .eyJzdWIiOiIxMjM0IiwibmFtZSI6IkJvYm8ifQ   ← LISIBLE        │
│  .signature                                                    │
│                                                                │
│  ✅ Intégrité + Authenticité                                  │
│  ❌ Confidentialité (payload visible)                          │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  JWE — JSON Web Encryption (RFC 7516)                         │
│  "JWT chiffré"                                                 │
│                                                                │
│  eyJhbGciOiJSU0EtT0FFUCIsImVuYyI6IkEyNTZHQ00ifQ             │
│  .OKOawDo13gRp2ojaHV7LFpZcgV7T6DVZKTyKOMTYUmKoTCVJRgck...  │
│  .48V1_ALb6US04U3b                                             │
│  .5eym8TW_c8SuK0ltJ3rpYIzTbbaitX4wW                           │
│  .XFBoMYUZodetZdvTiFvSkQ    ← PAYLOAD CHIFFRÉ                │
│                                                                │
│  ✅ Confidentialité (payload opaque)                           │
│  ✅ Intégrité (selon le mode)                                 │
│  ❌ Plus complexe à implémenter                               │
└────────────────────────────────────────────────────────────────┘
```

### Structure d'un JWE

Un JWE est composé de **cinq parties** séparées par des points :

```
BASE64URL(Protected Header)
.
BASE64URL(Encrypted Key)
.
BASE64URL(Initialization Vector)
.
BASE64URL(Ciphertext)
.
BASE64URL(Authentication Tag)
```

| Partie | Rôle |
|---|---|
| **Protected Header** | Algorithmes utilisés (`alg`, `enc`) et métadonnées |
| **Encrypted Key** | Clé de contenu (CEK) chiffrée avec la clé du destinataire |
| **IV** | Vecteur d'initialisation pour le chiffrement symétrique |
| **Ciphertext** | Payload chiffré |
| **Authentication Tag** | Tag d'authentification AEAD — garantit l'intégrité |

---

### Architecture à deux niveaux de chiffrement

JWE utilise une approche hybride (comme TLS) :

```
1. GÉNÉRATION D'UNE CEK (Content Encryption Key)
   ├─ Clé symétrique aléatoire générée pour cette opération
   └─ Exemple : 256 bits aléatoires pour A256GCM

2. CHIFFREMENT DE LA CEK (Key Management)
   ├─ La CEK est chiffrée avec la clé publique du destinataire
   ├─ Algorithme : RSA-OAEP, ECDH-ES, A256KW…
   └─ Résultat : "Encrypted Key" (2ème partie du JWE)

3. CHIFFREMENT DU PAYLOAD (Content Encryption)
   ├─ Le payload JSON est chiffré avec la CEK
   ├─ Algorithme : A256GCM, A128CBC-HS256…
   └─ Résultat : Ciphertext + IV + Auth Tag

AVANTAGE : La CEK est jetable (une par token).
           Si la clé privée du destinataire est compromise plus tard,
           chaque token reste résistant grâce à la CEK unique.
```

---

### Algorithmes de gestion de clé (`alg`)

Ces algorithmes définissent comment la **CEK est protégée** (chiffrée ou dérivée).

| Algorithme | Mécanisme | Cas d'usage |
|---|---|---|
| `RSA-OAEP` | RSA + OAEP padding | Destinataire avec clé RSA publique |
| `RSA-OAEP-256` | RSA + OAEP-SHA256 | Idem, hachage plus fort |
| `RSA1_5` | RSA + PKCS#1 v1.5 | ❌ Dépréciée (vulnérable Bleichenbacher) |
| `ECDH-ES` | Échange ECDH + dérivation | Destinataire EC (clé éphémère, pas de CEK séparée) |
| `ECDH-ES+A128KW` | ECDH + AES Key Wrap 128 | ECDH avec CEK wrappée |
| `ECDH-ES+A256KW` | ECDH + AES Key Wrap 256 | Recommandé avec clés EC |
| `A128KW` | AES Key Wrap 128 | Clé symétrique partagée |
| `A256KW` | AES Key Wrap 256 | Clé symétrique partagée |
| `dir` | CEK directe | Clé symétrique partagée = CEK |

> ✅ **Recommandations :** `RSA-OAEP-256` pour les systèmes RSA. `ECDH-ES+A256KW` pour les systèmes EC. Éviter `RSA1_5` (dépréciée).

---

### Algorithmes de chiffrement du contenu (`enc`)

Ces algorithmes définissent comment le **payload est chiffré** avec la CEK.

| Algorithme | Type | Taille clé | Propriétés |
|---|---|---|---|
| `A128GCM` | AES-GCM | 128 bits | AEAD, rapide, authentifié |
| `A192GCM` | AES-GCM | 192 bits | AEAD, peu répandu |
| `A256GCM` | AES-GCM | 256 bits | AEAD, **recommandé** |
| `A128CBC-HS256` | AES-CBC + HMAC-SHA256 | 128+128 bits | Authentifié, plus lent |
| `A192CBC-HS384` | AES-CBC + HMAC-SHA384 | 192+192 bits | Authentifié |
| `A256CBC-HS512` | AES-CBC + HMAC-SHA512 | 256+256 bits | Authentifié, sécurisé |

> **GCM vs CBC-HS :** AES-GCM est un mode **AEAD** (Authenticated Encryption with Associated Data) — il assure chiffrement et authentification en une passe, est parallélisable et très rapide sur le matériel moderne. CBC-HS est plus ancien, nécessite deux passes (chiffrement + MAC). **Préférer `A256GCM`**.

#### Header JWE complet

```json
{
  "alg": "RSA-OAEP-256",
  "enc": "A256GCM",
  "typ": "JWE",
  "kid": "enc-key-2026-03"
}
```

---

### Quand chiffrer le payload ?

La question fondamentale : **votre cas d'usage nécessite-t-il JWE ?**

#### ✅ Cas où JWE est justifié

```
1. Données sensibles dans le token
   → PII (adresse, téléphone, données médicales)
   → Données réglementaires (RGPD, HIPAA, PCI-DSS)
   → Secrets métier (tarifs internes, segments clients)

2. Transport sur canaux non maîtrisés
   → Le token passe par des systèmes tiers (CDN, proxies, logs)
   → Logs centralisés qui ne doivent pas voir le contenu

3. Exigences de conformité
   → Audit de sécurité exigeant le chiffrement au niveau applicatif
   → "Defense in depth" : chiffrement même si TLS est compromis

4. Tokens stockés au repos
   → Tokens persistés en BDD ou localStorage
   → Refresh tokens avec longue durée de vie
```

#### ❌ Cas où JWS suffit (la majorité des API REST)

```
1. Payload ne contient que des IDs et rôles
   → { "sub": "user_123", "role": "admin", "iat": ..., "exp": ... }
   → Aucune donnée sensible — JWS + HTTPS est suffisant

2. Architecture microservices interne (réseau de confiance)
   → Le réseau interne est sécurisé
   → La complexité de JWE n'est pas justifiée

3. Tokens OAuth2 Access Token standards
   → Ils ne contiennent que des métadonnées d'autorisation
```

> **Règle pratique :** HTTPS protège le transport. JWE protège le contenu **même si quelqu'un a accès au token**. Si un accès au token sans HTTPS est impossible dans votre architecture, JWS est souvent suffisant.

---

### Implémentation JWE en Python

```python
from jwcrypto import jwk, jwe
from jwcrypto.common import json_encode
import json

# --- ÉMETTEUR ---

# Charger la clé publique du destinataire (depuis JWKS ou fichier)
recipient_public_key = jwk.JWK.from_pem(open("recipient_public.pem", "rb").read())

# Payload à chiffrer
payload = json.dumps({
    "sub": "user_1234",
    "email": "bobo@tenxyte.io",  # Donnée sensible → justifie JWE
    "medical_data": "confidentiel",
    "iat": 1711928000,
    "exp": 1711931600
})

# Créer le JWE
protected_header = {
    "alg": "RSA-OAEP-256",
    "enc": "A256GCM",
    "typ": "JWE",
    "kid": recipient_public_key["kid"]
}

jwe_token = jwe.JWE(
    payload.encode('utf-8'),
    recipient=recipient_public_key,
    protected=json_encode(protected_header)
)

serialized = jwe_token.serialize(compact=True)
print(f"JWE: {serialized}")

# --- DESTINATAIRE ---

# Charger la clé privée
recipient_private_key = jwk.JWK.from_pem(open("recipient_private.pem", "rb").read())

# Déchiffrer
received_jwe = jwe.JWE()
received_jwe.deserialize(serialized, key=recipient_private_key)

decrypted_payload = json.loads(received_jwe.payload)
print(f"Payload déchiffré: {decrypted_payload}")
```

---

### JWE + JWS : la combinaison optimale

Pour maximiser à la fois confidentialité et authenticité, on peut imbriquer un JWS dans un JWE (**"Nested JWT"**) :

```
Étape 1 — Signer le payload avec la clé privée de l'émetteur :
  JWS = sign(payload, emitter_private_key)
         → garantit l'authenticité

Étape 2 — Chiffrer le JWS avec la clé publique du destinataire :
  JWE = encrypt(JWS, recipient_public_key)
         → garantit la confidentialité

Header JWE indique : "cty": "JWT" (content type = JWT imbriqué)
```

```
SÉCURITÉ OBTENUE :
  ✅ Seul l'émetteur peut créer le JWS interne (clé privée)
  ✅ Seul le destinataire peut déchiffrer le JWE (clé privée)
  ✅ Intégrité + Authenticité + Confidentialité
```

---

## Récapitulatif de l'Étape 2

```
┌────────────────────────────────────────────────────────────────┐
│  ALGORITHMES DE SIGNATURE                                      │
│                                                                │
│  HS256/384/512  → Symétrique, secret partagé                  │
│                   ⚠️ Toute partie vérifiant peut émettre      │
│                                                                │
│  RS256/384/512  → Asymétrique RSA-PKCS#1                      │
│  PS256/384/512  → Asymétrique RSA-PSS (préféré à RS256)       │
│  ES256/384/512  → Asymétrique ECDSA (compact + rapide)        │
│                   ✅ Seul le détenteur de la privée peut signer│
│                                                                │
│  RECOMMANDATION : ES256 (nouveaux projets), RS256 (compat)    │
├────────────────────────────────────────────────────────────────┤
│  JWKS & ROTATION                                               │
│                                                                │
│  JWK  → Représentation JSON d'une clé cryptographique         │
│  JWKS → Ensemble de JWK publié sur /.well-known/jwks.json     │
│  kid  → Permet de sélectionner la bonne clé et de            │
│          gérer la rotation sans interruption                  │
│                                                                │
│  ⚠️  Cacher le JWKS (TTL ~1h), invalider sur kid inconnu     │
│  ⚠️  Ne jamais suivre un jku depuis le header JWT             │
├────────────────────────────────────────────────────────────────┤
│  JWE — CHIFFREMENT                                             │
│                                                                │
│  JWS → Signature uniquement (payload visible)                 │
│  JWE → Chiffrement (payload opaque)                           │
│                                                                │
│  alg (gestion CEK) : RSA-OAEP-256, ECDH-ES+A256KW            │
│  enc (contenu)     : A256GCM (recommandé)                     │
│                                                                │
│  Nested JWT → JWS chiffré dans JWE = auth + confidentialité   │
└────────────────────────────────────────────────────────────────┘
```

### Points de contrôle — vérifiez votre compréhension

1. Pourquoi un service qui peut **vérifier** un JWT signé avec HS256 peut-il aussi en **émettre** ? Quelle conséquence architecturale cela implique-t-il ?
2. En quoi `PS256` est-il supérieur à `RS256` ? Quelle vulnérabilité historique corrige-t-il ?
3. Un attaquant intercepte un JWE. Qu'est-ce qu'il peut et ne peut pas en déduire ?
4. Qu'est-ce que la CEK dans JWE, et pourquoi son caractère jetable renforce-t-il la sécurité ?
5. Votre API reçoit un JWT dont le `kid` ne correspond à aucune clé dans votre cache JWKS. Quelle est la procédure correcte ?
6. Quelle vulnérabilité cible l'attaque par `jku` injection dans le header d'un JWT ?
7. Dans quel scénario concret l'utilisation de JWE est-elle indispensable dans une API REST ?

---

*Cours rédigé pour le programme **Maîtriser les JWT en profondeur** — Étape 2 : Cryptographie appliquée.*  
*Références : RFC 7515 (JWS), RFC 7516 (JWE), RFC 7517 (JWK), RFC 7518 (JWA), NIST SP 800-57.*