# Chapitre 9 - Programmation Dynamique

## Qu'est-ce que la programmation dynamique ?

La **programmation dynamique** est une technique qui résout des problèmes complexes en les décomposant en sous-problèmes plus simples et en stockant les résultats pour éviter les recalculs.

## Problème type : Le sac à dos (Knapsack Problem)

### Scénario
Vous avez un sac avec une capacité limitée et plusieurs objets avec des poids et valeurs différents. Quels objets prendre pour maximiser la valeur totale ?

### Approche naïve
- Essayer toutes les combinaisons possibles
- Complexité : O(2^n) - exponentiel !

### Approche dynamique
- Utiliser une grille pour stocker les solutions intermédiaires
- Complexité : O(n × capacité) - polynomial !

## Le problème du sac à dos en détail

### Données
```
Objets : 
- Guitare (1kg, $1500)
- Ordinateur (3kg, $2000)  
- Téléphone (1kg, $1000)

Capacité du sac : 4kg
```

### Grille de programmation dynamique
```
      0kg  1kg  2kg  3kg  4kg
Guitre 0   1500 1500 1500 1500
Ordi   0   1500 1500 2000 3500
Tel    0   1500 1500 2000 3500
```

### Comment remplir la grille
Pour chaque cellule [i][j] :
- **Ne pas prendre l'objet** : valeur de [i-1][j]
- **Prendre l'objet** : valeur_objet + [i-1][j-poids_objet]
- **Maximum** des deux options

## Implémentation du sac à dos

```python
def knapsack(items, capacity):
    # Grille : (nombre d'objets + 1) × (capacité + 1)
    grid = [[0] * (capacity + 1) for _ in range(len(items) + 1)]
    
    for i in range(1, len(items) + 1):
        weight, value = items[i - 1]
        for j in range(capacity + 1):
            # Ne pas prendre l'objet
            without_item = grid[i - 1][j]
            
            # Prendre l'objet (si possible)
            if weight <= j:
                with_item = value + grid[i - 1][j - weight]
                grid[i][j] = max(without_item, with_item)
            else:
                grid[i][j] = without_item
    
    return grid[-1][-1]  # Valeur maximale
```

## Applications de la programmation dynamique

### 1. Plus longue sous-séquence commune
- **Problème** : Trouver la plus longue séquence commune entre deux chaînes
- **Usage** : Comparaison de DNA, plagiat, version control

### 2. Plus long chemin dans un graphe
- **Problème** : Trouver le chemin le plus long
- **Usage** : Planification, ordonnancement

### 3. Changement de monnaie
- **Problème** : Nombre minimum de pièces pour un montant
- **Usage** : Distributeurs automatiques, caisses

## Plus longue sous-séquence commune

### Exemple
```
Chaîne 1 : "FOSH"
Chaîne 2 : "FISH"
Résultat : "FSH" (longueur = 3)
```

### Grille de résolution
```
      ""  F   O   S   H
""    0   0   0   0   0
F     0   1   1   1   1
I     0   1   1   1   1
S     0   1   1   2   2
H     0   1   1   2   3
```

### Implémentation
```python
def longest_common_subsequence(s1, s2):
    m, n = len(s1), len(s2)
    dp = [[0] * (n + 1) for _ in range(m + 1)]
    
    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if s1[i - 1] == s2[j - 1]:
                dp[i][j] = dp[i - 1][j - 1] + 1
            else:
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
    
    return dp[m][n]
```

## Principes de la programmation dynamique

### 1. Sous-structure optimale
- La solution optimale contient des solutions optimales de sous-problèmes
- Exemple : Si le sac à dos optimal contient l'ordinateur, le reste doit aussi être optimal

### 2. Chevauchement de sous-problèmes
- Les mêmes sous-problèmes apparaissent plusieurs fois
- Stocker les résultats évite les recalculs

### 3. Mémoïsation vs Tabulation
- **Mémoïsation** : Top-down (récursif avec cache)
- **Tabulation** : Bottom-up (itératif avec tableau)

## Mémoïsation (Top-down)

```python
def fibonacci_memo(n, memo={}):
    if n in memo:
        return memo[n]
    if n <= 2:
        return 1
    
    memo[n] = fibonacci_memo(n - 1, memo) + fibonacci_memo(n - 2, memo)
    return memo[n]
```

## Tabulation (Bottom-up)

```python
def fibonacci_tab(n):
    if n <= 2:
        return 1
    
    dp = [0] * (n + 1)
    dp[1] = dp[2] = 1
    
    for i in range(3, n + 1):
        dp[i] = dp[i - 1] + dp[i - 2]
    
    return dp[n]
```

## Questions fréquentes sur le sac à dos

### Q: Que se passe-t-il si on ajoute un objet ?
**R**: Il faut recalculer la grille avec une ligne supplémentaire.

### Q: L'ordre des lignes est-il important ?
**R**: Non, mais l'ordre des colonnes (capacités) doit être croissant.

### Q: Peut-on prendre des fractions d'objet ?
**R**: Non, c'est le problème du sac à discret. Pour les fractions, c'est un autre problème.

### Q: La solution remplit-elle toujours le sac ?
**R**: Pas forcément. La valeur maximale peut ne pas utiliser toute la capacité.

## Limites et défis

### 1. Complexité espace
- La grille peut devenir très grande
- Solution : optimisation spatiale, ne garder que les lignes nécessaires

### 2. Problèmes NP-difficiles
- Certains problèmes n'ont pas de solution efficace
- La programmation dynamique aide mais reste exponentielle dans certains cas

### 3. Identification des sous-problèmes
- Difficile de reconnaître quand utiliser la programmation dynamique
- nécessite de l'expérience et de la pratique

## Concepts clés du Chapitre 9

1. **Décomposition** : Diviser le problème en sous-problèmes
2. **Stockage** : Mémoriser les résultats intermédiaires
3. **Réutilisation** : Éviter les recalculs
4. **Optimalité** : Construire la solution optimale à partir des sous-solutions

## Points à retenir

- La programmation dynamique résout des problèmes complexes efficacement
- Le principe : décomposer + stocker + réutiliser
- Applications : sac à dos, séquences communes, plus courts chemins
- Deux approches : mémoïsation (top-down) et tabulation (bottom-up)
- Transforme des problèmes exponentiels en problèmes polynomiaux

---
*Extrait essentiel du Chapitre 9 de "Grokking Algorithms" par Aditya Y. Bhargava*
