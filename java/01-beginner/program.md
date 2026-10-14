# Java — Niveau 01 : Beginner

## Vision du projet fil rouge : **TaskFlow**

> **TaskFlow** est une application de gestion de tâches et de projets qui évoluera à chaque niveau du programme. Ce fil rouge unique garantit une progression cohérente de *beginner* à *expert*.

| Niveau | Projet fil rouge — État de TaskFlow |
|---|---|
| **01 — Beginner** | Application console : saisie, affichage et organisation basique de tâches |
| **02 — Intermediate** | Persistance fichier, collections avancées, gestion d'erreurs robuste |
| **03 — Fluent** | Base de données, design patterns, tests unitaires, streams & lambdas |
| **04 — Master** | API REST Spring Boot, JPA/Hibernate, sécurité, conteneurisation Docker |
| **05 — Expert** | Microservices, messaging asynchrone, observabilité, déploiement cloud |

---

## Prérequis

- **JDK 26** installé (on utilise les fonctionnalités modernes de Java)
- Un éditeur ou IDE (VS Code + Extension Pack for Java, ou IntelliJ IDEA)
- Terminal / ligne de commande fonctionnel
- Aucune connaissance préalable en Java requise

---

## Phase 1 — Les fondations : premier programme et types primitifs

### Objectifs
- Comprendre le cycle écrire → compiler → exécuter
- Manipuler les types primitifs (`int`, `double`, `boolean`, `char`)
- Déclarer des variables et des constantes (`final`)
- Utiliser les opérateurs arithmétiques, de comparaison et logiques
- Formater la sortie console (`System.out.println`, `System.out.printf`)

### Concepts clés
- Structure d'un programme Java (classe, méthode `main`)
- Conventions de nommage (camelCase, PascalCase)
- Différence entre types primitifs et types référence (aperçu)
- Commentaires (`//`, `/* */`, `/** */`)

### Exercices
1. **Hello TaskFlow** — Afficher un message de bienvenue pour l'application TaskFlow
2. **Variables de tâche** — Déclarer des variables représentant une tâche : `titre` (String), `priorite` (int 1-5), `estimationHeures` (double), `terminee` (boolean)
3. **Calcul de charge** — Calculer et afficher le total d'heures pour 3 tâches, la moyenne, et le pourcentage de tâches terminées
4. **Affichage formaté** — Utiliser `printf` pour afficher une tâche sous forme de fiche lisible et alignée

### 🔴 Fil rouge TaskFlow — Étape 1
> Créer un programme `TaskFlowApp.java` qui déclare en dur 3 tâches (variables simples) et affiche un tableau récapitulatif formaté dans la console.

---

## Phase 2 — Contrôle de flux : décisions et boucles

### Objectifs
- Maîtriser `if / else if / else`
- Utiliser `switch` (classique et expression switch Java 21)
- Écrire des boucles `for`, `while`, `do-while`
- Contrôler le flux avec `break` et `continue`

### Concepts clés
- Évaluation booléenne et court-circuit (`&&`, `||`)
- Portée des variables dans les blocs
- Boucle `for-each` (aperçu avec tableaux)
- Expression `switch` avec `->` et `yield`

### Exercices
1. **Filtre de priorité** — Demander une priorité à l'utilisateur et afficher un message différent selon le niveau (1=basse … 5=critique) avec un `switch`
2. **Statut de tâche** — Utiliser une expression `switch` pour convertir un code statut (1-4) en libellé (`À faire`, `En cours`, `En revue`, `Terminée`)
3. **Compteur de tâches** — Boucle `for` affichant les tâches numérotées ; s'arrêter si on rencontre une tâche marquée "urgente" (`break`)
4. **Menu interactif** — Boucle `do-while` affichant un menu (1. Voir tâches, 2. Ajouter, 3. Quitter) et répétant jusqu'au choix "Quitter"

### 🔴 Fil rouge TaskFlow — Étape 2
> Ajouter un menu interactif à TaskFlowApp : l'utilisateur peut afficher la liste, filtrer par priorité, et quitter. Utiliser `Scanner` pour la saisie.

---

## Phase 3 — Tableaux et chaînes de caractères

### Objectifs
- Déclarer, initialiser et parcourir des tableaux (`int[]`, `String[]`)
- Tableaux multidimensionnels (aperçu)
- Manipuler les `String` : concaténation, méthodes utilitaires (`length`, `substring`, `contains`, `equals`, `toUpperCase`…)
- Découvrir `StringBuilder`
- Utiliser `java.util.Arrays` (tri, recherche, copie)

### Concepts clés
- Différence entre `==` et `.equals()` pour les Strings
- Immutabilité des Strings
- Index hors limites (`ArrayIndexOutOfBoundsException`)
- Passage par valeur vs passage par référence (tableaux)

### Exercices
1. **Tableau de titres** — Stocker 5 titres de tâches dans un tableau, les afficher avec leur index
2. **Recherche** — Parcourir un tableau pour trouver une tâche par mot-clé (saisie utilisateur)
3. **Tri alphabétique** — Trier un tableau de titres avec `Arrays.sort()` et afficher avant/après
4. **Constructeur de résumé** — Utiliser `StringBuilder` pour construire un rapport textuel multi-lignes récapitulant toutes les tâches

