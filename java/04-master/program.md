# Java — Niveau 04 : Master

## Rappel du fil rouge : **TaskFlow**

> À l'issue du niveau Fluent, TaskFlow v3.0 est un projet Maven avec base de données SQLite (JDBC/DAO), design patterns, tests JUnit 5, et code idiomatique (streams, lambdas). Le niveau Master transforme TaskFlow en application web professionnelle avec API REST, ORM et conteneurisation.

| Niveau | Projet fil rouge — État de TaskFlow |
|---|---|
| ~~01 — Beginner~~ | ~~Application console basique~~ ✅ |
| ~~02 — Intermediate~~ | ~~Persistance fichier, collections, héritage~~ ✅ |
| ~~03 — Fluent~~ | ~~BDD, design patterns, tests, streams & lambdas~~ ✅ |
| **04 — Master** | **API REST Spring Boot, JPA/Hibernate, sécurité, Docker** ← tu es ici |
| 05 — Expert | Microservices, messaging asynchrone, observabilité, cloud |

---

## Prérequis

- Avoir complété le niveau 03 — Fluent (TaskFlow v3.0 fonctionnel)
- **JDK 26** installé
- **Docker Desktop** installé
- Être à l'aise avec : Maven, JDBC, JUnit 5, design patterns, streams, lambdas
- Notions HTTP de base (verbes, codes de statut, headers)

---

## Phase 1 — Spring Boot : premiers pas

### Objectifs
- Comprendre l'écosystème Spring et la philosophie Spring Boot (convention over configuration, auto-configuration)
- Créer un projet Spring Boot avec Spring Initializr
- Maîtriser la structure d'un projet Spring Boot
- Comprendre l'injection de dépendances (IoC) et les annotations (`@Component`, `@Service`, `@Repository`, `@Autowired`)
- Configurer l'application (`application.properties` / `application.yml`)

### Concepts clés
- Inversion of Control (IoC) et conteneur Spring
- Beans et cycle de vie
- Annotations stéréotypes (`@Component`, `@Service`, `@Repository`, `@Controller`)
- `@Autowired`, injection par constructeur (recommandé)
- Profils (`@Profile`, `spring.profiles.active`)
- `application.yml` : configuration hiérarchique
- Spring Boot DevTools (rechargement automatique)

