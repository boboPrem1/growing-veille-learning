# Java — Niveau 05 : Expert

## Rappel du fil rouge : **TaskFlow**

> À l'issue du niveau Master, TaskFlow v4.0 est une API REST Spring Boot complète avec JPA/Hibernate, authentification JWT, autorisation par rôles, tests multi-couches, documentation Swagger et conteneurisation Docker. Le niveau Expert fait évoluer TaskFlow vers une architecture microservices distribuée, observable et déployable en production.

| Niveau | Projet fil rouge — État de TaskFlow |
|---|---|
| ~~01 — Beginner~~ | ~~Application console basique~~ ✅ |
| ~~02 — Intermediate~~ | ~~Persistance fichier, collections, héritage~~ ✅ |
| ~~03 — Fluent~~ | ~~BDD, design patterns, tests, streams & lambdas~~ ✅ |
| ~~04 — Master~~ | ~~API REST Spring Boot, JPA/Hibernate, sécurité, Docker~~ ✅ |
| **05 — Expert** | **Microservices, messaging asynchrone, observabilité, cloud** ← tu es ici |

---

## Prérequis

- Avoir complété le niveau 04 — Master (TaskFlow v4.0 fonctionnel)
- **JDK 26** installé
- **Docker Desktop** installé et fonctionnel
- Être à l'aise avec : Spring Boot, JPA, Spring Security, JWT, Docker, tests
- Notions réseau de base (DNS, load balancing, ports)

---

## Phase 1 — Architecture microservices : décomposition

### Objectifs
- Comprendre les principes de l'architecture microservices (vs monolithe)
- Identifier les bounded contexts et décomposer TaskFlow en services
- Créer un projet multi-modules Maven
- Mettre en place la communication synchrone inter-services (REST + `RestClient` / `WebClient`)
- Gérer la configuration partagée

### Concepts clés
- Monolithe vs microservices : avantages, inconvénients, quand choisir
- Bounded context (DDD — aperçu)
- Décomposition par domaine métier
- Projet multi-modules Maven (parent POM, modules enfants)
- Communication synchrone : REST inter-services
- `RestClient` (Spring 6.1+) pour les appels HTTP
- Shared libraries vs duplication (trade-off)
- Principe d'autonomie des services (base de données par service)

### Exercices
1. **Décomposition** — Identifier les domaines : tâches, utilisateurs, notifications ; définir les responsabilités de chaque service
2. **Multi-modules** — Créer le projet parent avec les modules : `task-service`, `user-service`, `notification-service`, `common`
3. **Communication REST** — `task-service` appelle `user-service` via `RestClient` pour valider l'existence d'un utilisateur
4. **Base par service** — Chaque service a sa propre base H2/PostgreSQL ; pas de base partagée

### 🔴 Fil rouge TaskFlow — Étape 1
> Décomposer le monolithe TaskFlow v4.0 en 3 microservices :
> - **task-service** (port 8081) : CRUD tâches et projets
> - **user-service** (port 8082) : inscription, login, gestion utilisateurs, JWT
> - **notification-service** (port 8083) : envoi de notifications (email simulé / log)
>
> Chaque service a son propre `pom.xml`, sa propre base, et démarre indépendamment.

---

## Phase 2 — Spring Cloud : Gateway et Service Discovery

### Objectifs
- Mettre en place un service registry avec **Eureka Server**
- Enregistrer les microservices comme clients Eureka
- Configurer **Spring Cloud Gateway** comme point d'entrée unique
- Implémenter le load balancing client-side
- Centraliser la configuration avec **Spring Cloud Config** (aperçu)

### Concepts clés
- Service Discovery : pourquoi et comment (DNS dynamique)
- Eureka : Server et Client, heartbeat, self-preservation
- API Gateway : routing, filtres, rate limiting
- Load balancing client-side (Spring Cloud LoadBalancer)
- Route predicates et filters dans Gateway
- Single entry point : simplification pour les clients
- Configuration centralisée (Config Server + Git repo)

### Exercices
1. **Eureka Server** — Créer `discovery-server` (port 8761) avec `@EnableEurekaServer`
2. **Clients Eureka** — Enregistrer `task-service`, `user-service`, `notification-service` comme clients
3. **API Gateway** — Créer `api-gateway` (port 8080) qui route : `/api/taches/**` → task-service, `/api/auth/**` → user-service, `/api/notifications/**` → notification-service
4. **Load balancing** — Démarrer 2 instances de `task-service` et vérifier la distribution des requêtes

