# Java — Niveau 02 : Intermediate

## Rappel du fil rouge : **TaskFlow**

> À l'issue du niveau Beginner, TaskFlow v1.0 est une application console structurée en classes avec enums, gestion de saisie robuste et CRUD basique sur un tableau fixe de tâches. Le niveau Intermediate fait évoluer TaskFlow vers une architecture orientée objet complète avec persistance fichier.

| Niveau | Projet fil rouge — État de TaskFlow |
|---|---|
| ~~01 — Beginner~~ | ~~Application console : saisie, affichage et organisation basique de tâches~~ ✅ |
| **02 — Intermediate** | **Persistance fichier, collections avancées, gestion d'erreurs robuste** ← tu es ici |
| 03 — Fluent | Base de données, design patterns, tests unitaires, streams & lambdas |
| 04 — Master | API REST Spring Boot, JPA/Hibernate, sécurité, conteneurisation Docker |
| 05 — Expert | Microservices, messaging asynchrone, observabilité, déploiement cloud |

---

## Prérequis

- Avoir complété le niveau 01 — Beginner (TaskFlow v1.0 fonctionnel)
- **JDK 26** installé
- Être à l'aise avec : classes, enums, tableaux, méthodes, Scanner, try/catch

---

## Phase 1 — Collections : libérer les contraintes du tableau fixe

### Objectifs
- Remplacer les tableaux par `ArrayList<T>`
- Comprendre la distinction `List`, `Set`, `Map` et choisir la bonne collection
- Maîtriser les itérateurs et le `for-each` sur collections
- Manipuler `HashMap<K, V>` pour des accès par clé
- Découvrir `LinkedList`, `HashSet`, `TreeSet`, `TreeMap`

### Concepts clés
- Interfaces vs implémentations (`List` vs `ArrayList`)
- Generics : typage paramétré (`<T>`, `<K, V>`)
- Autoboxing / unboxing (`int` ↔ `Integer`)
- Méthodes utilitaires de `Collections` (tri, recherche, min, max, unmodifiable)
- Complexité algorithmique (aperçu : O(1), O(n), O(log n))

### Exercices
1. **Migration ArrayList** — Remplacer `Tache[]` par `ArrayList<Tache>`, ajouter/supprimer dynamiquement
2. **Index par priorité** — Créer un `HashMap<Priorite, List<Tache>>` regroupant les tâches par priorité
3. **Titres uniques** — Utiliser un `HashSet<String>` pour vérifier l'unicité des titres avant ajout
4. **Tri personnalisé** — Trier les tâches par priorité puis par titre avec `Collections.sort()` et `Comparator`

### 🔴 Fil rouge TaskFlow — Étape 1
> Migrer `GestionnaireTaches` de `Tache[]` vers `ArrayList<Tache>`. Ajouter un index `HashMap<Priorite, List<Tache>>` mis à jour automatiquement. Supprimer la limite de capacité.

---

## Phase 2 — Héritage et polymorphisme

### Objectifs
- Comprendre l'héritage (`extends`) et la relation "est-un"
- Utiliser `super` (constructeur et méthodes)
- Maîtriser le polymorphisme et la liaison dynamique
- Redéfinir des méthodes (`@Override`)
- Comprendre les classes abstraites

### Concepts clés
- Hiérarchie de classes et arbre d'héritage
- Classe abstraite vs classe concrète
- Méthode abstraite : contrat sans implémentation
- Casting (`instanceof`, pattern matching Java 16+)
- Classe `Object` : `equals()`, `hashCode()`, `toString()`
- Annotation `@Override`

### Exercices
1. **Sous-types de tâches** — Créer `Bug`, `Feature`, `Story` qui héritent de `Tache` avec des attributs spécifiques (ex: `severite` pour Bug, `pointsEffort` pour Story)
2. **Méthode abstraite** — Rendre `Tache` abstraite avec une méthode `String getEtiquette()` implémentée différemment dans chaque sous-type
3. **Polymorphisme en action** — Stocker des `Bug`, `Feature`, `Story` dans une `List<Tache>` et appeler `getEtiquette()` sur chacune
4. **equals et hashCode** — Implémenter `equals()` et `hashCode()` dans `Tache` basés sur l'ID unique

