# Maîtriser les JWT en profondeur
### Cours complet — Étape 1 : Fondations

> **Prérequis :** Notions de base en HTTP, JSON, et cryptographie élémentaire.  
> **Objectif :** Comprendre la nature, l'anatomie et le fonctionnement cryptographique des JSON Web Tokens avant toute implémentation.

---

## 1.1 — Qu'est-ce qu'un JWT ?

### Définition formelle

Un **JSON Web Token (JWT)** est un standard ouvert défini par la [RFC 7519](https://datatracker.ietf.org/doc/html/rfc7519) (2015). Il décrit un format compact, auto-contenu et URL-safe pour transmettre des **claims** (affirmations) entre deux parties sous forme d'objet JSON.

> *"JSON Web Token (JWT) is a compact, URL-safe means of representing claims to be transferred between two parties."*  
> — RFC 7519, Section 1

Un JWT est fondamentalement un **conteneur de données signé cryptographiquement**. Il permet à une partie (souvent un serveur) de **signer un ensemble d'informations**, et à une autre partie de **vérifier que ces informations n'ont pas été altérées**, sans avoir à contacter l'émetteur original.

---

### Problème résolu : transmettre des informations vérifiables

Imaginons un système distribué : le serveur A émet une assertion (`"cet utilisateur est admin"`), et le serveur B doit la consommer sans interroger A à chaque requête.

Sans JWT, le serveur B ne peut pas savoir si le client lui ment. Avec JWT :

1. Le serveur A **signe** le claim `{ "role": "admin" }` avec une clé secrète.
2. Le client présente ce token au serveur B.
3. Le serveur B **vérifie la signature** — si elle est valide, les données sont authentiques.

Le JWT résout le problème de **confiance sans canal de communication synchrone** entre émetteur et vérificateur.

---

### Authentification vs Autorisation

Ces deux concepts sont souvent confondus. Les JWT interviennent dans les deux, mais différemment.

| Concept | Définition | Question posée | Exemple avec JWT |
|---|---|---|---|
| **Authentification** | Vérifier *qui* est l'utilisateur | "Es-tu bien qui tu prétends être ?" | Le serveur émet un JWT après vérification du mot de passe |
| **Autorisation** | Vérifier *ce que* l'utilisateur peut faire | "As-tu le droit de faire ça ?" | Le JWT contient un claim `role: "editor"` lu par le serveur de ressources |

Un JWT peut transporter les informations nécessaires aux **deux étapes**. Cependant, il est important de comprendre que :

- L'**authentification** est un acte ponctuel (login) → produit le JWT.
- L'**autorisation** est continue (chaque requête) → consomme le JWT.

---

### Comparaison avec les sessions classiques (Stateful vs Stateless)

#### Sessions classiques — architecture Stateful

```
Client                    Serveur
  │                          │
  │── POST /login ──────────►│
  │                          │  1. Vérifie les credentials
  │                          │  2. Crée une session en mémoire/BDD
  │                          │     { sessionId: "abc123", userId: 42 }
  │◄── Set-Cookie: sid=abc123 ─│
  │                          │
  │── GET /profile ─────────►│
  │   Cookie: sid=abc123     │  3. Lookup sessionId "abc123" en BDD
  │                          │  4. Retrouve userId = 42
  │◄── 200 OK ───────────────│
```

**Problèmes :**
- Le serveur doit **stocker l'état** de chaque session (mémoire, Redis, BDD).
- Scalabilité horizontale difficile : si plusieurs serveurs, ils doivent partager le store de sessions (session stickiness ou store distribué).
- Chaque requête nécessite une **lecture en base** pour valider la session.

#### JWT — architecture Stateless

```
Client                    Serveur
  │                          │
  │── POST /login ──────────►│
  │                          │  1. Vérifie les credentials
  │                          │  2. Génère un JWT signé contenant { userId: 42 }
  │◄── 200 OK { token: "..." }─│
  │                          │
  │── GET /profile ─────────►│
  │   Authorization: Bearer  │  3. Vérifie la signature du JWT (aucune BDD)
  │   eyJ...                 │  4. Lit userId = 42 directement dans le token
  │◄── 200 OK ───────────────│
```

**Avantages :**
- **Zéro état côté serveur** — chaque requête est auto-suffisante.
- Scalabilité naturelle : n'importe quel serveur peut vérifier le token.
- Idéal pour les **microservices**, les **APIs publiques**, les **architectures distribuées**.

**Inconvénients :**
- **Révocation difficile** : un token valide le reste jusqu'à expiration (voir section avancée sur les blocklists).
- Le payload voyage **dans chaque requête** → attention à la taille.
- Si la clé secrète est compromise, **tous** les tokens sont compromis.

---

## 1.2 — Anatomie d'un JWT

### Structure en trois parties

Un JWT est une chaîne de caractères composée de **trois segments séparés par des points** :

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9
.
eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkJvYm8iLCJpYXQiOjE3MTE5MjgwMDB9
.
SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

Chaque partie correspond à :

```
BASE64URL(Header) . BASE64URL(Payload) . Signature
```

Visuellement :

```
┌──────────────────────────────────────────────────────┐
│  HEADER      │       PAYLOAD        │   SIGNATURE    │
│  Base64URL   │      Base64URL       │   Calculée     │
│              │                      │   sur H+P      │
└──────────────────────────────────────────────────────┘
       ↓                ↓                    ↓
   { alg, typ }   { claims JSON }    HMAC/RSA/ECDSA...
```

---

### Encodage Base64URL — ce que ce n'est PAS

C'est la **confusion la plus dangereuse** sur les JWT.

| Propriété | Base64URL | Chiffrement |
|---|---|---|
| Réversibilité | ✅ Décodable par n'importe qui | ❌ Nécessite une clé |
| Objectif | Représentation texte d'octets | Confidentialité des données |
| Protège les données ? | ❌ Non | ✅ Oui |

> ⚠️ **Base64URL n'est pas du chiffrement.** N'importe qui peut décoder le header et le payload d'un JWT. **Ne jamais stocker de données sensibles dans un JWT non chiffré (JWS).**

Base64URL diffère légèrement du Base64 standard :
- `+` → `-`
- `/` → `_`
- Pas de padding `=` (ou padding optionnel)

Cela permet d'utiliser le token dans des URLs et des headers HTTP sans encodage supplémentaire.

#### Exemple de décodage manuel

```bash
# Header d'un JWT :
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9

# Décoder en base64 :
echo "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" | base64 -d
# → {"alg":"HS256","typ":"JWT"}
```

---

### Décoder manuellement sur jwt.io

[jwt.io](https://jwt.io) est l'outil de référence pour inspecter visuellement un JWT.

**Exercice pratique :**

1. Copiez ce token de test :
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkJvYm8iLCJyb2xlIjoiYWRtaW4iLCJpYXQiOjE3MTE5MjgwMDAsImV4cCI6MTcxMTkzMTYwMH0.Tzy1tSUNkqaubOI_7H8xxHpNDTPdcoHCAEnK60JnET8
```
2. Collez-le sur jwt.io et activer `Base64URL Encoded` au niveau de la case de la verification → vous verrez Header, Payload, et le statut de la signature.
3. Dans le champ "VERIFY SIGNATURE", entrez le secret : `d6671740595c73943551aa2663b7fafb1fe344d10bcba53e5f1a157a77bdfc19`
4. Dans le mode `JWT Encoder`, dans la partie décodée du payload (à gauche), changez la valeur de `name` (ex : `"Bobo"` → `"Alice"`) → le token encodé (à droite) est recalculé, et la signature change automatiquement. Cela montre que **toute modification du payload produit une signature différente**.

Cette expérience illustre le principe fondamental : **modifier le payload sans recalculer la signature (donc sans posséder la clé secrète) invalidera le token**.

---

## 1.3 — Le Header

### Structure et rôle

Le header est un objet JSON qui **décrit comment le token est signé**. Après encodage en Base64URL, il constitue la première partie du JWT.

```json
{
  "alg": "HS256",
  "typ": "JWT"
}
```

Encodé :
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9
```

---

### Champ `alg` — Algorithme de signature

C'est le champ **le plus critique** du header. Il détermine comment la signature est calculée et vérifiée.

#### Algorithmes symétriques (HMAC)

L'**émetteur** et le **vérificateur** partagent **la même clé secrète**.

| Algorithme | Nom complet | Longueur de clé recommandée |
|---|---|---|
| `HS256` | HMAC with SHA-256 | ≥ 256 bits (32 octets) |
| `HS384` | HMAC with SHA-384 | ≥ 384 bits (48 octets) |
| `HS512` | HMAC with SHA-512 | ≥ 512 bits (64 octets) |

**Cas d'usage :** services monolithiques, microservices avec un émetteur et un vérificateur contrôlés par la même entité.

**Risque :** si le secret est partagé avec un tiers, ce tiers peut **émettre** de nouveaux tokens valides.

```
Signature = HMAC-SHA256(
    base64url(header) + "." + base64url(payload),
    secret_key
)
```

#### Algorithmes asymétriques (RSA / ECDSA)

L'émetteur signe avec une **clé privée**, les vérificateurs valident avec la **clé publique**.

| Algorithme | Type | Force recommandée |
|---|---|---|
| `RS256` | RSA + SHA-256 | 2048 bits minimum |
| `RS384` | RSA + SHA-384 | 2048 bits minimum |
| `RS512` | RSA + SHA-512 | 4096 bits recommandé |
| `ES256` | ECDSA + SHA-256 (P-256) | 256 bits (équivalent RSA 3072) |
| `ES384` | ECDSA + SHA-384 (P-384) | 384 bits |
| `ES512` | ECDSA + SHA-512 (P-521) | 521 bits |

**Avantages d'ECDSA (`ES256`) vs RSA (`RS256`) :**
- Clés plus courtes pour une sécurité équivalente.
- Signatures plus petites → tokens plus compacts.
- Opérations cryptographiques plus rapides.

**Cas d'usage :** systèmes distribués où plusieurs services vérifient les tokens mais seul l'AuthServer les émet. La clé publique peut être exposée via un endpoint JWKS.

> ✅ **Recommandation 2024 :** Préférez `ES256` (ECDSA) pour les nouvelles implémentations. `RS256` reste très courant et solide. **Évitez `HS256` dans les architectures multi-services** car il nécessite de partager le secret.

#### L'algorithme `none` — Danger absolu

```json
{ "alg": "none" }
```

> 🔴 **CRITIQUE — Vulnérabilité CVE.** Certaines bibliothèques historiques acceptaient `alg: none`, permettant à un attaquant de **forger n'importe quel token** sans clé. Vérifiez toujours que votre bibliothèque **rejette explicitement** `none`.

---

### Champ `typ` — Type de token

Valeur quasi-universelle : `"JWT"`. Peut être omis (par défaut JWT), mais sa présence est une bonne pratique pour l'interopérabilité.

Dans des cas spéciaux, on peut trouver `"at+JWT"` (Access Token JWT, RFC 9068) ou `"dpop+jwt"` (DPoP, RFC 9449).

---

### Champ `kid` — Key ID

Le `kid` (Key Identifier) est un identifiant opaque permettant au vérificateur de sélectionner la **bonne clé parmi plusieurs**.

```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "key-2024-03"
}
```

**Cas d'usage principal : la rotation de clés**

```
Serveur expose ses clés publiques via /.well-known/jwks.json :

{
  "keys": [
    { "kid": "key-2024-01", "kty": "RSA", "n": "...", "e": "AQAB" },
    { "kid": "key-2024-03", "kty": "RSA", "n": "...", "e": "AQAB" }
  ]
}
```

Le vérificateur lit le `kid` du header JWT → sélectionne la clé correspondante dans le JWKS → vérifie la signature. Cela permet de **déprécier des clés progressivement** sans invalider tous les tokens existants.

> ⚠️ **Vulnérabilité `kid` injection :** Certaines implémentations utilisent le `kid` pour faire une requête SQL ou lire un fichier. Un `kid` malformé peut mener à une injection. Traitez toujours le `kid` comme une entrée non fiable.

---

## 1.4 — Le Payload (Claims)

### Définition d'un claim

Un **claim** est une assertion — une déclaration sur un sujet. Dans un JWT, les claims sont des paires clé-valeur dans l'objet JSON du payload.

```json
{
  "sub": "user_1234",
  "name": "Bobo",
  "role": "admin",
  "iat": 1711928000,
  "exp": 1711931600
}
```

La RFC 7519 définit trois catégories de claims.

---

### Registered Claims (Claims enregistrés)

Ce sont des claims **standardisés** par la RFC. Leurs noms sont courts (3 lettres) pour des raisons de compacité. Tous sont **optionnels** mais leur utilisation est fortement recommandée.

#### `iss` — Issuer (Émetteur)

```json
{ "iss": "https://auth.tenxyte.io" }
```

Identifie qui a émis le token. Typiquement une URL ou un identifiant de service. Le vérificateur **doit** valider que `iss` correspond à l'émetteur attendu.

---

#### `sub` — Subject (Sujet)

```json
{ "sub": "user_1234" }
```

Identifie le principal (l'entité) concerné par le JWT. Doit être **unique** dans le contexte de l'émetteur. Souvent l'ID utilisateur, un UUID, ou un identifiant métier.

> La combinaison `iss` + `sub` doit être **globalement unique**.

---

#### `aud` — Audience

```json
{ "aud": "api.tenxyte.io" }
```

Ou pour plusieurs audiences :
```json
{ "aud": ["api.tenxyte.io", "dashboard.tenxyte.io"] }
```

Indique le ou les destinataires prévus du token. Un serveur recevant un token **doit vérifier** qu'il fait partie de l'audience. Si `aud` est absent ou ne contient pas le serveur, le token **doit être rejeté**.

> ⚠️ **Erreur classique :** ne pas valider `aud` permet à un token émis pour le service A d'être accepté par le service B — c'est la **Confused Deputy Attack**.

---

#### `exp` — Expiration Time

```json
{ "exp": 1711931600 }
```

**Timestamp Unix** (secondes depuis l'epoch) après lequel le token n'est plus valide. Le vérificateur **doit rejeter** un token dont `exp` est dans le passé.

Durées recommandées selon le type de token :

| Type de token | Durée typique | Justification |
|---|---|---|
| Access Token (API) | 5 – 15 minutes | Réduire la fenêtre d'exploitation |
| Access Token (Web) | 1 heure | UX acceptable |
| Refresh Token | 7 – 30 jours | Long-lived, mais révocable |
| Token one-time (magic link) | 10 – 30 minutes | Usage unique |

> ✅ **Tolérance de décalage horaire (`leeway`) :** Les serveurs distribués ont des horloges légèrement désynchronisées. Il est courant d'accepter une tolérance de **60 secondes** autour de `exp` et `nbf`.

---

#### `nbf` — Not Before

```json
{ "nbf": 1711928000 }
```

Timestamp avant lequel le token n'est **pas encore valide**. Utile pour des tokens émis à l'avance (ex : planification de tâches différées, tokens d'activation futurs).

```
Timeline :  ──────[nbf]────────────[exp]──────►
                   Token valide ici
```

---

#### `iat` — Issued At

```json
{ "iat": 1711925000 }
```

Timestamp d'émission du token. Utile pour calculer l'âge du token, auditer les logs, ou implémenter des politiques de rotation (ex : "si le token a plus de 30 min, forcer un refresh même avant `exp`").

---

#### `jti` — JWT ID

```json
{ "jti": "01HV4MXYZ9K3Q7BWRN8PSDTCF" }
```

Identifiant **unique** du token (UUID, ULID, ou chaîne aléatoire). Son rôle principal est la **prévention du rejeu** (replay attack) : en stockant les `jti` utilisés, le serveur peut refuser un token présenté deux fois.

```
Flux anti-rejeu :
  1. Réception du JWT
  2. Vérification de la signature et de exp
  3. Lookup de jti dans le store "used_tokens"
  4. Si trouvé → rejeter (replay détecté)
  5. Sinon → ajouter jti au store, TTL = exp - now
  6. Traiter la requête
```

---

### Public Claims

Claims non enregistrés par la RFC mais **publiés dans le registre IANA** ([IANA JWT Claims Registry](https://www.iana.org/assignments/jwt/jwt.xhtml)) pour éviter les collisions entre différentes organisations.

Exemples courants :

```json
{
  "email": "bobo@tenxyte.io",
  "name": "Bobo",
  "picture": "https://cdn.example.com/avatar.jpg",
  "locale": "fr-BJ"
}
```

Ces claims sont utilisés notamment dans les tokens **OpenID Connect** (`id_token`).

---

### Private Claims

Claims **définis librement** entre l'émetteur et le consommateur, sans enregistrement. Ils doivent être utilisés avec précaution pour éviter les collisions.

```json
{
  "tenxyte_tenant_id": "tenant_abc123",
  "tenxyte_permissions": ["read:contracts", "write:invoices"],
  "subscription_tier": "pro"
}
```

> **Convention recommandée :** Préfixer les private claims avec votre domaine ou namespace pour éviter les conflits (`tenxyte_*`, `x-*`, ou URI-based).

---

### Ce qu'il ne faut JAMAIS mettre dans le Payload

Rappel fondamental : **le payload est encodé en Base64URL, pas chiffré**. N'importe qui avec accès au token peut lire son contenu.

| ❌ Ne jamais inclure | Raison |
|---|---|
| Mot de passe (haché ou non) | Exposition directe |
| Numéros de carte bancaire | Données PCI-DSS |
| Numéros de sécurité sociale | Données PII sensibles |
| Secrets API | Compromission immédiate |
| Données médicales brutes | Données HIPAA/RGPD |
| Tokens d'accès tiers | Chaîne de compromission |

> ✅ **Règle d'or :** Ne mettez dans le payload que ce que vous seriez à l'aise d'afficher dans un log de production. Si la réponse est non, la donnée n'a pas sa place dans un JWT non chiffré.
>
> Si vous avez besoin de confidentialité, utilisez **JWE (JSON Web Encryption, RFC 7516)** — un JWT chiffré.

---

### Taille et performance

Chaque claim alourdit le token. Un JWT voyage dans **chaque requête HTTP** (header `Authorization`). Des claims excessifs impactent :

- La bande passante (notamment sur mobile/Afrique).
- Les performances de parsing.
- La lisibilité des logs.

**Bonne pratique :** Inclure seulement ce qui est **nécessaire pour prendre la décision d'autorisation** côté serveur. Pour des données supplémentaires (profil complet, préférences…), faites un appel API séparé.

---

## 1.5 — La Signature

### Principe de la signature cryptographique

La signature est la **troisième partie** du JWT. Elle garantit deux propriétés fondamentales :

1. **Intégrité** : le contenu n'a pas été modifié depuis l'émission.
2. **Authenticité** : le token a bien été émis par une entité possédant la clé.

#### Calcul de la signature (HS256)

```
signature = HMAC-SHA256(
    base64url(header) + "." + base64url(payload),
    secret
)
```

En détail :

```
1. Encoder le header :
   {"alg":"HS256","typ":"JWT"} → eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9

2. Encoder le payload :
   {"sub":"1234","name":"Bobo"} → eyJzdWIiOiIxMjM0IiwibmFtZSI6IkJvYm8ifQ

3. Concaténer avec un point :
   signing_input = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0IiwibmFtZSI6IkJvYm8ifQ"

4. Calculer le HMAC-SHA256 avec le secret :
   signature_bytes = HMAC-SHA256(signing_input, "my-secret-key")

5. Encoder la signature en Base64URL :
   signature = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

6. Assembler le JWT final :
   jwt = signing_input + "." + signature
```

---

### Vérification de l'intégrité ≠ Confidentialité

C'est la distinction la plus importante à maîtriser.

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   SIGNATURE = INTÉGRITÉ + AUTHENTICITÉ                 │
│                                                         │
│   ✅ Garantit que le contenu n'a pas été modifié       │
│   ✅ Garantit qui a émis le token (si clé sécurisée)   │
│   ❌ Ne cache PAS le contenu                            │
│   ❌ N'empêche PAS la lecture du payload               │
│                                                         │
│   CHIFFREMENT (JWE) = CONFIDENTIALITÉ                   │
│                                                         │
│   ✅ Cache le contenu (chiffré)                         │
│   ❌ N'empêche pas la falsification seule              │
│       (d'où l'usage conjoint signature + chiffrement)  │
└─────────────────────────────────────────────────────────┘
```

#### Tableau récapitulatif

| Propriété | JWS (JWT signé) | JWE (JWT chiffré) | JWS + JWE |
|---|---|---|---|
| Intégrité | ✅ | ❌ | ✅ |
| Authenticité | ✅ | ❌ | ✅ |
| Confidentialité | ❌ | ✅ | ✅ |
| Lisible sans clé | ✅ Oui | ❌ Non | ❌ Non |

Dans la pratique courante (APIs REST, OAuth2), on utilise des **JWS** — des JWT simplement signés. La confidentialité est assurée par **TLS/HTTPS**, pas par le JWT lui-même.

---

### Pourquoi un token signé ne peut pas être falsifié

Scénario d'attaque : un utilisateur tente de modifier son payload pour s'octroyer des droits.

```
Token légitime :
  header.payload.signature_originale

Attaquant modifie le payload :
  { "role": "user" }  →  { "role": "admin" }

Nouveau payload encodé → différent de l'original

Tentative de falsification :
  header.payload_modifie.signature_originale

Vérification côté serveur :
  HMAC-SHA256(header + "." + payload_modifie, secret)
  ≠ signature_originale

  → Résultat : REJETÉ ✗
```

Pour falsifier un token valide, l'attaquant doit :
1. Modifier le payload.
2. **Recalculer la signature** — impossible sans la clé secrète.

C'est la propriété fondamentale des fonctions HMAC et des signatures asymétriques : la **résistance à la falsification sans connaissance de la clé**.

---

### Algorithmes asymétriques — le flux complet

Avec RS256 ou ES256, le flux de signature/vérification est le suivant :

```
AUTH SERVER (possède clé privée)          API SERVER (possède clé publique)
        │                                           │
        │  1. Génère le JWT                         │
        │  2. Signe avec clé privée                 │
        │     sig = RSA-SHA256(input, private_key)  │
        │──── JWT ─────────────────────────────────►│  (via le client)
        │                                           │
        │                                    3. Vérifie :
        │                                       RSA-SHA256(input, public_key)
        │                                       == sig ?
        │                                       → ✅ Valide
```

**Avantage clé :** La clé publique peut être partagée librement (endpoint JWKS). N'importe quel service peut vérifier les tokens **sans jamais avoir accès à la clé privée**. Le seul serveur capable d'**émettre** des tokens valides est celui qui possède la clé privée.

---

### Sécurité de la clé — règles absolues

| Règle | HS256 | RS256/ES256 |
|---|---|---|
| Ne jamais logger la clé | ✅ | ✅ clé privée uniquement |
| Ne jamais inclure dans le code source | ✅ | ✅ clé privée uniquement |
| Stocker dans les variables d'environnement | ✅ | ✅ clé privée uniquement |
| Longueur minimale | ≥ 256 bits | ≥ 2048 bits (RSA) / 256 bits (EC) |
| Rotation régulière | Recommandée | Recommandée avec kid |
| La clé publique peut être exposée | N/A | ✅ (JWKS endpoint) |

```python
# ❌ Ne JAMAIS faire
SECRET = "monmotdepasse"  # Trop court, dans le code

# ✅ Correct
import os
SECRET = os.getenv("JWT_SECRET_KEY")  # Variable d'environnement
# Et la valeur doit être générée aléatoirement :
# openssl rand -hex 32
```

---

## Récapitulatif de l'Étape 1

```
┌──────────────────────────────────────────────────────────────┐
│  JWT = Header.Payload.Signature                              │
│                                                              │
│  Header    → Méta-informations (alg, typ, kid)              │
│  Payload   → Claims (iss, sub, aud, exp, nbf, iat, jti +    │
│              claims custom)                                  │
│  Signature → Garantie d'intégrité et d'authenticité         │
│                                                              │
│  ⚠️  Base64URL ≠ Chiffrement → payload lisible par tous     │
│  ⚠️  Signature ≠ Confidentialité → utiliser HTTPS + JWE     │
│  ⚠️  alg: none → vulnérabilité critique à bloquer           │
│  ⚠️  Données sensibles → jamais dans le payload              │
│                                                              │
│  ✅ Stateless → scalabilité horizontale naturelle           │
│  ✅ Auto-contenu → aucun lookup BDD pour la vérification    │
│  ✅ Standardisé RFC 7519 → interopérable                    │
└──────────────────────────────────────────────────────────────┘
```

### Points de contrôle — vérifiez votre compréhension

Avant de passer à l'étape 2, vous devez pouvoir répondre à :

1. Quelle est la différence fondamentale entre un JWT signé (JWS) et un JWT chiffré (JWE) ?
2. Pourquoi préférer `ES256` à `RS256` dans une nouvelle implémentation ?
3. Que se passe-t-il si un attaquant modifie le payload d'un JWT et renvoie la signature originale ?
4. Quels claims doit-on **obligatoirement valider** à la réception d'un JWT ?
5. Dans quel cas `alg: none` peut-il être exploité et comment s'en protéger ?
6. Pourquoi est-il dangereux de partager un secret HMAC avec un service tiers ?
7. À quoi sert le claim `jti` et dans quel scénario devient-il indispensable ?

---

*Cours rédigé pour le programme **Maîtriser les JWT en profondeur** — Étape 1 : Fondations.*  
*Références : RFC 7519, RFC 7515, RFC 7516, RFC 7517, IANA JWT Claims Registry.*