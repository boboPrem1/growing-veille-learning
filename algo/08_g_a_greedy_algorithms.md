# Chapitre 8 - Algorithmes Gloutons (Greedy Algorithms)

## Qu'est-ce qu'un algorithme glouton ?

Un **algorithme glouton** fait le choix optimal local à chaque étape, en espérant aboutir à une solution globale optimale. C'est comme prendre toujours le chemin le plus évident sans regarder trop loin.

## Principe : "Localement optimal → Globalement optimal ?"

### Fonctionnement
1. **Évaluer** les options disponibles immédiatement
2. **Choisir** la meilleure option maintenant
3. **Répéter** jusqu'à la solution complète

### Attention !
- **Parfois** : La stratégie gloutonne fonctionne parfaitement
- **Parfois** : Elle mène à une solution sous-optimale
- **Défi** : Savoir quand l'utiliser

## Problème 1 : Planification de salle de classe

### Scénario
Vous devez planifier le plus grand nombre possible de cours dans une salle, sachant que chaque cours a des heures de début et fin.

### Données
```
Cours A : 9h - 10h
Cours B : 9h30 - 10h30
Cours C : 10h - 11h
Cours D : 10h30 - 11h30
Cours E : 11h - 12h
```

### Approche gloutonne
1. **Choisir** le cours qui finit le plus tôt
2. **Éliminer** tous les cours qui chevauchent
3. **Répéter** avec les cours restants

### Exécution étape par étape
**Étape 1** : Cours A (9h-10h) - finit le plus tôt
**Éliminer** : B (chevauche A)
**Restants** : C, D, E

**Étape 2** : Cours C (10h-11h) - prochain qui finit le plus tôt
**Éliminer** : D (chevauche C)
**Restants** : E

**Étape 3** : Cours E (11h-12h)
**Solution optimale** : A, C, E (3 cours)

### Implémentation
```python
def schedule_classes(courses):
    # Trier par heure de fin
    sorted_courses = sorted(courses, key=lambda x: x[1])
    
    schedule = []
    last_end = 0
    
    for course in courses:
        start, end = course
        if start >= last_end:
            schedule.append(course)
            last_end = end
    
    return schedule
```

## Problème 2 : Le sac à dos (Knapsack Problem)

### Variante : Sac à dos fractionnaire
Contrairement au chapitre 9, ici on peut prendre des fractions d'objets.

### Données
```
Sac : capacité 15kg
Objets :
- Or : 10kg, $60/kg → Valeur totale : $600
- Argent : 5kg, $40/kg → Valeur totale : $200
- Cuivre : 15kg, $20/kg → Valeur totale : $300
```

### Approche gloutonne
Prendre l'objet avec le meilleur rapport valeur/poids.

**Étape 1** : Or ($60/kg) - prendre tout (10kg)
**Reste** : 5kg de capacité

**Étape 2** : Argent ($40/kg) - prendre tout (5kg)
**Reste** : 0kg de capacité

**Solution** : 10kg d'or + 5kg d'argent = $800

### Implémentation
```python
def fractional_knapsack(items, capacity):
    # Trier par valeur/poids décroissant
    sorted_items = sorted(items, key=lambda x: x[1]/x[0], reverse=True)
    
    total_value = 0
    remaining_capacity = capacity
    
    for weight, value in sorted_items:
        if remaining_capacity >= weight:
            total_value += value
            remaining_capacity -= weight
        else:
            # Prendre une fraction
            fraction = remaining_capacity / weight
            total_value += value * fraction
            break
    
    return total_value
```

## Problème 3 : Couverture d'ensemble (Set Covering)

### Scénario
Vous voulez construire des stations de radio pour couvrir plusieurs états avec un minimum de stations.

### Données
```
États à couvrir : 1, 2, 3, 4, 5

Stations disponibles :
A : couvre {1, 2, 3}
B : couvre {2, 4}
C : couvre {3, 5}
D : couvre {1, 4, 5}
```

### Approche gloutonne
1. **Choisir** la station qui couvre le plus d'états non couverts
2. **Répéter** jusqu'à ce que tous les états soient couverts

### Exécution
**Étape 1** : Station A (couvre 3 états)
**Couverts** : {1, 2, 3}
**Restants** : {4, 5}

**Étape 2** : Station D (couvre 2 états restants)
**Couverts** : {1, 2, 3, 4, 5}
**Solution** : Stations A et D

