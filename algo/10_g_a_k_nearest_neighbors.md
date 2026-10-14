# Chapitre 10 - K-plus proches voisins (K-Nearest Neighbors)

## Qu'est-ce que K-NN ?

**K-NN (K-Nearest Neighbors)** est un algorithme d'apprentissage automatique qui classe de nouvelles données en se basant sur les K données les plus similaires dans le jeu d'entraînement.

## Principe fondamental

### "Dis-moi qui sont tes amis, je te dirai qui tu es"
- Trouver les K voisins les plus proches
- Voter pour la classe majoritaire
- Prédire basée sur cette majorité

## Classification : Oranges vs Pamplemousses

### Jeu de données d'entraînement
```
Taille (cm) | Couleur (0-10) | Fruit
-----------|----------------|-------
8          | 7              | Orange
9          | 8              | Orange  
10         | 6              | Orange
12         | 3              | Pamplemousse
13         | 4              | Pamplemousse
14         | 2              | Pamplemousse
```

### Nouvelle donnée à classer
```
Taille : 11cm
Couleur : 5
```

### Calcul des distances (distance euclidienne)
```
Distance(Orange1) = √((11-8)² + (5-7)²) = √(9 + 4) = √13 ≈ 3.6
Distance(Orange2) = √((11-9)² + (5-8)²) = √(4 + 9) = √13 ≈ 3.6
Distance(Orange3) = √((11-10)² + (5-6)²) = √(1 + 1) = √2 ≈ 1.4
Distance(Pample1) = √((11-12)² + (5-3)²) = √(1 + 4) = √5 ≈ 2.2
Distance(Pample2) = √((11-13)² + (5-4)²) = √(4 + 1) = √5 ≈ 2.2
Distance(Pample3) = √((11-14)² + (5-2)²) = √(9 + 9) = √18 ≈ 4.2
```

### Avec K=3 (3 voisins les plus proches)
1. Orange3 (distance 1.4)
2. Pample1 (distance 2.2) 
3. Pample2 (distance 2.2)

**Résultat** : 1 Orange, 2 Pamplemousses → **Pamplemousse**

## Implémentation de K-NN

```python
import math
from collections import Counter

def euclidean_distance(point1, point2):
    return math.sqrt(sum((p1 - p2) ** 2 for p1, p2 in zip(point1, point2)))

def knn_classify(training_data, new_point, k=3):
    # Calculer toutes les distances
    distances = []
    for point, label in training_data:
        dist = euclidean_distance(point, new_point)
        distances.append((dist, label))
    
    # Trier par distance et prendre les K plus proches
    distances.sort(key=lambda x: x[0])
    k_nearest = distances[:k]
    
    # Voter pour la classe majoritaire
    labels = [label for _, label in k_nearest]
    most_common = Counter(labels).most_common(1)[0][0]
    
    return most_common
```

## Système de recommandation

### Exemple : Recommandation de films
```
Utilisateurs et notes (1-5) :
Alice :   [Action:5, Comédie:2, Drame:4]
Bob :     [Action:1, Comédie:5, Drame:2]
Charlie : [Action:4, Comédie:3, Drame:5]
David :   [Action:2, Comédie:4, Drame:1]

Nouvel utilisateur : [Action:?, Comédie:5, Drame:?]
```

### Trouver les voisins similaires
- Calculer la distance entre les utilisateurs
- Trouver les K utilisateurs les plus similaires
- Recommander ce qu'ils ont aimé

## Extraction de caractéristiques (Feature Extraction)

### Qu'est-ce qu'une caractéristique ?
Une **caractéristique** est une propriété mesurable d'un objet qui aide à le classifier.

### Exemples de caractéristiques
- **Fruits** : taille, poids, couleur, texture
- **Textes** : nombre de mots, fréquence des termes, longueur
- **Images** : couleurs, formes, textures, luminosité
- **Clients** : âge, revenus, achats, localisation

### Bonnes caractéristiques
1. **Discriminantes** : Séparent bien les classes
2. **Indépendantes** : Non corrélées entre elles
3. **Normalisées** : Même échelle de valeurs
4. **Pertinentes** : Liées au problème

### Mauvaises caractéristiques
- Trop de bruit
- Échelles très différentes
- Non pertinentes
- Trop corrélées