### 🔴 Fil rouge TaskFlow — Étape 2
> Rendre `Tache` abstraite. Créer les sous-classes `Bug`, `Feature` et `Story`. Le menu d'ajout demande désormais le type de tâche et les champs spécifiques. L'affichage montre l'étiquette de chaque type.

---

## Phase 3 — Interfaces et contrats

### Objectifs
- Déclarer et implémenter des interfaces
- Comprendre la différence interface vs classe abstraite
- Utiliser les interfaces fonctionnelles (aperçu)
- Implémenter `Comparable<T>` et `Comparator<T>`
- Découvrir les méthodes `default` et `static` dans les interfaces

### Concepts clés
- Interface = contrat de comportement
- Implémentation multiple (une classe, plusieurs interfaces)
- Interfaces du JDK : `Comparable`, `Iterable`, `Serializable`
- Séparation des responsabilités via interfaces
- Principe "programmer vers une interface, pas une implémentation"

### Exercices
1. **Interface Exportable** — Créer `interface Exportable { String exporterTexte(); String exporterCsv(); }` ; l'implémenter dans `Tache`
2. **Interface Filtrable** — Créer `interface Filtrable<T> { List<T> filtrer(List<T> elements); }` pour les stratégies de filtrage
3. **Comparable** — Implémenter `Comparable<Tache>` pour un tri naturel par priorité
4. **Comparators multiples** — Créer des `Comparator<Tache>` pour trier par titre, statut, date de création ; les chaîner avec `thenComparing`

### 🔴 Fil rouge TaskFlow — Étape 3
> Les tâches implémentent `Exportable` et `Comparable<Tache>`. Ajouter au menu : export de la liste en texte et CSV (affiché en console). Le tri est paramétrable (par priorité, titre ou statut).

---

## Phase 4 — Packages et organisation du code

### Objectifs
- Organiser le code en packages Java
- Comprendre les niveaux de visibilité (`public`, `protected`, package-private, `private`)
- Utiliser les imports correctement
- Structurer un projet multi-packages

### Concepts clés
- Convention de nommage des packages (`com.taskflow.model`, etc.)
- Visibilité et encapsulation au niveau du package
- Package `default` (sans déclaration)
- Dépendances entre packages et architecture en couches
- Compilation et exécution avec packages (`javac -d`, classpath)

### Exercices
1. **Restructuration** — Organiser le projet en packages : `model`, `service`, `ui`, `util`
2. **Visibilité** — Ajuster les modificateurs d'accès : seules les méthodes nécessaires sont `public`
3. **Package service** — Déplacer `GestionnaireTaches` dans `service` et n'exposer qu'une interface publique
4. **Compilation** — Compiler et exécuter le projet multi-packages depuis la ligne de commande

### 🔴 Fil rouge TaskFlow — Étape 4
> Réorganiser tout le code TaskFlow en packages :
> ```
> com.taskflow/
> ├── model/      → Tache, Bug, Feature, Story, Priorite, Statut
> ├── service/    → GestionnaireTaches, ExportService
> ├── ui/         → MenuConsole, ConsoleUtils
> └── util/       → Validateur, FormatUtils
> ```

---

## Phase 5 — Gestion de fichiers (I/O)

### Objectifs
- Lire et écrire des fichiers texte (`FileReader`, `FileWriter`, `BufferedReader`, `BufferedWriter`)
- Utiliser `try-with-resources` systématiquement
- Manipuler les chemins avec `java.nio.file.Path` et `Files`
- Sérialiser/désérialiser des objets en format texte (CSV)
- Découvrir `java.io` vs `java.nio`

### Concepts clés
- Flux (streams) d'entrée/sortie : octets vs caractères
- Buffering et performance
- Encodage (`UTF-8`)
- `Path`, `Files.readAllLines()`, `Files.write()`
- Gestion des exceptions I/O (`IOException`, `FileNotFoundException`)

### Exercices
1. **Écriture CSV** — Sauvegarder toutes les tâches dans un fichier `taches.csv`
2. **Lecture CSV** — Charger les tâches depuis `taches.csv` au démarrage de l'application
3. **Fichier de configuration** — Lire un `config.properties` (nombre max de tâches, chemin de sauvegarde, etc.)
4. **Journal d'activité** — Écrire un fichier `taskflow.log` enregistrant chaque action (ajout, modification, suppression) avec horodatage