### 🔴 Fil rouge TaskFlow — Étape 2
> Ajouter `discovery-server` et `api-gateway`. Tous les microservices s'enregistrent dans Eureka. Le client n'accède qu'à `http://localhost:8080` (gateway). Le JWT est validé au niveau de la gateway. Les routes sont configurées dans `application.yml`.

---

## Phase 3 — Messaging asynchrone avec RabbitMQ

### Objectifs
- Comprendre la communication asynchrone (vs synchrone)
- Installer et configurer RabbitMQ (via Docker)
- Publier et consommer des messages avec Spring AMQP
- Comprendre les exchanges, queues et bindings
- Implémenter des événements métier (event-driven)

### Concepts clés
- Synchrone vs asynchrone : couplage, résilience, performance
- RabbitMQ : broker, exchange (direct, topic, fanout), queue, binding
- Spring AMQP : `RabbitTemplate`, `@RabbitListener`
- Sérialisation des messages (JSON avec Jackson)
- Événements métier : `TacheCreee`, `StatutChange`, `TacheAssignee`
- Idempotence et gestion des messages dupliqués
- Dead Letter Queue (DLQ) pour les messages en erreur
- Garanties de livraison (at-least-once, at-most-once)

### Exercices
1. **Setup RabbitMQ** — Ajouter RabbitMQ dans `docker-compose.yml`, configurer les connexions Spring
2. **Événement TacheCreee** — `task-service` publie un événement quand une tâche est créée ; `notification-service` le consomme et log une notification
3. **Événement StatutChange** — Publier quand un statut change ; consumer pour mettre à jour des compteurs et envoyer une notification
4. **Dead Letter Queue** — Configurer une DLQ pour les messages qui échouent après 3 tentatives

### 🔴 Fil rouge TaskFlow — Étape 3
> `task-service` publie des événements métier (`tache.creee`, `tache.statut.change`, `tache.supprimee`) dans RabbitMQ. `notification-service` consomme ces événements et génère des notifications (log + stockage). La communication asynchrone remplace les appels REST pour les notifications.

---

## Phase 4 — Résilience et tolérance aux pannes

### Objectifs
- Comprendre les patterns de résilience (Circuit Breaker, Retry, Timeout, Bulkhead, Fallback)
- Implémenter la résilience avec **Resilience4j**
- Gérer les pannes partielles (un service down ≠ tout down)
- Configurer des fallbacks dégradés
- Tester la résilience (chaos engineering — aperçu)

### Concepts clés
- Circuit Breaker : états (CLOSED, OPEN, HALF_OPEN), seuils, durée
- Retry : nombre de tentatives, backoff exponentiel
- Timeout : éviter l'attente infinie
- Bulkhead : isolation des ressources (limiter les threads par service)
- Fallback : réponse dégradée quand un service est indisponible
- `@CircuitBreaker`, `@Retry`, `@TimeLimiter` (annotations Resilience4j)
- Health checks et readiness probes

### Exercices
1. **Circuit Breaker** — Protéger l'appel `task-service` → `user-service` avec `@CircuitBreaker` ; fallback retournant un utilisateur "inconnu"
2. **Retry** — Configurer 3 tentatives avec backoff exponentiel sur les appels inter-services
3. **Timeout** — Limiter chaque appel inter-service à 2 secondes
4. **Test de panne** — Arrêter `user-service`, vérifier que `task-service` continue de fonctionner en mode dégradé

### 🔴 Fil rouge TaskFlow — Étape 4
> Tous les appels inter-services sont protégés par Resilience4j (Circuit Breaker + Retry + Timeout). Si `user-service` tombe, `task-service` fonctionne en mode dégradé. Si RabbitMQ tombe, les messages sont mis en file locale et renvoyés au redémarrage.

---

## Phase 5 — Observabilité : logs, métriques, traces

### Objectifs
- Comprendre les 3 piliers de l'observabilité (logs, métriques, traces)
- Centraliser les logs avec **ELK** (Elasticsearch, Logstash, Kibana) ou Loki
- Collecter les métriques avec **Micrometer** + **Prometheus** et visualiser avec **Grafana**
- Implémenter le tracing distribué avec **Micrometer Tracing** (ex-Spring Cloud Sleuth) + **Zipkin**
- Corréler les logs entre services (traceId, spanId)

