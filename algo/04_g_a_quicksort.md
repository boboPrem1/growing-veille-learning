# Chapitre 4 - Tri Rapide (Quicksort)

## Introduction au Tri Rapide

Le **Tri Rapide (Quicksort)** est un algorithme de tri "diviser pour régner" qui utilise la récursivité. C'est l'un des algorithmes de tri les plus efficaces en pratique.

## Principe du Tri Rapide

### Étapes :
1. **Choisir un pivot** : Un élément du tableau
2. **Partitionner** : Placer les éléments plus petits à gauche, plus grands à droite
3. **Trier récursivement** : Appliquer le même processus aux sous-tableaux

### Exemple concret
Tableau : `[3, 7, 8, 5, 2, 1, 9, 5, 4]`

**Étape 1** : Pivot = 5
- Éléments < 5 : `[3, 2, 1, 4]`
- Éléments = 5 : `[5, 5]`
- Éléments > 5 : `[7, 8, 9]`

**Étape 2** : Trier `[3, 2, 1, 4]` et `[7, 8, 9]` récursivement

## Algorithme détaillé

```python
def quicksort(arr):
    if len(arr) <= 1:           # Cas de base
        return arr
    else:                       # Cas récursif
        pivot = arr[len(arr) // 2]
        left = [x for x in arr if x < pivot]
        middle = [x for x in arr if x == pivot]
        right = [x for x in arr if x > pivot]
        return quicksort(left) + middle + quicksort(right)
```

## Analyse de complexité

### Meilleur cas : O(n log n)
- Pivot divise le tableau en deux parties égales
- Profondeur : log n
- Travail à chaque niveau : n

### Cas moyen : O(n log n)
- En pratique, proche du meilleur cas

### Pire cas : O(n²)
- Pivot toujours le plus petit ou le plus grand
- Profondeur : n
- Exemple : tableau déjà trié avec pivot = premier élément

## Importance du choix du pivot

### Stratégies :
1. **Premier élément** : Simple mais risqué
2. **Dernier élément** : Similaire au premier
3. **Élément médian** : Bon compromis
4. **Élément aléatoire** : Réduit le risque du pire cas
5. **Médiane de trois** : Choisir le médian de premier, milieu, dernier

## Tri Rapide vs Tri par sélection

| Caractéristique | Tri Rapide | Tri par sélection |
|-----------------|------------|-------------------|
| Complexité moyenne | O(n log n) | O(n²) |
| Pire cas | O(n²) | O(n²) |
| Espace | O(log n) | O(1) |
| Stabilité | Non stable | Stable |
| Usage pratique | Très utilisé | Rarement utilisé |

## Tri Rapide sur place

### Version optimisée (moins de mémoire)
```python
def quicksort_inplace(arr, low, high):
    if low < high:
        pivot_index = partition(arr, low, high)
        quicksort_inplace(arr, low, pivot_index - 1)
        quicksort_inplace(arr, pivot_index + 1, high)

def partition(arr, low, high):
    pivot = arr[high]
    i = low - 1
    for j in range(low, high):
        if arr[j] <= pivot:
            i += 1
            arr[i], arr[j] = arr[j], arr[i]
    arr[i + 1], arr[high] = arr[high], arr[i + 1]
    return i + 1
```

## Quand utiliser le Tri Rapide ?

**Idéal pour :**
- Grandes quantités de données
- Données aléatoires
- Quand la performance est critique

**Éviter pour :**
- Petits ensembles de données (tri par insertion peut être meilleur)
- Données presque triées (risque de pire cas)
- Quand la stabilité est requise

## Concepts clés du Chapitre 4

1. **Diviser pour régner** : Partitionner puis résoudre récursivement
2. **Pivot** : Élément crucial pour la performance
3. **Complexité variable** : O(n log n) en moyenne, O(n²) dans le pire cas
4. **Tri sur place** : Optimisation mémoire

## Points à retenir

- Le Tri Rapide est généralement plus rapide que les autres algorithmes de tri
- Le choix du pivot affecte considérablement la performance
- La complexité varie entre O(n log n) et O(n²)
- C'est un excellent exemple d'algorithme "diviser pour régner"
- La version sur place économise de la mémoire mais est plus complexe

---
*Extrait essentiel du Chapitre 4 de "Grokking Algorithms" par Aditya Y. Bhargava*