### Exercices
1. **Initialisation** — Créer un projet Spring Boot via start.spring.io avec les starters : Web, JPA, H2, Validation, DevTools
2. **Premier Bean** — Migrer `GestionnaireTaches` en `@Service` injecté via constructeur
3. **Configuration** — Externaliser les paramètres (nom de l'app, version, limites) dans `application.yml`
4. **Profils** — Créer un profil `dev` (H2 en mémoire) et `prod` (PostgreSQL) avec des fichiers `application-{profil}.yml`

### 🔴 Fil rouge TaskFlow — Étape 1
> Créer le projet Spring Boot `taskflow-api`. Migrer les classes `model`, `service` et `exception` du v3.0. Les services sont des beans Spring injectés par constructeur. L'application démarre avec `mvn spring-boot:run`.

---

## Phase 2 — API REST avec Spring Web

### Objectifs
- Créer des contrôleurs REST (`@RestController`, `@RequestMapping`)
- Maîtriser les annotations de mapping (`@GetMapping`, `@PostMapping`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping`)
- Gérer les paramètres (`@PathVariable`, `@RequestParam`, `@RequestBody`)
- Retourner des réponses HTTP appropriées (`ResponseEntity`, codes de statut)
- Structurer les DTOs (Data Transfer Objects)

### Concepts clés
- Architecture REST : ressources, verbes HTTP, codes de statut
- Sérialisation JSON automatique (Jackson)
- DTO vs Entité : séparation des représentations
- `ResponseEntity<T>` pour contrôler statut + headers + body
- Pagination et tri (`Pageable`, `Page<T>`)
- Conventions REST : nommage des URIs, HATEOAS (aperçu)

### Exercices
1. **CRUD Controller** — Créer `TacheController` avec les endpoints : `GET /api/taches`, `GET /api/taches/{id}`, `POST /api/taches`, `PUT /api/taches/{id}`, `DELETE /api/taches/{id}`
2. **DTOs** — Créer `TacheRequestDto` (entrée) et `TacheResponseDto` (sortie) ; mapper entre DTO et entité
3. **Filtrage** — `GET /api/taches?statut=EN_COURS&priorite=HAUTE&type=BUG` avec `@RequestParam`
4. **Pagination** — `GET /api/taches?page=0&size=10&sort=priorite,desc` avec `Pageable`

### 🔴 Fil rouge TaskFlow — Étape 2
> Exposer l'API REST complète pour les tâches. Tous les endpoints retournent des DTOs. Le filtrage par statut, priorité et type fonctionne. La pagination est supportée. Tester avec curl ou Postman.

---

## Phase 3 — JPA / Hibernate

### Objectifs
- Comprendre l'ORM (Object-Relational Mapping) et JPA
- Annoter les entités (`@Entity`, `@Table`, `@Id`, `@GeneratedValue`, `@Column`, `@Enumerated`)
- Mapper l'héritage (`@Inheritance` : SINGLE_TABLE, JOINED, TABLE_PER_CLASS)
- Utiliser Spring Data JPA (`JpaRepository`, méthodes dérivées, `@Query`)
- Gérer les relations (`@OneToMany`, `@ManyToOne`, `@ManyToMany`)

### Concepts clés
- Entité JPA vs POJO
- Stratégies de génération d'ID (`IDENTITY`, `SEQUENCE`, `UUID`)
- Mapping d'héritage : SINGLE_TABLE (avec `@DiscriminatorColumn`) vs JOINED
- Spring Data JPA : méthodes dérivées (`findByStatutAndPriorite`)
- JPQL et `@Query` pour les requêtes personnalisées
- Fetch strategies : `LAZY` vs `EAGER`
- `@Transactional` et gestion des transactions
- Auditing (`@CreatedDate`, `@LastModifiedDate`)

### Exercices
1. **Entités JPA** — Annoter `Tache`, `Bug`, `Feature`, `Story` comme entités JPA avec héritage SINGLE_TABLE
2. **Repository Spring Data** — Créer `TacheJpaRepository extends JpaRepository<Tache, Long>` avec méthodes dérivées
3. **Requêtes custom** — `@Query("SELECT t FROM Tache t WHERE t.echeance < :date AND t.statut <> 'TERMINEE'")` pour les tâches en retard
4. **Relations** — Ajouter une entité `Projet` avec relation `@OneToMany` vers `Tache` ; un projet contient plusieurs tâches

### 🔴 Fil rouge TaskFlow — Étape 3
> Remplacer le DAO JDBC par Spring Data JPA. Les entités sont annotées avec héritage SINGLE_TABLE. Ajouter l'entité `Projet` (un projet a N tâches). Le repository utilise des méthodes dérivées et des `@Query`. Base H2 en dev, PostgreSQL en prod.

---

## Phase 4 — Validation et gestion d'erreurs

### Objectifs
- Valider les entrées avec Bean Validation (`@NotNull`, `@NotBlank`, `@Size`, `@Min`, `@Max`, `@Pattern`, `@Valid`)
- Créer des validateurs personnalisés (`@Constraint`, `ConstraintValidator`)
- Centraliser la gestion des erreurs avec `@RestControllerAdvice` et `@ExceptionHandler`
- Retourner des réponses d'erreur structurées et cohérentes (RFC 7807 Problem Details)

### Concepts clés
- Bean Validation (JSR 380) et Hibernate Validator
- Validation en cascade (`@Valid` sur les objets imbriqués)
- Groupes de validation (aperçu)
- `@RestControllerAdvice` : gestionnaire global d'exceptions
- `ProblemDetail` (Spring 6+) pour les réponses d'erreur standardisées
- Différence validation métier vs validation technique

### Exercices
1. **Validation DTO** — Annoter `TacheRequestDto` : titre `@NotBlank @Size(max=200)`, priorité `@NotNull`, description `@Size(max=2000)`
2. **Validateur custom** — Créer `@EcheanceFuture` qui vérifie que la date d'échéance est dans le futur
3. **Error Handler** — `@RestControllerAdvice` qui gère : `MethodArgumentNotValidException`, `TacheNotFoundException`, `TransitionStatutException`, `Exception` générique
4. **Réponse d'erreur** — Format uniforme : `{ "type": "...", "title": "...", "status": 404, "detail": "...", "timestamp": "..." }`

### 🔴 Fil rouge TaskFlow — Étape 4
> Tous les DTOs sont validés avec Bean Validation. Un `@RestControllerAdvice` centralise la gestion d'erreurs avec des `ProblemDetail` standardisés. Aucune stack trace n'est exposée au client. Les erreurs de validation retournent un 400 avec la liste des champs invalides.

---

## Phase 5 — Tests dans Spring Boot

### Objectifs
- Tester les couches séparément : unit, slice, integration
- Tests unitaires des services (Mockito : `@Mock`, `@InjectMocks`, `when/thenReturn`, `verify`)
- Tests de la couche web (`@WebMvcTest`, `MockMvc`)
- Tests d'intégration (`@SpringBootTest`, `@AutoConfigureMockMvc`)
- Tests de la couche repository (`@DataJpaTest`)

### Concepts clés
- Pyramide des tests appliquée à Spring Boot
- Mockito : mocks, stubs, verification
- `MockMvc` : simuler des requêtes HTTP sans serveur
- `@WebMvcTest` : slice test du contrôleur (mock des services)
- `@DataJpaTest` : slice test du repository (H2 en mémoire)
- `@SpringBootTest` : test d'intégration complet
- TestContainers (aperçu) pour tester avec une vraie BDD

### Exercices
1. **Tests service** — Tester `GestionnaireTaches` avec Mockito : mock du repository, vérifier les appels et les résultats
2. **Tests controller** — `@WebMvcTest(TacheController.class)` : tester GET, POST, PUT, DELETE, validation, erreurs 404
3. **Tests repository** — `@DataJpaTest` : tester les méthodes dérivées et les `@Query` avec H2
4. **Test intégration** — `@SpringBootTest` : tester un scénario complet (créer un projet, ajouter des tâches, filtrer)

### 🔴 Fil rouge TaskFlow — Étape 5
> Couverture de tests complète :
> - Tests unitaires services avec Mockito
> - Tests `@WebMvcTest` pour chaque endpoint du contrôleur
> - Tests `@DataJpaTest` pour le repository
> - Au moins 1 test d'intégration `@SpringBootTest` end-to-end
> - Minimum 50 tests passants avec `mvn test`

---

## Phase 6 — Spring Security : authentification et autorisation

### Objectifs
- Comprendre les concepts : authentification vs autorisation
- Configurer Spring Security (SecurityFilterChain)
- Implémenter l'authentification JWT (JSON Web Token)
- Gérer les rôles et permissions (`ROLE_USER`, `ROLE_ADMIN`)
- Sécuriser les endpoints (`@PreAuthorize`, `@Secured`)

### Concepts clés
- Filtre de sécurité (SecurityFilterChain)
- `UserDetails`, `UserDetailsService`
- JWT : structure (header, payload, signature), génération, validation
- Stateless authentication (pas de session serveur)
- CORS (Cross-Origin Resource Sharing)
- Password encoding (`BCryptPasswordEncoder`)
- Principe du moindre privilège

### Exercices
1. **Configuration de base** — Configurer `SecurityFilterChain` : endpoints publics (`/api/auth/**`) et protégés (`/api/taches/**`)
2. **Entité Utilisateur** — Créer `Utilisateur` (email, mot de passe hashé, rôle) avec `UserDetailsService`
3. **JWT** — Implémenter `JwtService` : génération du token à la connexion, validation sur chaque requête via un filtre
4. **Autorisation** — `ROLE_USER` peut CRUD ses propres tâches ; `ROLE_ADMIN` peut tout voir et supprimer

### 🔴 Fil rouge TaskFlow — Étape 6
> TaskFlow est sécurisé : inscription (`POST /api/auth/register`), connexion (`POST /api/auth/login`) retournant un JWT. Chaque tâche appartient à un utilisateur. Un utilisateur ne voit que ses tâches. L'admin voit tout. Les endpoints non authentifiés retournent 401.

---

## Phase 7 — Documentation API et conteneurisation Docker

### Objectifs
- Documenter l'API avec OpenAPI 3 / Swagger UI (`springdoc-openapi`)
- Annoter les contrôleurs (`@Operation`, `@ApiResponse`, `@Tag`, `@Schema`)
- Comprendre Docker : images, conteneurs, Dockerfile, docker-compose
- Conteneuriser l'application Spring Boot
- Orchestrer avec docker-compose (app + base de données)

### Concepts clés
- OpenAPI 3.0 : spécification standard pour les API REST
- Swagger UI : interface interactive pour tester l'API
- Docker : image (blueprint) vs conteneur (instance running)
- Dockerfile multi-stage (build + run)
- `docker-compose.yml` : orchestration multi-conteneurs
- Variables d'environnement pour la configuration
- Volumes pour la persistance des données

### Exercices
1. **Springdoc** — Ajouter `springdoc-openapi-starter-webmvc-ui`, accéder à Swagger UI sur `/swagger-ui.html`
2. **Annotations** — Documenter chaque endpoint avec `@Operation`, `@ApiResponse`, les DTOs avec `@Schema`
3. **Dockerfile** — Écrire un Dockerfile multi-stage : `mvn package` dans un stage build, `java -jar` dans un stage runtime léger
4. **Docker Compose** — `docker-compose.yml` avec 2 services : `taskflow-api` (l'app) + `taskflow-db` (PostgreSQL)

### 🔴 Fil rouge TaskFlow — Étape 7
> L'API est documentée et testable via Swagger UI. L'application est conteneurisée : `docker-compose up` lance TaskFlow + PostgreSQL. Les variables d'environnement configurent la connexion BDD, le secret JWT, etc.

---

## Phase 8 — Projet final Master : TaskFlow v4.0

### Objectifs
- Consolider tous les acquis du niveau Master
- Produire une API REST professionnelle, sécurisée, testée et conteneurisée
- Documentation complète (README, Swagger, architecture)

### API endpoints attendus pour TaskFlow v4.0

```
Auth
  POST   /api/auth/register          → Inscription
  POST   /api/auth/login             → Connexion (retourne JWT)

Tâches (authentifié)
  GET    /api/taches                  → Lister (filtres, pagination, tri)
  GET    /api/taches/{id}             → Détail
  POST   /api/taches                  → Créer (Bug, Feature ou Story)
  PUT    /api/taches/{id}             → Modifier
  PATCH  /api/taches/{id}/statut      → Changer le statut
  DELETE /api/taches/{id}             → Supprimer

Projets (authentifié)
  GET    /api/projets                 → Lister ses projets
  POST   /api/projets                 → Créer un projet
  GET    /api/projets/{id}/taches     → Tâches d'un projet

Export
  GET    /api/taches/export/csv       → Exporter en CSV
  GET    /api/taches/rapport          → Rapport JSON complet

Admin (ROLE_ADMIN)
  GET    /api/admin/utilisateurs      → Lister les utilisateurs
  GET    /api/admin/statistiques      → Statistiques globales
```

### Structure du projet attendue

```
04-master/
├── program.md
└── taskflow-v4/
    ├── pom.xml
    ├── Dockerfile
    ├── docker-compose.yml
    ├── README.md
    └── src/
        ├── main/
        │   ├── java/
        │   │   └── com/taskflow/
        │   │       ├── TaskFlowApplication.java
        │   │       ├── config/
        │   │       │   ├── SecurityConfig.java
        │   │       │   └── OpenApiConfig.java
        │   │       ├── model/
        │   │       │   ├── Tache.java
        │   │       │   ├── Bug.java
        │   │       │   ├── Feature.java
        │   │       │   ├── Story.java
        │   │       │   ├── Projet.java
        │   │       │   ├── Utilisateur.java
        │   │       │   ├── Role.java
        │   │       │   ├── Priorite.java
        │   │       │   └── Statut.java
        │   │       ├── repository/
        │   │       │   ├── TacheRepository.java
        │   │       │   ├── ProjetRepository.java
        │   │       │   └── UtilisateurRepository.java
        │   │       ├── service/
        │   │       │   ├── TacheService.java
        │   │       │   ├── ProjetService.java
        │   │       │   ├── AuthService.java
        │   │       │   └── ExportService.java
        │   │       ├── controller/
        │   │       │   ├── TacheController.java
        │   │       │   ├── ProjetController.java
        │   │       │   ├── AuthController.java
        │   │       │   └── AdminController.java
        │   │       ├── dto/
        │   │       │   ├── TacheRequestDto.java
        │   │       │   ├── TacheResponseDto.java
        │   │       │   ├── ProjetDto.java
        │   │       │   ├── AuthRequestDto.java
        │   │       │   └── AuthResponseDto.java
        │   │       ├── security/
        │   │       │   ├── JwtService.java
        │   │       │   ├── JwtAuthFilter.java
        │   │       │   └── UserDetailsServiceImpl.java
        │   │       ├── exception/
        │   │       │   ├── GlobalExceptionHandler.java
        │   │       │   ├── TacheNotFoundException.java
        │   │       │   └── ...
        │   │       └── mapper/
        │   │           ├── TacheMapper.java
        │   │           └── ProjetMapper.java
        │   └── resources/
        │       ├── application.yml
        │       ├── application-dev.yml
        │       └── application-prod.yml
        └── test/
            └── java/
                └── com/taskflow/
                    ├── controller/
                    │   └── TacheControllerTest.java
                    ├── service/
                    │   └── TacheServiceTest.java
                    ├── repository/
                    │   └── TacheRepositoryTest.java
                    └── integration/
                        └── TaskFlowIntegrationTest.java
```

### Critères de validation
- [ ] Application Spring Boot démarrant sans erreur
- [ ] API REST complète (CRUD tâches + projets + auth)
- [ ] JPA/Hibernate avec héritage SINGLE_TABLE et relations (@OneToMany, @ManyToOne)
- [ ] Bean Validation sur tous les DTOs d'entrée
- [ ] Gestion d'erreurs centralisée avec ProblemDetail
- [ ] Authentification JWT fonctionnelle (register, login, token sur chaque requête)
- [ ] Autorisation par rôles (USER voit ses tâches, ADMIN voit tout)
- [ ] Swagger UI accessible et documentant tous les endpoints
- [ ] Docker Compose fonctionnel (app + PostgreSQL)
- [ ] Minimum 50 tests passants (unit + slice + intégration)
- [ ] Profils dev (H2) et prod (PostgreSQL)
- [ ] README avec instructions de démarrage, endpoints et architecture

### Bonus (optionnel)
- MapStruct pour le mapping DTO ↔ Entité
- Flyway ou Liquibase pour les migrations de schéma BDD
- Rate limiting sur les endpoints publics
- Refresh Token pour renouveler le JWT
- Cache avec `@Cacheable` (Spring Cache)
- Health check et métriques avec Spring Actuator

---

## Récapitulatif de progression

| Phase | Thème | Fil rouge TaskFlow |
|---|---|---|
| 1 | Spring Boot, IoC, configuration | Migration vers Spring Boot |
| 2 | API REST, DTOs, pagination | Endpoints CRUD complets |
| 3 | JPA/Hibernate, Spring Data | ORM, entité Projet, relations |
| 4 | Bean Validation, error handling | Validation DTOs, ProblemDetail |
| 5 | Tests Spring (Mockito, MockMvc, DataJpaTest) | 50+ tests multi-couches |
| 6 | Spring Security, JWT | Auth, rôles, sécurisation endpoints |
| 7 | OpenAPI/Swagger, Docker | Documentation API, conteneurisation |
| 8 | **Projet final v4.0** | **API REST sécurisée et conteneurisée** |

---

## Transition vers le niveau 05 — Expert

À l'issue de ce niveau, tu as une API REST Spring Boot complète, sécurisée, testée et conteneurisée. Voici ce qui t'attend :

- **Architecture microservices** : décomposer TaskFlow en services indépendants
- **Messaging asynchrone** avec RabbitMQ ou Kafka
- **API Gateway** et service discovery (Spring Cloud Gateway, Eureka)
- **Observabilité** : logging centralisé (ELK), métriques (Prometheus/Grafana), tracing distribué (Micrometer Tracing)
- **Performance** : caching avancé (Redis), programmation réactive (WebFlux — aperçu)
- **CI/CD** et déploiement cloud (GitHub Actions, Kubernetes — aperçu)

> TaskFlow v5.0 sera décomposé en microservices (task-service, user-service, notification-service) communiquant via messaging, avec observabilité complète et déploiement orchestré.