### 🔴 Fil rouge TaskFlow — Étape 5
> TaskFlow persiste désormais les tâches dans `taches.csv`. Au démarrage : chargement automatique. À la fermeture (ou sur demande) : sauvegarde. Ajouter un fichier de log `taskflow.log`.

---

## Phase 6 — Exceptions personnalisées et robustesse

### Objectifs
- Créer des exceptions métier personnalisées
- Maîtriser la chaîne `throw` → `throws` → `try/catch`
- Comprendre quand utiliser checked vs unchecked
- Appliquer le pattern "fail fast"
- Gérer les erreurs en couches (propagation)

### Concepts clés
- Hiérarchie complète : `Throwable` → `Error` / `Exception` → `RuntimeException`
- Exception personnalisée avec message et cause
- Multi-catch (`catch (A | B e)`)
- `finally` vs `try-with-resources`
- Anti-patterns : catch vide, catch `Exception` générique, exceptions pour le flux de contrôle

### Exercices
1. **TacheNotFoundException** — Exception levée quand on cherche une tâche par ID inexistant
2. **ValidationException** — Exception regroupant une liste d'erreurs de validation
3. **PersistanceException** — Encapsuler les `IOException` dans une exception métier lors de la lecture/écriture fichier
4. **TransitionStatutException** — Exception si on tente une transition de statut invalide (ex: `TERMINEE` → `A_FAIRE`)

### 🔴 Fil rouge TaskFlow — Étape 6
> Remplacer tous les `System.out.println("Erreur...")` par des exceptions métier appropriées. La couche `service` lève des exceptions, la couche `ui` les attrape et affiche des messages clairs. Aucun `catch` vide dans le code.

---

## Phase 7 — Dates, temps et types utilitaires

### Objectifs
- Utiliser `java.time` : `LocalDate`, `LocalDateTime`, `Duration`, `Period`
- Formater et parser des dates (`DateTimeFormatter`)
- Comprendre `Optional<T>` pour éviter les `null`
- Découvrir les wrappers (`Integer`, `Double`…) et leurs méthodes utilitaires

### Concepts clés
- API `java.time` (immuable, thread-safe)
- Formatage personnalisé (`DateTimeFormatter.ofPattern`)
- `Optional` : `of`, `ofNullable`, `isPresent`, `orElse`, `map`
- Bonnes pratiques : éviter `null`, utiliser `Optional` en retour de méthode
- `String.format()`, `Objects.requireNonNull()`

### Exercices
1. **Dates de tâche** — Ajouter `dateCreation` (auto) et `dateEcheance` (optionnelle) à `Tache`
2. **Tâches en retard** — Filtrer les tâches dont l'échéance est dépassée avec `LocalDate.now()`
3. **Durée de traitement** — Calculer le temps passé entre la création et la complétion d'une tâche
4. **Optional** — `rechercherParId(int id)` retourne `Optional<Tache>` au lieu de `null`

### 🔴 Fil rouge TaskFlow — Étape 7
> Enrichir `Tache` avec `dateCreation`, `dateEcheance` (Optional) et `dateCompletion`. Ajouter au menu : afficher les tâches en retard, afficher les statistiques de durée. `rechercherParId` retourne `Optional<Tache>`.

---

## Phase 8 — Projet final Intermediate : TaskFlow v2.0

### Objectifs
- Consolider tous les acquis du niveau Intermediate
- Produire un projet structuré, persistant et robuste
- Pratiquer le refactoring d'envergure
- Documenter l'architecture (README)

### Fonctionnalités attendues pour TaskFlow v2.0

