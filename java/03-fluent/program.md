# Java — Niveau 03 : Fluent

## Rappel du fil rouge : **TaskFlow**

> À l'issue du niveau Intermediate, TaskFlow v2.0 est une application console multi-packages avec héritage (Bug/Feature/Story), persistance CSV, exceptions métier, dates et Optional. Le niveau Fluent fait passer TaskFlow à un véritable projet professionnel : build tool, base de données, tests, et code idiomatique moderne.

| Niveau | Projet fil rouge — État de TaskFlow |
|---|---|
| ~~01 — Beginner~~ | ~~Application console basique~~ ✅ |
| ~~02 — Intermediate~~ | ~~Persistance fichier, collections, héritage~~ ✅ |
| **03 — Fluent** | **BDD, design patterns, tests unitaires, streams & lambdas** ← tu es ici |
| 04 — Master | API REST Spring Boot, JPA/Hibernate, sécurité, Docker |
| 05 — Expert | Microservices, messaging asynchrone, observabilité, cloud |

---

## Prérequis

- Avoir complété le niveau 02 — Intermediate (TaskFlow v2.0 fonctionnel)
- **JDK 26** installé
- Être à l'aise avec : héritage, interfaces, collections, I/O fichiers, exceptions, Optional, java.time

---

## Phase 1 — Build tool : Maven

### Objectifs
- Comprendre le rôle d'un build tool (compilation, dépendances, tests, packaging)
- Créer un projet Maven avec la structure standard
- Configurer le `pom.xml` (groupId, artifactId, version, propriétés, dépendances)
- Utiliser le cycle de vie Maven (`compile`, `test`, `package`, `install`)
- Gérer les dépendances externes via Maven Central

### Concepts clés
- Convention over configuration
- Structure standard : `src/main/java`, `src/test/java`, `src/main/resources`
- Coordonnées Maven (GAV : groupId, artifactId, version)
- Scopes de dépendance (`compile`, `test`, `runtime`, `provided`)
- Plugins Maven (compiler-plugin, surefire-plugin)
- Fichier `.gitignore` pour Maven (`target/`)

### Exercices
1. **Création du projet** — Initialiser un projet Maven pour TaskFlow avec `mvn archetype:generate` ou manuellement
2. **Migration** — Déplacer tout le code de TaskFlow v2.0 dans la structure Maven
3. **Dépendance** — Ajouter une dépendance (ex: `commons-lang3`) et utiliser `StringUtils` dans le code
4. **Build complet** — Compiler, packager en JAR exécutable et lancer TaskFlow depuis le JAR

### 🔴 Fil rouge TaskFlow — Étape 1
> Migrer TaskFlow v2.0 vers un projet Maven. Le projet compile et s'exécute via `mvn compile exec:java`. Le JAR produit par `mvn package` est exécutable.

---

## Phase 2 — Expressions lambda et interfaces fonctionnelles

### Objectifs
- Comprendre les interfaces fonctionnelles (`@FunctionalInterface`)
- Écrire des expressions lambda (syntaxe courte et longue)
- Utiliser les interfaces fonctionnelles du JDK (`Predicate`, `Function`, `Consumer`, `Supplier`, `UnaryOperator`)
- Maîtriser les références de méthode (`::`)
- Combiner des predicats (`and`, `or`, `negate`)

### Concepts clés
- Lambda = implémentation inline d'une interface fonctionnelle
- Capture de variables (effectively final)
- `Predicate<T>` pour le filtrage
- `Function<T, R>` pour la transformation
- `Consumer<T>` pour les effets de bord
- `Supplier<T>` pour la création paresseuse
- Composition fonctionnelle (`andThen`, `compose`)

### Exercices
1. **Filtrage par lambda** — Réécrire le filtrage des tâches avec `Predicate<Tache>` au lieu de boucles if/else
2. **Transformation** — Utiliser `Function<Tache, String>` pour extraire différentes représentations textuelles
3. **Références de méthode** — Remplacer les lambdas simples par des références (`Tache::getTitre`, `System.out::println`)
4. **Composition** — Combiner des `Predicate<Tache>` : tâches urgentes ET en retard, tâches de type Bug OU priorité critique

### 🔴 Fil rouge TaskFlow — Étape 2
> Introduire un système de filtrage flexible : `GestionnaireTaches.filtrer(Predicate<Tache> critere)`. Le menu permet de combiner des filtres dynamiquement (type + priorité + statut). Remplacer les `Comparator` anonymes par des lambdas.

---

## Phase 3 — Streams API