## Régression vs Classification

### Classification
- **Objectif** : Prédire une catégorie
- **Sortie** : Classe discrète (Orange/Pamplemousse)
- **Méthode** : Vote majoritaire des K voisins

### Régression  
- **Objectif** : Prédire une valeur numérique
- **Sortie** : Valeur continue (prix, température)
- **Méthode** : Moyenne des K voisins

### Exemple de régression
```
Taille appartement (m²) | Prix (€)
----------------------|-----------
30                    | 800
45                    | 1200
60                    | 1500
75                    | 1800
90                    | 2200

Nouvel appartement : 55m² → Prix prédit ?
```

## Choix de K

### Effet de K sur les prédictions

**K petit (ex: K=1)**
- **Avantage** : Très sensible aux variations locales
- **Inconvénient** : Vulnérable au bruit, overfitting

**K grand (ex: K=10)**
- **Avantage** : Plus robuste au bruit
- **Inconvénient** : Moins précis, peut lisser les détails

### Règle générale
- **Commencer** avec K = √n (où n = nombre d'échantillons)
- **Tester** différentes valeurs de K
- **Utiliser** la validation croisée pour choisir le meilleur K

## Normalisation des caractéristiques

### Pourquoi normaliser ?
Les caractéristiques avec de grandes échelles dominent la distance :

```
Sans normalisation :
Taille (cm) : 150-200
Poids (g) : 50000-80000
→ Le poids domine complètement la distance !
```

### Méthodes de normalisation

**Min-Max Scaling**
```python
def min_max_scaling(values):
    min_val, max_val = min(values), max(values)
    return [(x - min_val) / (max_val - min_val) for x in values]
```

**Standardisation (Z-score)**
```python
def standardization(values):
    mean = sum(values) / len(values)
    std = (sum((x - mean) ** 2 for x in values) / len(values)) ** 0.5
    return [(x - mean) / std for x in values]
```

## Applications de K-NN

### 1. Reconnaissance optique de caractères (OCR)
- **Caractéristiques** : pixels, contours, textures
- **Usage** : Lecture de documents, reconnaissance d'écriture

### 2. Filtres anti-spam
- **Caractéristiques** : mots-clés, fréquence, expéditeur
- **Classification** : Spam vs Non-spam

### 3. Prédiction boursière
- **Caractéristiques** : volumes, prix historiques, indicateurs
- **Régression** : Prédiction du prix futur

### 4. Diagnostic médical
- **Caractéristiques** : symptômes, analyses, antécédents
- **Classification** : Maladie vs Sain

## Avantages et inconvénients

### Avantages
- **Simple** à comprendre et implémenter
- **Non paramétrique** : aucune hypothèse sur les données
- **Flexible** : fonctionne pour classification et régression
- **Adaptatif** : s'ajuste automatiquement aux données

### Inconvénients
- **Coûteux** en calcul avec beaucoup de données
- **Sensible** au choix de K et des caractéristiques
- **Mémoire** : doit stocker toutes les données d'entraînement
- **Curse of dimensionality** : performances dégradées avec beaucoup de caractéristiques

## Introduction au Machine Learning

### Types d'apprentissage
1. **Supervisé** : Données étiquetées (comme K-NN)
2. **Non supervisé** : Pas d'étiquettes, trouver des patterns
3. **Par renforcement** : Récompenses/punitions

### K-NN dans l'écosystème ML
- **Algorithme de base** : bon pour commencer
- **Baseline** : référence pour comparer d'autres algorithmes
- **Éducatif** : enseigne les concepts fondamentaux

## Concepts clés du Chapitre 10

1. **Similarité** : Mesure de distance entre points
2. **Vote majoritaire** : Principe de classification
3. **Caractéristiques** : Propriétés discriminantes
4. **Normalisation** : Mise à l'échelle des données

## Points à retenir

- K-NN classe en se basant sur les K voisins les plus proches
- Le choix des caractéristiques est crucial pour la performance
- La normalisation évite qu'une caractéristique domine les autres
- K petit = sensible, K grand = robuste
- Applications : OCR, spam, prédiction, diagnostic médical

---
*Extrait essentiel du Chapitre 10 de "Grokking Algorithms" par Aditya Y. Bhargava*