### 🔴 Fil rouge TaskFlow — Étape 3
> Refactorer TaskFlowApp pour stocker les tâches dans des tableaux parallèles (`String[] titres`, `int[] priorites`, `boolean[] terminees`). Permettre l'ajout de tâches (jusqu'à une capacité max) et la recherche par mot-clé.

---

## Phase 4 — Méthodes et modularité

### Objectifs
- Déclarer et appeler des méthodes (avec/sans retour, avec/sans paramètres)
- Comprendre la signature, la surcharge (overloading)
- Maîtriser la portée des variables (locale vs paramètre)
- Organiser le code en méthodes utilitaires cohérentes

### Concepts clés
- Pile d'appels (call stack) et passage de paramètres
- `return` et retour anticipé
- Méthodes `static` (contexte du `main`)
- Surcharge : même nom, signatures différentes
- Principes DRY (Don't Repeat Yourself)

### Exercices
1. **Méthode d'affichage** — Extraire l'affichage d'une tâche dans une méthode `afficherTache(String titre, int priorite, boolean terminee)`
2. **Surcharge** — Créer `ajouterTache(String titre)` (priorité par défaut = 3) et `ajouterTache(String titre, int priorite)`
3. **Méthode de calcul** — `calculerProgression(boolean[] terminees)` retourne le pourcentage de tâches terminées
4. **Validation** — `estPrioriteValide(int priorite)` retourne un `boolean` ; l'utiliser avant chaque ajout

### 🔴 Fil rouge TaskFlow — Étape 4
> Restructurer TaskFlowApp en extrayant toute la logique dans des méthodes dédiées : `afficherMenu()`, `ajouterTache(...)`, `listerTaches()`, `rechercherTache(...)`, `afficherStatistiques()`. Le `main` ne doit contenir que la boucle du menu et les appels de méthodes.

---

## Phase 5 — Introduction à la POO : classes et objets

### Objectifs
- Comprendre le paradigme orienté objet (classe = plan, objet = instance)
- Créer une classe avec attributs et méthodes
- Utiliser les constructeurs (défaut et paramétré)
- Appliquer l'encapsulation (`private` + getters/setters)
- Découvrir `this` et `toString()`

### Concepts clés
- Différence entre classe et objet
- État (attributs) et comportement (méthodes)
- Encapsulation et masquage des données
- Mot-clé `new` et mémoire (heap vs stack — aperçu)
- Convention JavaBean (getters/setters)

### Exercices
1. **Classe Tache** — Créer `Tache` avec les attributs `titre`, `description`, `priorite`, `terminee` ; constructeur paramétré ; `toString()`
2. **Encapsulation** — Rendre les attributs `private`, ajouter getters/setters avec validation (priorité entre 1 et 5)
3. **Classe Categorie** — Créer `Categorie` avec `nom` et `couleur` ; une tâche possède une catégorie
4. **Tableau d'objets** — Créer un tableau de `Tache[]`, le remplir et afficher toutes les tâches via `toString()`

### 🔴 Fil rouge TaskFlow — Étape 5
> Remplacer les tableaux parallèles par un tableau de `Tache[]`. Créer la classe `Tache` dans un fichier séparé. Adapter toutes les méthodes existantes pour manipuler des objets `Tache`.

---

## Phase 6 — Aller plus loin avec les objets

### Objectifs
- Utiliser des membres `static` (constantes de classe, compteur d'instances)
- Comprendre les énumérations (`enum`) pour les valeurs fixes
- Découvrir les records Java (Java 16+) pour les objets immuables simples
- Composer des objets (relation "a-un")

### Concepts clés
- `static` vs instance
- `enum` avec attributs et méthodes
- `record` : syntaxe compacte, immutabilité, cas d'usage
- Composition d'objets vs héritage (aperçu)
- `null` et `NullPointerException` (sensibilisation)

### Exercices
1. **Enum Priorite** — Créer `enum Priorite { BASSE, NORMALE, HAUTE, URGENTE, CRITIQUE }` avec un libellé et une couleur console (ANSI)
2. **Enum Statut** — Créer `enum Statut { A_FAIRE, EN_COURS, EN_REVUE, TERMINEE }` avec des transitions valides
3. **Record Résumé** — Créer `record Resume(int total, int terminees, double pourcentage)` pour encapsuler les statistiques
4. **Compteur static** — Ajouter un compteur `static` dans `Tache` pour attribuer un ID unique auto-incrémenté à chaque tâche

### 🔴 Fil rouge TaskFlow — Étape 6
> Introduire `enum Priorite` et `enum Statut` dans la classe `Tache`. Remplacer les `int` et `boolean` par ces enums. Ajouter un ID unique auto-généré. Créer un `record Resume` pour les statistiques.

---

## Phase 7 — Gestion des entrées et premières exceptions

### Objectifs
- Utiliser `Scanner` proprement (gestion des types, `nextLine` vs `nextInt`)
- Comprendre le mécanisme des exceptions (`try / catch / finally`)
- Gérer les erreurs de saisie utilisateur (`InputMismatchException`, `NumberFormatException`)
- Valider les entrées avec des boucles de re-saisie

### Concepts clés
- Hiérarchie des exceptions (aperçu : `Throwable` → `Exception` → `RuntimeException`)
- Checked vs unchecked exceptions (introduction)
- Bloc `try-with-resources` (aperçu pour `Scanner`)
- Messages d'erreur explicites pour l'utilisateur

### Exercices
1. **Saisie sécurisée** — Écrire `lireEntier(Scanner sc, String message, int min, int max)` avec boucle de re-saisie et `try/catch`
2. **Saisie de tâche complète** — Demander titre, priorité (enum), description avec validation à chaque étape
3. **Gestion du Scanner** — Gérer proprement le problème `nextInt()` suivi de `nextLine()`
4. **Menu robuste** — Aucun crash possible : toute saisie invalide affiche un message clair et re-propose le choix

### 🔴 Fil rouge TaskFlow — Étape 7
> Blindage complet de TaskFlowApp : toutes les saisies sont validées, aucune exception non gérée ne peut crasher l'application. Extraire les méthodes de saisie dans une classe utilitaire `ConsoleUtils`.

---

## Phase 8 — Projet final Beginner : TaskFlow v1.0

### Objectifs
- Consolider tous les acquis des phases 1 à 7
- Produire un programme complet, structuré et robuste
- Documenter minimalement le code (Javadoc sur les méthodes publiques)
- Pratiquer le refactoring

### Fonctionnalités attendues pour TaskFlow v1.0

```
╔══════════════════════════════════════════╗
║          TASKFLOW v1.0 — MENU           ║
╠══════════════════════════════════════════╣
║  1. 📋 Lister toutes les tâches        ║
║  2. ➕ Ajouter une tâche               ║
║  3. ✏️  Modifier une tâche              ║
║  4. 🔄 Changer le statut d'une tâche   ║
║  5. 🗑️  Supprimer une tâche             ║
║  6. 🔍 Rechercher (par mot-clé)        ║
║  7. 📊 Filtrer par priorité / statut   ║
║  8. 📈 Afficher les statistiques       ║
║  9. ❌ Quitter                          ║
╚══════════════════════════════════════════╝
```

### Structure des fichiers attendue

```
01-beginner/
├── program.md
└── taskflow-v1/
    ├── TaskFlowApp.java       ← Point d'entrée (main + menu)
    ├── Tache.java             ← Classe métier principale
    ├── Priorite.java          ← Enum des priorités
    ├── Statut.java            ← Enum des statuts
    ├── Resume.java            ← Record statistiques
    ├── GestionnaireTaches.java ← Logique métier (CRUD sur tableau)
    └── ConsoleUtils.java      ← Utilitaires de saisie/affichage
```

### Critères de validation
- [ ] Le programme compile et s'exécute sans erreur
- [ ] Toutes les 9 options du menu fonctionnent
- [ ] Aucune saisie invalide ne provoque un crash
- [ ] Le code est découpé en classes et méthodes cohérentes
- [ ] Les enums `Priorite` et `Statut` sont utilisés (pas de magic numbers)
- [ ] Chaque méthode publique a une Javadoc minimale
- [ ] Le code respecte les conventions Java (nommage, indentation)

### Bonus (optionnel)
- Affichage en couleurs ANSI dans le terminal
- Tri des tâches (par priorité, par statut, par date de création)
- Pagination si plus de 10 tâches
- Sauvegarde/chargement depuis un fichier texte (avant-goût du niveau 02)

---

## Récapitulatif de progression

| Phase | Thème | Fil rouge TaskFlow |
|---|---|---|
| 1 | Types primitifs, variables, opérateurs | Affichage de tâches en dur |
| 2 | Conditions, boucles, menu | Menu interactif + filtres |
| 3 | Tableaux, Strings | Stockage en tableaux, recherche |
| 4 | Méthodes, modularité | Extraction en méthodes |
| 5 | Classes, objets, encapsulation | Classe `Tache`, tableau d'objets |
| 6 | Enums, records, static | Enums Priorite/Statut, ID unique |
| 7 | Scanner, exceptions | Saisie robuste, `ConsoleUtils` |
| 8 | **Projet final v1.0** | **Application complète** |

---

## Transition vers le niveau 02 — Intermediate

À l'issue de ce niveau, tu sais écrire un programme Java console structuré en classes. Voici ce qui t'attend :

- **Collections** (`ArrayList`, `HashMap`, `Set`) pour remplacer les tableaux fixes
- **Héritage et polymorphisme** pour spécialiser les tâches (Bug, Feature, Story…)
- **Interfaces** pour définir des contrats (filtrage, tri, export)
- **Gestion de fichiers** (I/O) pour persister les tâches sur disque
- **Exceptions personnalisées** pour une gestion d'erreurs métier
- **Packages** pour organiser le code en modules

> TaskFlow v2.0 passera d'un tableau fixe à des collections dynamiques, sauvera les tâches dans des fichiers, et introduira des sous-types de tâches via l'héritage.