### Objectifs
- Comprendre le concept de pipeline Stream (source → opérations intermédiaires → opération terminale)
- Maîtriser les opérations intermédiaires (`filter`, `map`, `flatMap`, `sorted`, `distinct`, `peek`, `limit`, `skip`)
- Maîtriser les opérations terminales (`forEach`, `collect`, `reduce`, `count`, `anyMatch`, `allMatch`, `findFirst`, `toList`)
- Utiliser `Collectors` (`toList`, `toSet`, `toMap`, `groupingBy`, `partitioningBy`, `joining`, `summarizing`)
- Streams primitifs (`IntStream`, `DoubleStream`, `LongStream`)

### Concepts clés
- Évaluation paresseuse (lazy evaluation)
- Stream ≠ Collection (usage unique, pas de stockage)
- Pipeline : chaîne fluide d'opérations
- Parallélisme (aperçu : `parallelStream()`)
- `Optional` comme résultat terminal (`findFirst`, `reduce`)
- Collectors avancés (`groupingBy` imbriqué, `collectingAndThen`)

### Exercices
1. **Statistiques en un pipeline** — Nombre de tâches terminées, moyenne de priorité, tâche la plus ancienne — le tout en streams
2. **Groupement** — `groupingBy(Statut)` puis `groupingBy(Priorite)` pour un tableau croisé statut × priorité
3. **Rapport textuel** — Construire un rapport formaté avec `Collectors.joining("\n")` à partir d'un stream de tâches
4. **Réduction** — Calculer la charge totale (somme des estimations) avec `reduce` et avec `mapToDouble().sum()`

### 🔴 Fil rouge TaskFlow — Étape 3
> Réécrire toute la logique de requêtage dans `GestionnaireTaches` avec des Streams : `listerParStatut()`, `statistiques()`, `rechercherParMotCle()`, `genererRapport()`. Supprimer les boucles for explicites pour le traitement de données.

---

## Phase 4 — Generics avancés

### Objectifs
- Créer des classes et méthodes génériques
- Comprendre les wildcards (`?`, `? extends T`, `? super T`)
- Appliquer le principe PECS (Producer Extends, Consumer Super)
- Créer des structures de données génériques réutilisables
- Bornes multiples (`<T extends A & B>`)