### Concepts clés
- Structured logging (JSON) avec Logback
- MDC (Mapped Diagnostic Context) pour la corrélation
- Micrometer : façade de métriques (compteurs, jauges, histogrammes, timers)
- Spring Boot Actuator : endpoints `/actuator/health`, `/actuator/metrics`, `/actuator/prometheus`
- Prometheus : scraping de métriques, PromQL
- Grafana : dashboards, alertes
- Tracing distribué : trace, span, propagation de contexte
- Zipkin : visualisation des traces

### Exercices
1. **Actuator + Prometheus** — Activer Spring Actuator, exposer `/actuator/prometheus`, configurer Prometheus pour scraper les métriques
2. **Dashboard Grafana** — Créer un dashboard avec : requêtes/s, latence p50/p95/p99, erreurs, tâches créées par minute
3. **Tracing** — Configurer Micrometer Tracing + Zipkin ; suivre une requête de la gateway → task-service → user-service → RabbitMQ
4. **Logs structurés** — Configurer Logback en JSON avec traceId/spanId ; centraliser dans ELK ou Loki

### 🔴 Fil rouge TaskFlow — Étape 5
> Observabilité complète ajoutée au `docker-compose.yml` :
> - **Prometheus + Grafana** : dashboard avec métriques clés de chaque service
> - **Zipkin** : tracing distribué entre gateway, services et messaging
> - **Logs structurés** JSON avec corrélation traceId
> - Chaque service expose `/actuator/health` et `/actuator/prometheus`

---

## Phase 6 — Performance : caching avec Redis et optimisation

### Objectifs
- Comprendre les stratégies de cache (cache-aside, write-through, write-behind)
- Implémenter le caching avec **Redis** et Spring Cache (`@Cacheable`, `@CacheEvict`, `@CachePut`)
- Optimiser les requêtes JPA (N+1, projections, fetch join)
- Profiler l'application (heap, threads, GC)
- Programmer de manière réactive avec **WebFlux** (aperçu)

### Concepts clés
- Redis : in-memory data store, types de données, TTL
- Spring Cache abstraction : `@Cacheable`, `@CacheEvict`, `@CachePut`
- Cache invalidation (le problème le plus dur en informatique)
- Problème N+1 en JPA : détection et solutions (`@EntityGraph`, `JOIN FETCH`)
- Projections JPA (interface-based, class-based)
- Indexation BDD pour les requêtes fréquentes
- JVM profiling : heap dump, thread dump, GC logs (aperçu)
- WebFlux et programmation réactive (Mono, Flux — introduction)

### Exercices
1. **Redis setup** — Ajouter Redis dans `docker-compose.yml`, configurer Spring Cache avec Redis
2. **Cache des tâches** — `@Cacheable` sur `findById`, `@CacheEvict` sur update/delete ; TTL de 5 minutes
3. **Optimisation N+1** — Identifier et corriger les problèmes N+1 avec `@EntityGraph` sur la relation Projet → Tâches
4. **Benchmark** — Mesurer les temps de réponse avant/après cache avec des métriques Micrometer

### 🔴 Fil rouge TaskFlow — Étape 6
> Redis est intégré comme cache dans `task-service`. Les requêtes fréquentes (détail tâche, liste par projet) sont cachées. Les problèmes N+1 sont corrigés. Le dashboard Grafana montre l'impact du cache (hit ratio, latence avant/après).

---

## Phase 7 — CI/CD et déploiement

### Objectifs
- Comprendre les principes CI/CD (Continuous Integration / Continuous Deployment)
- Configurer un pipeline **GitHub Actions** (build, test, analyse, deploy)
- Écrire des tests d'intégration avec **Testcontainers** (PostgreSQL, RabbitMQ, Redis)
- Découvrir **Kubernetes** (concepts : pod, service, deployment, configmap, secret)
- Déployer sur Kubernetes (Minikube ou cloud provider)

### Concepts clés
- CI : build automatique, tests, analyse de code à chaque push
- CD : déploiement automatique après validation
- GitHub Actions : workflow, jobs, steps, secrets
- Testcontainers : conteneurs Docker éphémères pour les tests d'intégration
- Kubernetes : orchestration de conteneurs à grande échelle
- Pod, Service, Deployment, ConfigMap, Secret, Ingress
- Helm charts (aperçu) : packaging Kubernetes
- Environments : dev, staging, production

