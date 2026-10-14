# Chapitre 3 - Récursivité

## Qu'est-ce que la récursivité ?

La **récursivité** est une technique où une fonction s'appelle elle-même pour résoudre un problème. C'est comme une poupée russe - chaque poupée contient une poupée plus petite.

## Structure d'une fonction récursive

Toute fonction récursive a deux parties essentielles :

1. **Cas de base** : Condition qui arrête la récursion
2. **Cas récursif** : La fonction s'appelle avec un problème plus petit

```python
def countdown(i):
    if i <= 0:           # Cas de base
        return
    else:                # Cas récursif
        print(i)
        countdown(i - 1)
```

## La pile d'appels (Call Stack)

### Comment ça fonctionne ?
- Chaque appel récursif est empilé
- Quand le cas de base est atteint, les appels sont dépilés
- L'ordinateur utilise une **pile d'appels** pour suivre les fonctions

### Exemple : Factorielle
```python
def factorial(n):
    if n == 1:           # Cas de base
        return 1
    else:                # Cas récursif
        return n * factorial(n - 1)
```

**Exécution pour factorial(3) :**
```
factorial(3) → 3 * factorial(2)
factorial(2) → 2 * factorial(1)
factorial(1) → 1 (cas de base)
```

## Avantages de la récursivité

- **Code élégant** : Solutions plus simples et plus lisibles
- **Diviser pour régner** : Parfait pour les problèmes complexes
- **Naturel** : Certains problèmes sont naturellement récursifs

## Inconvénients et pièges

1. **Dépassement de pile** : Trop d'appels récursifs
2. **Performance** : Parfois plus lent que l'itératif
3. **Cas de base oublié** : Boucle infinie !

## Exemple : Somme d'un tableau

### Approche récursive
```python
def sum_array(arr):
    if len(arr) == 1:           # Cas de base
        return arr[0]
    else:                       # Cas récursif
        return arr[0] + sum_array(arr[1:])
```

### Approche itérative (pour comparaison)
```python
def sum_array_iterative(arr):
    total = 0
    for num in arr:
        total += num
    return total
```

## Quand utiliser la récursivité ?

**Idéal pour :**
- Arbres et graphes
- Algorithmes "diviser pour régner"
- Problèmes mathématiques (factorielle, Fibonacci)
- Tri rapide, fusion de tri

**Éviter pour :**
- Problèmes simples avec boucles
- Quand la performance est critique
- Quand il y a risque de dépassement de pile

## Récursivité vs Itération

| Critère | Récursivité | Itération |
|---------|-------------|-----------|
| Lisibilité | Souvent plus claire | Parfois plus complexe |
| Performance | Plus lente (pile) | Plus rapide |
| Mémoire | O(n) pour la pile | O(1) |
| Débogage | Plus difficile | Plus facile |

## Concepts clés du Chapitre 3

1. **Cas de base** : Essentiel pour éviter les boucles infinies
2. **Pile d'appels** : Comment l'ordinateur gère la récursion
3. **Diviser pour régner** : Principe fondamental
4. **Compromis** : Élégance vs performance

## Points à retenir

- Toute fonction récursive doit avoir un cas de base
- La pile d'appels a une taille limitée
- La récursivité rend certains algorithmes beaucoup plus simples
- Choisir entre récursivité et itération selon le problème
- La récursivité est naturelle pour les structures arborescentes

---
*Extrait essentiel du Chapitre 3 de "Grokking Algorithms" par Aditya Y. Bhargava*
