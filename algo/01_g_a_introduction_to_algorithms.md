# Chapitre 1 - Introduction aux Algorithmes

## Qu'est-ce qu'un algorithme ?

Un **algorithme** est un ensemble d'instructions étape par étape pour accomplir une tâche. C'est comme une recette de cuisine - vous suivez des instructions précises dans un ordre spécifique pour obtenir un résultat.

## Pourquoi apprendre les algorithmes ?

- **Efficacité** : Les bons algorithmes résolvent les problèmes plus rapidement
- **Scalabilité** : Ils fonctionnent bien même avec de grandes quantités de données
- **Résolution de problèmes** : Ils nous aident à penser de manière structurée

## Exemple : Recherche binaire

### Le problème
Trouver un nombre dans une liste triée de 100 éléments.

### Approche naïve (recherche linéaire)
- Vérifier chaque élément un par un
- Au pire : 100 vérifications

### Approche intelligente (recherche binaire)
- Diviser la liste en deux à chaque étape
- Éliminer la moitié des possibilités à chaque fois
- Au pire : log₂(100) ≈ 7 vérifications

## Notation Big O

La **notation Big O** décrit comment le temps d'exécution d'un algorithme augmente avec la taille des données :

- **O(1)** - Temps constant : toujours le même temps
- **O(log n)** - Temps logarithmique : très efficace (recherche binaire)
- **O(n)** - Temps linéaire : proportionnel à la taille (recherche linéaire)
- **O(n²)** - Temps quadratique : beaucoup plus lent

## Concepts clés du Chapitre 1

1. **Algorithme vs Programme** : Un algorithme est la logique, un programme est l'implémentation
2. **Efficacité** : Certains algorithmes sont fondamentalement plus rapides que d'autres
3. **Complexité** : Big O nous aide à comparer les algorithmes
4. **Diviser pour régner** : La recherche binaire illustre ce principe puissant

## Points à retenir

- Les algorithmes sont fondamentaux en informatique
- Le choix du bon algorithme peut faire une énorme différence de performance
- La notation Big O est essentielle pour comparer les algorithmes
- La recherche binaire est un exemple parfait d'algorithme efficace

---
*Extrait essentiel du Chapitre 1 de "Grokking Algorithms" par Aditya Y. Bhargava*