```
╔═══════════════════════════════════════════════╗
║          TASKFLOW v2.0 — MENU                 ║
╠═══════════════════════════════════════════════╣
║  1.  📋 Lister les tâches (tri paramétrable) ║
║  2.  ➕ Ajouter (Bug / Feature / Story)      ║
║  3.  ✏️  Modifier une tâche                   ║
║  4.  🔄 Changer le statut                    ║
║  5.  🗑️  Supprimer une tâche                  ║
║  6.  🔍 Rechercher (mot-clé, ID)             ║
║  7.  📊 Filtrer (priorité / statut / type)   ║
║  8.  📈 Statistiques & tâches en retard      ║
║  9.  💾 Sauvegarder                          ║
║  10. 📂 Exporter (texte / CSV)               ║
║  11. ❌ Quitter                               ║
╚═══════════════════════════════════════════════╝
```

### Structure du projet attendue

```
02-intermediate/
├── program.md
└── taskflow-v2/
    └── src/
        └── com/
            └── taskflow/
                ├── model/
                │   ├── Tache.java          ← Classe abstraite
                │   ├── Bug.java
                │   ├── Feature.java
                │   ├── Story.java
                │   ├── Priorite.java
                │   └── Statut.java
                ├── service/
                │   ├── GestionnaireTaches.java
                │   ├── PersistanceService.java
                │   └── ExportService.java
                ├── exception/
                │   ├── TacheNotFoundException.java
                │   ├── ValidationException.java
                │   ├── PersistanceException.java
                │   └── TransitionStatutException.java
                ├── ui/
                │   ├── MenuConsole.java
                │   └── ConsoleUtils.java
                ├── util/
                │   ├── Validateur.java
                │   └── FormatUtils.java
                └── TaskFlowApp.java
```

### Critères de validation
- [ ] Le projet est organisé en packages (`model`, `service`, `exception`, `ui`, `util`)
- [ ] `Tache` est abstraite avec sous-classes `Bug`, `Feature`, `Story`
- [ ] Les collections sont utilisées (`ArrayList`, `HashMap`, pas de tableaux bruts)
- [ ] Les tâches persistent dans un fichier CSV (sauvegarde/chargement)
- [ ] Les exceptions métier sont utilisées (pas de `println` pour les erreurs)
- [ ] `Optional` est utilisé pour les retours pouvant être absents
- [ ] Les dates (`java.time`) sont intégrées (création, échéance, complétion)
- [ ] Le tri et le filtrage fonctionnent avec `Comparable` / `Comparator`
- [ ] L'export texte et CSV fonctionne
- [ ] Un fichier `taskflow.log` enregistre les actions
- [ ] Le code compile et s'exécute sans erreur

### Bonus (optionnel)
- Sérialisation binaire avec `Serializable` / `ObjectOutputStream`
- Sauvegarde automatique après chaque modification
- Import depuis un fichier CSV externe
- Statistiques avancées (tâches par semaine, temps moyen de résolution)
- Système de tags avec `Set<String>` sur les tâches

---

## Récapitulatif de progression

| Phase | Thème | Fil rouge TaskFlow |
|---|---|---|
| 1 | Collections (`List`, `Map`, `Set`) | Migration ArrayList, index par priorité |
| 2 | Héritage, polymorphisme, classes abstraites | Sous-types Bug/Feature/Story |
| 3 | Interfaces, Comparable, Comparator | Export, tri paramétrable |
| 4 | Packages, visibilité | Architecture en couches |
| 5 | I/O fichiers, CSV, NIO | Persistance CSV, fichier de log |
| 6 | Exceptions personnalisées | Exceptions métier en couches |
| 7 | java.time, Optional | Dates, échéances, Optional |
| 8 | **Projet final v2.0** | **Application complète persistante** |

---

## Transition vers le niveau 03 — Fluent

À l'issue de ce niveau, tu as un projet Java multi-packages avec héritage, persistance fichier et gestion d'erreurs métier. Voici ce qui t'attend :

- **Streams & Lambdas** pour des traitements de données déclaratifs et concis
- **Generics avancés** (wildcards, bornes) pour du code réutilisable
- **Design patterns** (Strategy, Observer, Factory, Builder, Singleton) appliqués à TaskFlow
- **Tests unitaires** avec JUnit 5 et Mockito
- **Base de données** relationnelle avec JDBC
- **Build tool** : Maven ou Gradle pour gérer le projet et ses dépendances

> TaskFlow v3.0 passera d'un fichier CSV à une base de données SQLite, sera couvert par des tests unitaires, et utilisera des design patterns pour une architecture propre et extensible.