### Implémentation
```python
def set_covering(universe, sets):
    uncovered = set(universe)
    selected_sets = []
    
    while uncovered:
        best_set = None
        best_covered = set()
        
        for name, covered in sets.items():
            newly_covered = uncovered & covered
            if len(newly_covered) > len(best_covered):
                best_set = name
                best_covered = newly_covered
        
        if best_set is None:
            break
        
        selected_sets.append(best_set)
        uncovered -= best_covered
    
    return selected_sets
```

## Algorithmes d'approximation

### Quand la solution exacte est trop coûteuse
Certains problèmes sont NP-difficiles - trouver la solution exacte prend un temps exponentiel.

### Algorithmes d'approximation
- **Objectif** : Trouver une solution "assez bonne" rapidement
- **Garantie** : Solution dans un facteur de l'optimale
- **Usage** : Problèmes réels où "assez bon" suffit

### Exemple : Couverture d'ensemble
- **Solution optimale** : Difficile à trouver (NP-difficile)
- **Solution gloutonne** : Rapide et garantie d'être au moins 63% de l'optimale

## Problèmes NP-complets

### Qu'est-ce que NP-complet ?
- **NP** : Vérifiable rapidement (non-déterministe polynomial)
- **NP-complet** : Les problèmes les plus difficiles dans NP
- **Propriété** : Si on résout un, on résout tous les autres

### Exemples de problèmes NP-complets
1. **Voyageur de commerce** : Chemin le plus court visitant toutes les villes
2. **Sac à discret** : Chapitre 9, version sans fractions
3. **Coloration de graphe** : Colorier un graphe avec un minimum de couleurs
4. **Satisfiability (SAT)** : Problème fondamental en logique

### Comment reconnaître un problème NP-complet ?

**Signes indicateurs :**
1. **Optimisation** : Trouver le "meilleur" parmi beaucoup d'options
2. **Combinatoire** : Beaucoup de combinaisons possibles
3. **Pas d'algorithme rapide connu** : Personne n'a trouvé de solution polynomiale
4. **Réductible** : Peut transformer un autre problème NP-complet en celui-ci

### Exemple : Voyageur de commerce

```
Villes : A, B, C, D, E
Distances connues entre chaque paire

Objectif : Chemin le plus court visitant toutes les villes une fois
```

**Approche naïve** : Essayer toutes les permutations
- 5 villes : 5! = 120 chemins
- 10 villes : 10! = 3,628,800 chemins
- 15 villes : 15! = 1,307,674,368,000 chemins !

**Approche gloutonne** : Toujours aller à la ville la plus proche non visitée
- Rapide mais pas toujours optimal

## Quand utiliser les algorithmes gloutons ?

### Cas où ça fonctionne bien
1. **Planification** : Intervalles (comme les salles de classe)
2. **Huffman coding** : Compression de données
3. **Arbres couvrants minimum** : Chapitre 8
4. **Sac à dos fractionnaire** : Peut prendre des fractions

### Cas où ça ne fonctionne pas
1. **Sac à discret** : Chapitre 9 (sans fractions)
2. **Voyageur de commerce** : Peut être très sous-optimal
3. **Coloration de graphe** : Peut utiliser trop de couleurs

### Comment savoir ?
1. **Preuve mathématique** : Démontrer que local = global
2. **Contre-exemple** : Trouver un cas où ça échoue
3. **Expérience** : Tester sur de nombreux exemples

## Avantages et inconvénients des algorithmes gloutons

### Avantages
- **Simple** à comprendre et implémenter
- **Rapide** : généralement polynomial
- **Pratique** : souvent "assez bon" pour les applications réelles
- **Intuitif** : correspond à notre façon de penser

### Inconvénients
- **Pas toujours optimal** : peut donner de mauvais résultats
- **Difficile à prouver** : savoir si ça marche pour un problème donné
- **Pièges** : certains problèmes semblent gloutons mais ne le sont pas

## Concepts clés du Chapitre 8

1. **Choix local optimal** : Prendre la meilleure option maintenant
2. **Approximation** : Solutions "assez bonnes" pour les problèmes difficiles
3. **NP-complétude** : Classe de problèmes très difficiles
4. **Sacrifices** : Vitesse vs optimalité

## Points à retenir

- Les algorithmes gloutons choisissent localement optimal
- Parfois ça donne la solution globale optimale
- Parfois ça donne une solution sous-optimale
- Utiles pour les problèmes NP-difficiles comme approximation
- Applications : planification, sac à dos fractionnaire, couverture d'ensemble

---
*Extrait essentiel du Chapitre 8 de "Grokking Algorithms" par Aditya Y. Bhargava*