### Concepts clés
- Type erasure et ses conséquences
- Wildcards bornés pour la flexibilité
- Méthodes génériques (`<T> List<T> filtrer(...)`)
- Generics et héritage (`List<Bug>` n'est PAS un `List<Tache>`)
- Diamond operator (`<>`) et inférence de type

### Exercices
1. **Résultat générique** — Créer `class Resultat<T> { T valeur; String message; boolean succes; }` pour encapsuler les retours de service
2. **Repository générique** — Créer `interface Repository<T, ID> { void ajouter(T entite); Optional<T> trouverParId(ID id); List<T> trouverTous(); void supprimer(ID id); }`
3. **Méthode générique de filtrage** — `<T> List<T> filtrer(List<T> source, Predicate<T> critere)` réutilisable pour n'importe quel type
4. **Wildcards** — Écrire une méthode `afficherTaches(List<? extends Tache> taches)` qui accepte `List<Bug>`, `List<Feature>`, etc.

### 🔴 Fil rouge TaskFlow — Étape 4
> Introduire `interface Repository<T, ID>` implémentée par `TacheRepository`. Encapsuler les résultats d'opérations dans `Resultat<T>`. La couche service utilise le repository au lieu d'accéder directement à la liste.

---

## Phase 5 — Design Patterns

### Objectifs
- Comprendre et appliquer les patterns créationnels : **Factory Method**, **Builder**, **Singleton**
- Comprendre et appliquer les patterns comportementaux : **Strategy**, **Observer**
- Comprendre et appliquer le pattern structurel : **Decorator** (aperçu)
- Reconnaître les patterns dans le JDK (`Stream` = Builder, `Collections.unmodifiable` = Decorator…)

### Concepts clés
- Pattern = solution éprouvée à un problème récurrent
- Factory : déléguer la création d'objets
- Builder : construction étape par étape d'objets complexes
- Strategy : interchanger des algorithmes
- Observer : notification de changements
- Singleton : instance unique (et ses limites)
- Quand NE PAS utiliser un pattern (over-engineering)

### Exercices
1. **TacheFactory** — `TacheFactory.creer(TypeTache type, String titre, Priorite priorite)` retourne le bon sous-type sans `if/else` en utilisant une `Map<TypeTache, Supplier<Tache>>`
2. **TacheBuilder** — `new TacheBuilder().titre("...").priorite(HAUTE).echeance(date).build()` pour une construction flexible et lisible
3. **Strategy de tri** — Interface `StrategieTri` avec implémentations `TriParPriorite`, `TriParDate`, `TriParTitre` ; interchangeables à l'exécution
4. **Observer** — `interface TacheObserver { void onTacheAjoutee(Tache t); void onStatutChange(Tache t, Statut ancien, Statut nouveau); }` ; le logger et les statistiques écoutent les changements

### 🔴 Fil rouge TaskFlow — Étape 5
> Intégrer `TacheFactory` pour la création, `TacheBuilder` pour la construction via le menu, `Observer` pour le logging automatique et la mise à jour des statistiques. Le code de création de tâches ne contient plus de `switch` sur le type.

---

## Phase 6 — Tests unitaires avec JUnit 5

### Objectifs
- Comprendre la pyramide des tests (unit, integration, e2e)
- Écrire des tests avec JUnit 5 (`@Test`, `@BeforeEach`, `@AfterEach`, `@DisplayName`)
- Utiliser les assertions (`assertEquals`, `assertTrue`, `assertThrows`, `assertAll`)
- Organiser les tests (`@Nested`, `@Tag`)
- Découvrir les tests paramétrés (`@ParameterizedTest`, `@ValueSource`, `@CsvSource`, `@MethodSource`)

### Concepts clés
- Arrange-Act-Assert (AAA)
- Test isolé et indépendant
- Couverture de code (concept, pas d'outil encore)
- Tester les cas nominaux, les cas limites et les erreurs
- Nommage des tests : `should_ReturnEmpty_When_NoTachesExist`
- Dépendance Maven : `junit-jupiter` (scope `test`)

### Exercices
1. **Tests de Tache** — Tester la création, les getters/setters, la validation de priorité, `equals`/`hashCode`, `toString`
2. **Tests du GestionnaireTaches** — Tester ajout, suppression, recherche, filtrage, tâche inexistante → exception
3. **Tests paramétrés** — Tester les transitions de statut valides/invalides avec `@CsvSource`
4. **Tests du Repository** — Tester `TacheRepository` : CRUD complet, recherche par ID inexistant → `Optional.empty()`

### 🔴 Fil rouge TaskFlow — Étape 6
> Couvrir les couches `model` et `service` avec des tests JUnit 5. Objectif : au moins 1 classe de test par classe métier/service. Les tests passent avec `mvn test`. Minimum 30 tests.

---

## Phase 7 — Base de données avec JDBC

### Objectifs
- Comprendre les bases relationnelles (tables, colonnes, clés primaires, relations)
- Écrire du SQL : `CREATE TABLE`, `INSERT`, `SELECT`, `UPDATE`, `DELETE`
- Se connecter à une base SQLite via JDBC
- Exécuter des requêtes (`Statement`, `PreparedStatement`, `ResultSet`)
- Appliquer le pattern DAO (Data Access Object)

### Concepts clés
- JDBC : API standard Java pour les bases de données
- URL de connexion (`jdbc:sqlite:taskflow.db`)
- `PreparedStatement` vs `Statement` (sécurité SQL injection)
- Mapping objet-relationnel manuel (ResultSet → Objet)
- Transactions (`setAutoCommit`, `commit`, `rollback`)
- Pattern DAO : séparer l'accès aux données de la logique métier
- Migration de schéma (script SQL d'initialisation)

### Exercices
1. **Schéma** — Écrire le script `schema.sql` : table `taches` avec colonnes mappées aux attributs de `Tache`
2. **TacheDao** — Implémenter `TacheDao implements Repository<Tache, Integer>` avec JDBC et `PreparedStatement`
3. **Transactions** — Ajouter une méthode `ajouterEnLot(List<Tache> taches)` dans une transaction (rollback si erreur)
4. **Migration CSV → SQLite** — Écrire un utilitaire qui lit le `taches.csv` existant et insère les données dans SQLite

### 🔴 Fil rouge TaskFlow — Étape 7
> Remplacer la persistance CSV par SQLite. `TacheDao` implémente `Repository<Tache, Integer>`. La base est créée automatiquement au premier lancement (`schema.sql`). L'ancien CSV peut être importé via un utilitaire de migration.

---

## Phase 8 — Projet final Fluent : TaskFlow v3.0

### Objectifs
- Consolider tous les acquis du niveau Fluent
- Produire un projet Maven complet, testé, avec persistance BDD
- Architecture propre avec design patterns
- Code idiomatique Java moderne (streams, lambdas, Optional)

### Fonctionnalités attendues pour TaskFlow v3.0

```
╔═══════════════════════════════════════════════════╗
║            TASKFLOW v3.0 — MENU                   ║
╠═══════════════════════════════════════════════════╣
║  1.  📋 Lister (tri paramétrable)                ║
║  2.  ➕ Ajouter (Bug / Feature / Story)          ║
║  3.  ✏️  Modifier                                 ║
║  4.  🔄 Changer le statut                        ║
║  5.  🗑️  Supprimer                                ║
║  6.  🔍 Rechercher (mot-clé, ID)                 ║
║  7.  📊 Filtrer (critères combinables)           ║
║  8.  📈 Statistiques (streams)                   ║
║  9.  📂 Exporter (texte / CSV)                   ║
║  10. 🔁 Importer depuis CSV                      ║
║  11. 📑 Générer rapport complet                  ║
║  12. ❌ Quitter                                   ║
╚═══════════════════════════════════════════════════╝
```

### Structure du projet attendue

```
03-fluent/
├── program.md
└── taskflow-v3/
    ├── pom.xml
    ├── README.md
    └── src/
        ├── main/
        │   ├── java/
        │   │   └── com/taskflow/
        │   │       ├── TaskFlowApp.java
        │   │       ├── model/
        │   │       │   ├── Tache.java
        │   │       │   ├── Bug.java
        │   │       │   ├── Feature.java
        │   │       │   ├── Story.java
        │   │       │   ├── Priorite.java
        │   │       │   ├── Statut.java
        │   │       │   └── TypeTache.java
        │   │       ├── repository/
        │   │       │   ├── Repository.java        ← Interface générique
        │   │       │   └── TacheDao.java           ← Implémentation JDBC
        │   │       ├── service/
        │   │       │   ├── GestionnaireTaches.java
        │   │       │   └── ExportService.java
        │   │       ├── factory/
        │   │       │   ├── TacheFactory.java
        │   │       │   └── TacheBuilder.java
        │   │       ├── observer/
        │   │       │   ├── TacheObserver.java
        │   │       │   └── LogObserver.java
        │   │       ├── ui/
        │   │       │   ├── MenuConsole.java
        │   │       │   └── ConsoleUtils.java
        │   │       ├── util/
        │   │       │   ├── Resultat.java
        │   │       │   └── FormatUtils.java
        │   │       └── exception/
        │   │           └── ...
        │   └── resources/
        │       └── schema.sql
        └── test/
            └── java/
                └── com/taskflow/
                    ├── model/
                    │   └── TacheTest.java
                    ├── repository/
                    │   └── TacheDaoTest.java
                    ├── service/
                    │   └── GestionnaireTachesTest.java
                    └── factory/
                        └── TacheFactoryTest.java
```

### Critères de validation
- [ ] Projet Maven compilable (`mvn compile`) et testable (`mvn test`)
- [ ] Persistance SQLite fonctionnelle (CRUD complet)
- [ ] Design patterns appliqués : Factory, Builder, Observer, Strategy
- [ ] Streams utilisés pour tout le traitement de données (pas de boucles for pour filtrer/transformer)
- [ ] Lambdas et références de méthode utilisées systématiquement
- [ ] Interface générique `Repository<T, ID>` implémentée
- [ ] `Resultat<T>` encapsule les retours de service
- [ ] Minimum 30 tests JUnit 5 passants
- [ ] Tests paramétrés pour les cas multiples
- [ ] Code Java idiomatique et moderne
- [ ] README documentant l'architecture et les commandes pour build/run/test

### Bonus (optionnel)
- Mockito pour isoler les tests de service (mock du repository)
- Couverture de code avec JaCoCo
- Logging avec SLF4J + Logback au lieu du fichier log maison
- Pattern Command pour l'historique d'actions (undo/redo)
- Base de données H2 en alternative à SQLite (profil de configuration)

---

## Récapitulatif de progression

| Phase | Thème | Fil rouge TaskFlow |
|---|---|---|
| 1 | Maven, structure de projet | Migration vers projet Maven |
| 2 | Lambdas, interfaces fonctionnelles | Filtrage par Predicate, composition |
| 3 | Streams API, Collectors | Requêtage déclaratif, statistiques |
| 4 | Generics avancés, wildcards | Repository générique, Resultat\<T\> |
| 5 | Design patterns (Factory, Builder, Observer, Strategy) | Architecture patterns |
| 6 | JUnit 5, tests paramétrés | Couverture tests model + service |
| 7 | JDBC, SQLite, DAO | Persistance BDD, migration CSV |
| 8 | **Projet final v3.0** | **Application testée avec BDD** |

---

## Transition vers le niveau 04 — Master

À l'issue de ce niveau, tu as un projet Maven testé, avec base de données, design patterns et code Java idiomatique. Voici ce qui t'attend :

- **Spring Boot** pour créer une API REST complète
- **JPA / Hibernate** pour remplacer JDBC par un ORM
- **Spring Security** pour l'authentification et l'autorisation
- **Validation** avec Bean Validation (`@NotNull`, `@Size`…)
- **Docker** pour conteneuriser l'application
- **API documentation** avec OpenAPI / Swagger

> TaskFlow v4.0 deviendra une application web avec API REST, base de données gérée par JPA, sécurité intégrée, et déployable dans un conteneur Docker.