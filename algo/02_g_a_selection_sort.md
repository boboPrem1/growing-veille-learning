# Chapitre 2 - Sélection et Algorithmes de Tri

## Introduction au tri

Le **tri** est l'un des problèmes fondamentaux en informatique. Il consiste à organiser des éléments dans un ordre spécifique (numérique, alphabétique, etc.).

## Pourquoi le tri est important ?

- **Recherche efficace** : Les données triées permettent des recherches plus rapides
- **Organisation** : Facilite la lecture et l'analyse des données
- **Base pour d'autres algorithmes** : De nombreux algorithmes nécessitent des données triées

## Algorithme : Tri par sélection (Selection Sort)

### Le principe
1. Trouver le plus petit élément dans la liste
2. Le placer au début
3. Répéter pour le reste de la liste

### Exemple concret
Liste : `[5, 3, 6, 2, 10]`

**Étape 1** : Trouver le minimum (2) → `[2, 3, 6, 5, 10]`
**Étape 2** : Trouver le minimum dans le reste (3) → `[2, 3, 6, 5, 10]`
**Étape 3** : Trouver le minimum dans le reste (5) → `[2, 3, 5, 6, 10]`
**Étape 4** : Trouver le minimum dans le reste (6) → `[2, 3, 5, 6, 10]`

### Complexité
- **Temps** : O(n²) - Pour chaque élément, on parcourt tout le reste
- **Espace** : O(1) - Tri sur place, pas besoin de mémoire supplémentaire

## Tableaux vs Listes chaînées

### Tableaux (Arrays)
- **Avantages** : Accès direct O(1), lecture rapide
- **Inconvénients** : Insertion/suppression lente O(n)

### Listes chaînées (Linked Lists)
- **Avantages** : Insertion/suppression rapide O(1)
- **Inconvénients** : Accès séquentiel O(n), lecture lente

## Comment représenter les données ?

### Pour le tri par sélection
Les **tableaux** sont plus efficaces car :
- Accès direct aux éléments
- Pas besoin de parcourir toute la liste pour trouver un élément

### Pour l'insertion fréquente
Les **listes chaînées** sont meilleures car :
- Insertion en tête O(1)
- Pas besoin de décaler les éléments

## Code du tri par sélection

```python
def selection_sort(arr):
    for i in range(len(arr)):
        min_idx = i
        for j in range(i + 1, len(arr)):
            if arr[j] < arr[min_idx]:
                min_idx = j
        arr[i], arr[min_idx] = arr[min_idx], arr[i]
    return arr
```

## Concepts clés du Chapitre 2

1. **Structures de données** : Le choix affecte la performance des algorithmes
2. **Tri sur place** : Modifier les données sans utiliser de mémoire supplémentaire
3. **Compromis** : Différentes structures pour différents usages
4. **Complexité quadratique** : O(n²) devient lent avec de grandes données

## Points à retenir

- Le tri par sélection est simple mais inefficace pour les grandes listes
- Les tableaux sont meilleurs pour l'accès aléatoire
- Les listes chaînées sont meilleures pour les insertions fréquentes
- La complexité O(n²) limite l'utilisation pour des données volumineuses
- Le choix de la structure de données dépend du problème à résoudre

---
*Extrait essentiel du Chapitre 2 de "Grokking Algorithms" par Aditya Y. Bhargava*