### Exercices
1. **GitHub Actions** — Pipeline : checkout → build → test → build Docker image → push vers registry
2. **Testcontainers** — Tests d'intégration avec PostgreSQL et RabbitMQ dans des conteneurs Testcontainers
3. **Kubernetes manifests** — Écrire les fichiers YAML : Deployment, Service, ConfigMap, Secret pour chaque microservice
4. **Déploiement Minikube** — Déployer tout le cluster TaskFlow sur Minikube, tester depuis l'extérieur via Ingress

### 🔴 Fil rouge TaskFlow — Étape 7
> Pipeline CI/CD GitHub Actions complet : chaque push déclenche build → test (avec Testcontainers) → build Docker → push. Manifestes Kubernetes prêts pour le déploiement. Le cluster peut tourner sur Minikube avec tous les services + infra (PostgreSQL, RabbitMQ, Redis).

---

## Phase 8 — Projet final Expert : TaskFlow v5.0

### Objectifs
- Consolider tous les acquis du niveau Expert
- Produire une architecture microservices distribuée, résiliente, observable et déployable
- Documentation d'architecture complète

### Architecture TaskFlow v5.0

```
                         ┌─────────────┐
                         │   Client    │
                         │ (Postman /  │
                         │  Frontend)  │
                         └──────┬──────┘
                                │
                         ┌──────▼──────┐
                         │ API Gateway │ :8080
                         │   (JWT +    │
                         │   Routing)  │
                         └──┬───┬───┬──┘
                ┌───────────┘   │   └───────────┐
                ▼               ▼               ▼
        ┌───────────┐   ┌───────────┐   ┌───────────────┐
        │   Task    │   │   User    │   │ Notification  │
        │  Service  │   │  Service  │   │   Service     │
        │  :8081    │   │  :8082    │   │   :8083       │
        └─────┬─────┘   └─────┬─────┘   └───────┬───────┘
              │               │                 │
              ▼               ▼                 ▼
        ┌──────────┐   ┌──────────┐      (consomme les
        │ Task DB  │   │ User DB  │       événements)
        │ Postgres │   │ Postgres │
        └──────────┘   └──────────┘
              │                                 ▲
              └────────► RabbitMQ ──────────────┘
                        (événements)

        ┌──────────────── Infra ────────────────────┐
        │  Eureka · Redis · Prometheus · Grafana     │
        │  Zipkin · ELK/Loki                         │
        └────────────────────────────────────────────┘
```

### Services et ports

| Service | Port | Responsabilité |
|---|---|---|
| `api-gateway` | 8080 | Routing, JWT validation, rate limiting |
| `discovery-server` | 8761 | Service registry Eureka |
| `task-service` | 8081 | CRUD tâches et projets, événements |
| `user-service` | 8082 | Auth, gestion utilisateurs, JWT |
| `notification-service` | 8083 | Consommation événements, notifications |

### Structure du projet attendue

