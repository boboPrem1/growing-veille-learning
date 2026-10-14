# Plan d'étude : Maîtriser les JWT en profondeur

## Étape 1 — Fondations : comprendre les bases

### 1.1 Qu'est-ce qu'un JWT ?
- Définition (JSON Web Token, RFC 7519)
- Problème résolu : transmission d'informations vérifiables entre parties
- Différence entre **authentification** et **autorisation**
- Comparaison avec les sessions classiques (cookie + serveur stateful)

### 1.2 Anatomie d'un JWT
- Structure en 3 parties : `Header.Payload.Signature`
- Encodage Base64URL (≠ chiffrement)
- Décoder manuellement un token sur [jwt.io](https://jwt.io)

### 1.3 Le Header
- `alg` : algorithme de signature (HS256, RS256, ES256…)
- `typ` : type du token (`JWT`)
- `kid` : Key ID (optionnel, pour la rotation de clés)

### 1.4 Le Payload (Claims)
- **Registered claims** : `iss`, `sub`, `aud`, `exp`, `nbf`, `iat`, `jti`
- **Public claims** : enregistrés dans le registre IANA
- **Private claims** : personnalisés entre émetteur et consommateur
- Ce qu'il ne faut **jamais** mettre dans le payload (données sensibles)

### 1.5 La Signature
- Principe de la signature cryptographique
- Vérification de l'intégrité ≠ confidentialité
- Pourquoi un token signé ne peut pas être falsifié (sans la clé)

---

## Étape 2 — Cryptographie appliquée aux JWT

### 2.1 Algorithmes symétriques (HMAC)
- `HS256`, `HS384`, `HS512`
- Une seule clé secrète partagée
- Cas d'usage : microservices internes, API mono-domaine
- Risques : la clé doit rester strictement secrète des deux côtés

### 2.2 Algorithmes asymétriques (RSA / EC)
- `RS256`, `RS384`, `RS512` (RSA + SHA)
- `ES256`, `ES384`, `ES512` (ECDSA + SHA)
- `PS256` (RSA-PSS)
- Clé privée pour signer → clé publique pour vérifier
- Cas d'usage : OAuth2, OIDC, SSO multi-services
- Avantage : la clé de vérification peut être publique (JWKS endpoint)

### 2.3 JWK et JWKS
- JSON Web Key (RFC 7517)
- Endpoint `/.well-known/jwks.json`
- Rotation de clés et `kid`

### 2.4 Algorithmes de chiffrement : JWE
- Différence JWT (signé) vs JWE (chiffré, RFC 7516)
- Quand chiffrer le payload ?
- Algorithmes : `RSA-OAEP`, `A256GCM`…

---

## Étape 3 — Flux d'authentification et d'autorisation

### 3.1 Flux JWT standard
1. Login → serveur émet `access_token` + `refresh_token`
2. Client stocke les tokens
3. Requêtes avec `Authorization: Bearer <token>`
4. Serveur vérifie la signature + `exp`

### 3.2 Access Token vs Refresh Token
- Durée de vie courte (5–15 min) vs longue (7–30 jours)
- Rotation du refresh token (Refresh Token Rotation)
- Détection de réutilisation (Reuse Detection)

### 3.3 OAuth 2.0 et JWT
- Rôle du JWT comme Bearer Token dans OAuth2
- `client_credentials`, `authorization_code`, `implicit` (déprécié), `device_flow`
- Introspection endpoint (`/introspect`) vs vérification locale

### 3.4 OpenID Connect (OIDC)
- `id_token` JWT et ses claims spécifiques (`nonce`, `at_hash`, `azp`)
- Différence `access_token` / `id_token` / `refresh_token` dans OIDC
- Discovery endpoint `/.well-known/openid-configuration`

---

## Étape 4 — Sécurité : attaques et contre-mesures

### 4.1 Attaque "algorithm confusion" (`alg: none`)
- Vulnérabilité historique : accepter `alg: none`
- Fix : toujours valider et whitelister l'algorithme côté serveur

### 4.2 Confusion RS256 → HS256
- Attaquant signe avec la clé publique RSA en HMAC
- Fix : ne jamais inférer l'algorithme depuis le token lui-même

### 4.3 Brute-force sur secret HMAC
- Secrets faibles cassables hors-ligne
- Fix : secrets ≥ 256 bits, générés aléatoirement

### 4.4 JWT sans expiration (`exp` absent)
- Token valide à vie
- Fix : toujours inclure et valider `exp`

### 4.5 Vol de token (XSS, MITM)
- Stockage dangereux dans `localStorage`
- Fix : `httpOnly` cookie, HTTPS strict, CSP

### 4.6 Replay Attack
- Réutilisation d'un token valide intercepté
- Fix : `jti` (JWT ID) + blacklist, courte durée de vie

### 4.7 Injection dans les claims
- Manipulation du payload si décodage sans vérification
- Fix : toujours vérifier la signature avant de lire les claims

### 4.8 SSRF via `jku` / `x5u`
- Header pointant vers une JWKS malveillante
- Fix : whitelist stricte des URLs de clés autorisées

---

## Étape 5 — Implémentation pratique

### 5.1 Implémenter JWT from scratch (au moins une fois)
- Encoder manuellement Header + Payload en Base64URL
- Signer avec HMAC-SHA256 en Node.js / Python / autre
- Vérifier sans librairie tierce

### 5.2 Utiliser les librairies standard
- **Node.js** : `jsonwebtoken`, `jose`, `passport-jwt`
- **Python** : `PyJWT`, `python-jose`
- **Java** : `jjwt`, `nimbus-jose-jwt`
- **Go** : `golang-jwt/jwt`
- Bonnes pratiques : options de validation (clockSkew, audience, issuer)

### 5.3 Implémentation côté serveur
- Middleware de vérification réutilisable
- Gestion des erreurs : `TokenExpiredError`, `JsonWebTokenError`, `NotBeforeError`
- Blacklist / revocation (Redis, base de données)

### 5.4 Implémentation côté client
- Stockage sécurisé : `httpOnly` cookie vs mémoire JS
- Refresh silencieux en arrière-plan
- Gestion de l'expiration (intercepteur Axios / fetch)

### 5.5 Rotation et révocation
- Pourquoi les JWT sont "stateless" mais la révocation est "stateful"
- Stratégies : short-lived tokens, blacklist `jti`, versioning de token

---

## Étape 6 — Cas d'usage avancés

### 6.1 JWT dans les microservices
- Propagation du token entre services (service-to-service)
- Token exchange (RFC 8693)
- mTLS + JWT pour l'authentification inter-services

### 6.2 Nested JWT
- Signer puis chiffrer un token (Sign-then-Encrypt)
- Cas d'usage : données ultra-sensibles dans le payload

### 6.3 JWT et WebSockets
- Authentification lors du handshake
- Passage du token via query string (risques de log) vs protocole

### 6.4 Federated Identity
- SAML vs JWT/OIDC
- Intégration avec des IdP externes (Auth0, Keycloak, Okta, Cognito)

### 6.5 Zero Trust et JWT
- JWT comme preuve d'identité dans une architecture Zero Trust
- SPIFFE/SPIRE et les SVIDs basés sur JWT

---

## Étape 7 — Standards, RFCs et écosystème

| RFC | Sujet |
|-----|-------|
| RFC 7519 | JSON Web Token (JWT) |
| RFC 7515 | JSON Web Signature (JWS) |
| RFC 7516 | JSON Web Encryption (JWE) |
| RFC 7517 | JSON Web Key (JWK) |
| RFC 7518 | JSON Web Algorithms (JWA) |
| RFC 6749 | OAuth 2.0 |
| RFC 6750 | Bearer Token Usage |
| RFC 8693 | Token Exchange |
| OpenID Connect Core 1.0 | OIDC |

---

## Étape 8 — Consolidation et validation des acquis

### Exercices pratiques
- [ ] Décoder et valider un JWT à la main (sans librairie)
- [ ] Implémenter un serveur d'auth avec `access_token` + `refresh_token`
- [ ] Implémenter la rotation du refresh token avec détection de réutilisation
- [ ] Exploiter la vulnérabilité `alg: none` sur un serveur de test intentionnellement vulnérable
- [ ] Mettre en place un JWKS endpoint avec rotation de clés
- [ ] Intégrer OIDC avec un IdP (Keycloak en local par ex.)

### Questions de vérification
- Quelle est la différence entre `iss` et `aud` et pourquoi les valider ?
- Quand utiliser HMAC vs RSA ?
- Comment révoquer un JWT sans base de données ?
- Quels claims sont obligatoires ? Lesquels sont recommandés ?
- Pourquoi `localStorage` est dangereux pour stocker un JWT ?

---

## Ressources recommandées

- [jwt.io](https://jwt.io) — décodage interactif + librairies
- [RFC 7519](https://datatracker.ietf.org/doc/html/rfc7519) — spec officielle
- *"The JWT Handbook"* — Sebastián Peyrott (Auth0)
- [PortSwigger Web Security Academy — JWT attacks](https://portswigger.net/web-security/jwt)
- [OWASP JWT Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/JSON_Web_Token_for_Java_Cheat_Sheet.html)
- [oauth.net](https://oauth.net/2/) — ressources OAuth2/OIDC