```
05-expert/
├── program.md
└── taskflow-v5/
    ├── pom.xml                          ← Parent POM
    ├── docker-compose.yml               ← Tous les services + infra
    ├── docker-compose.infra.yml         ← Infra seule (Postgres, RabbitMQ, Redis...)
    ├── README.md
    ├── .github/
    │   └── workflows/
    │       └── ci-cd.yml                ← Pipeline GitHub Actions
    ├── k8s/
    │   ├── task-service.yml
    │   ├── user-service.yml
    │   ├── notification-service.yml
    │   ├── api-gateway.yml
    │   ├── discovery-server.yml
    │   └── infra/
    │       ├── postgres.yml
    │       ├── rabbitmq.yml
    │       └── redis.yml
    ├── discovery-server/
    │   ├── pom.xml
    │   ├── Dockerfile
    │   └── src/...
    ├── api-gateway/
    │   ├── pom.xml
    │   ├── Dockerfile
    │   └── src/...
    ├── task-service/
    │   ├── pom.xml
    │   ├── Dockerfile
    │   └── src/
    │       ├── main/java/com/taskflow/task/
    │       │   ├── TaskServiceApplication.java
    │       │   ├── controller/
    │       │   ├── model/
    │       │   ├── repository/
    │       │   ├── service/
    │       │   ├── event/              ← Événements publiés
    │       │   ├── client/             ← RestClient vers user-service
    │       │   ├── config/
    │       │   └── exception/
    │       ├── main/resources/
    │       └── test/                   ← Tests + Testcontainers
    ├── user-service/
    │   ├── pom.xml
    │   ├── Dockerfile
    │   └── src/
    │       └── main/java/com/taskflow/user/
    │           ├── UserServiceApplication.java
    │           ├── controller/
    │           ├── model/
    │           ├── repository/
    │           ├── service/
    │           ├── security/
    │           └── exception/
    ├── notification-service/
    │   ├── pom.xml
    │   ├── Dockerfile
    │   └── src/
    │       └── main/java/com/taskflow/notification/
    │           ├── NotificationServiceApplication.java
    │           ├── consumer/           ← RabbitMQ listeners
    │           ├── model/
    │           ├── repository/
    │           └── service/
    └── common/
        ├── pom.xml
        └── src/
            └── main/java/com/taskflow/common/
                ├── dto/                ← DTOs partagés
                └── event/              ← Classes d'événements partagées
```

### Critères de validation
- [ ] Architecture microservices fonctionnelle (3 services métier + gateway + discovery)
- [ ] Chaque service a sa propre base de données (database-per-service)
- [ ] Communication asynchrone via RabbitMQ (événements métier)
- [ ] Service Discovery avec Eureka
- [ ] API Gateway avec routing et validation JWT centralisée
- [ ] Résilience : Circuit Breaker, Retry, Timeout avec Resilience4j
- [ ] Mode dégradé fonctionnel (un service down ne casse pas tout)
- [ ] Observabilité complète : métriques (Prometheus/Grafana), tracing (Zipkin), logs structurés
- [ ] Cache Redis sur les requêtes fréquentes
- [ ] Problèmes N+1 JPA corrigés
- [ ] Tests d'intégration avec Testcontainers
- [ ] Pipeline CI/CD GitHub Actions (build → test → Docker)
- [ ] Manifestes Kubernetes pour le déploiement
- [ ] `docker-compose up` lance l'ensemble du système
- [ ] README complet : architecture, setup, endpoints, commandes

### Bonus (optionnel)
- Apache Kafka en alternative à RabbitMQ
- Event Sourcing / CQRS sur le domaine tâches
- Frontend React/Angular consommant l'API
- Spring Cloud Config Server pour la configuration centralisée
- Helm charts pour le déploiement Kubernetes
- Monitoring des alertes dans Grafana (Alertmanager)
- Rate limiting dans la Gateway (Redis-based)
- Saga pattern pour les transactions distribuées

---

## Récapitulatif de progression

| Phase | Thème | Fil rouge TaskFlow |
|---|---|---|
| 1 | Architecture microservices, décomposition | 3 services + communication REST |
| 2 | Spring Cloud Gateway, Eureka | Gateway unique, service discovery |
| 3 | RabbitMQ, événements métier | Messaging asynchrone événementiel |
| 4 | Resilience4j, tolérance aux pannes | Circuit Breaker, mode dégradé |
| 5 | Observabilité (Prometheus, Grafana, Zipkin) | Métriques, tracing, logs structurés |
| 6 | Redis, optimisation JPA | Cache, N+1, performance |
| 7 | CI/CD, Testcontainers, Kubernetes | Pipeline, tests infra, déploiement |
| 8 | **Projet final v5.0** | **Microservices distribués en production** |

---

## Récapitulatif global du parcours

| Niveau | Version | De → Vers |
|---|---|---|
| 01 — Beginner | v1.0 | Zéro → Application console structurée |
| 02 — Intermediate | v2.0 | Console → OOP complète + persistance fichier |
| 03 — Fluent | v3.0 | Fichier → Maven + BDD + tests + patterns |
| 04 — Master | v4.0 | Console → API REST Spring Boot + Docker |
| 05 — Expert | v5.0 | Monolithe → Microservices distribués en production |

> 🎓 **Félicitations !** Tu as parcouru le chemin complet de débutant Java à architecte de systèmes distribués. TaskFlow est passé d'un simple `System.out.println` à un écosystème de microservices résilients, observables et déployables dans le cloud.