# Chapitre 11 - Vers où aller ensuite

## Introduction aux algorithmes avancés

Après avoir maîtrisé les concepts fondamentaux, voici une sélection d'algorithmes et techniques plus avancés qui étendent votre boîte à outils algorithmique.

## Arbres (Trees)

### Qu'est-ce qu'un arbre ?
Un **arbre** est une structure de données hiérarchique avec un nœud racine et des nœuds enfants. Contrairement aux graphes généraux, les arbres n'ont pas de cycles.

### Types d'arbres courants

#### Arbres binaires de recherche (BST)
```
       8
      / \
     3   10
    / \    \
   1   6    14
      / \   /
     4   7 13
```

**Propriétés** :
- Sous-arbre gauche < nœud parent
- Sous-arbre droit > nœud parent
- Recherche, insertion, suppression : O(log n) en moyenne

#### Arbres AVL et Rouge-Noir
- **Arbres équilibrés** : Maintiennent l'équilibre automatiquement
- **Garantie** : O(log n) dans tous les cas
- **Usage** : Bases de données, systèmes de fichiers

#### Arbres B et B+
- **Arbres à plusieurs branches** : Plus de 2 enfants par nœud
- **Usage** : Indexation de bases de données
- **Avantage** : Réduisent les accès disque

#### Trie (Arbre de préfixes)
```
     r
    / \
   a   o
  / \   \
 t   d   o
     /   /
    y   t
```
- **Usage** : Dictionnaires, auto-complétion
- **Avantage** : Recherche de préfixes O(k) où k = longueur du mot

### Applications des arbres
- **Systèmes de fichiers** : Structure hiérarchique
- **Compilateurs** : Arbres syntaxiques
- **Bases de données** : Indexation
- **Réseaux** : Arbres de spanning, routage

## Index inversés (Inverted Indexes)

### Qu'est-ce qu'un index inversé ?
Un **index inversé** mappe du contenu vers les documents qui le contiennent. C'est comme l'index d'un livre mais inversé.

### Exemple simple
```
Documents :
D1 : "le chat mange"
D2 : "le chien aboie"
D3 : "chat et chien"

Index inversé :
"le" → [D1, D2]
"chat" → [D1, D3]
"mange" → [D1]
"chien" → [D2, D3]
"aboie" → [D2]
"et" → [D3]
```

### Applications
- **Moteurs de recherche** : Google, Bing, etc.
- **Systèmes de fichiers** : Recherche de contenu
- **Bases de données** : Recherche textuelle

### Implémentation simple
```python
def create_inverted_index(documents):
    index = {}
    
    for doc_id, content in documents.items():
        words = content.lower().split()
        for word in words:
            if word not in index:
                index[word] = []
            if doc_id not in index[word]:
                index[word].append(doc_id)
    
    return index

def search(index, query):
    words = query.lower().split()
    if words[0] in index:
        return index[words[0]]
    return []
```

## Transformée de Fourier

### Qu'est-ce que c'est ?
La **transformée de Fourier** décompose un signal en ses fréquences composantes. C'est comme analyser un accord musical pour identifier chaque note.

### Applications
- **Traitement audio** : Compression MP3, égalisation
- **Traitement d'images** : Compression JPEG, filtrage
- **Télécommunications** : Modulation, détection de signaux
- **Analyse financière** : Cycles économiques, tendances

### Principe de base
```python
import numpy as np

# Signal simple : somme de sinusoïdes
t = np.linspace(0, 1, 1000)
signal = np.sin(2 * np.pi * 10 * t) + 0.5 * np.sin(2 * np.pi * 20 * t)

# Transformée de Fourier
fft_result = np.fft.fft(signal)
frequencies = np.fft.fftfreq(len(t), t[1] - t[0])

# Les pics dans le résultat montrent les fréquences dominantes
```

## Algorithmes parallèles

### Pourquoi le parallélisme ?
- **Limite du séquentiel** : Les processeurs atteignent des limites physiques
- **Données massives** : Big data nécessite des traitements distribués
- **Performance** : Diviser pour régner appliqué au calcul

### Types de parallélisme
1. **Parallélisme de données** : Même opération sur différentes données
2. **Parallélisme de tâches** : Différentes opérations en même temps
3. **Pipeline** : Chaîne de traitement

### Exemple : Somme parallèle
```python
import multiprocessing

def parallel_sum(numbers, num_processes=4):
    chunk_size = len(numbers) // num_processes
    chunks = [numbers[i:i+chunk_size] for i in range(0, len(numbers), chunk_size)]
    
    with multiprocessing.Pool(num_processes) as pool:
        partial_sums = pool.map(sum, chunks)
    
    return sum(partial_sums)
```

## MapReduce

### Qu'est-ce que MapReduce ?
**MapReduce** est un modèle de programmation pour traiter de grands ensembles de données en parallèle sur des clusters.

### Pourquoi les algorithmes distribués sont utiles ?
- **Échelle** : Traiter des téraoctets de données
- **Tolérance aux pannes** : Si un nœud tombe, les autres continuent
- **Coût** : Matériel bon marché vs supercalculateurs

### La fonction Map
```python
def map_function(document):
    # Émettre des paires (clé, valeur)
    words = document.lower().split()
    return [(word, 1) for word in words]

# Exemple :
# "le chat mange" → [("le", 1), ("chat", 1), ("mange", 1)]
```

### La fonction Reduce
```python
def reduce_function(key, values):
    # Agréger les valeurs pour une clé
    return key, sum(values)

# Exemple :
# ("chat", [1, 1, 1]) → ("chat", 3)
```

### Exemple complet : Comptage de mots
```python
def word_count_mapreduce(documents):
    # Phase Map
    mapped = []
    for doc in documents:
        mapped.extend(map_function(doc))
    
    # Phase Shuffle (groupe par clé)
    grouped = {}
    for key, value in mapped:
        if key not in grouped:
            grouped[key] = []
        grouped[key].append(value)
    
    # Phase Reduce
    results = []
    for key, values in grouped.items():
        results.append(reduce_function(key, values))
    
    return results
```

## Filtres de Bloom et HyperLogLog

### Filtres de Bloom

#### Qu'est-ce que c'est ?
Un **filtre de Bloom** est une structure de données probabiliste qui teste si un élément est dans un ensemble, avec possibilité de faux positifs mais jamais de faux négatifs.

#### Applications
- **Vérification d'existence** : "Cet email existe déjà ?"
- **Optimisation de cache** : "Cette donnée est-elle en cache ?"
- **Sécurité** : Détection de mots de passe faibles

#### Fonctionnement
```python
import mmh3
from bitarray import bitarray

class BloomFilter:
    def __init__(self, size, hash_count):
        self.size = size
        self.hash_count = hash_count
        self.bit_array = bitarray(size)
        self.bit_array.setall(False)
    
    def add(self, item):
        for i in range(self.hash_count):
            index = mmh3.hash(item, i) % self.size
            self.bit_array[index] = True
    
    def check(self, item):
        for i in range(self.hash_count):
            index = mmh3.hash(item, i) % self.size
            if not self.bit_array[index]:
                return False
        return True
```

#### Propriétés
- **Faux positifs possibles** : Dit "présent" alors que non
- **Jamais de faux négatifs** : Dit "absent" seulement si vraiment absent
- **Espace efficace** : Beaucoup moins de mémoire qu'un set

### HyperLogLog

#### Qu'est-ce que c'est ?
**HyperLogLog** est un algorithme pour estimer le nombre d'éléments uniques dans un grand ensemble avec très peu de mémoire.

#### Applications
- **Analytics** : Nombre d'utilisateurs uniques
- **Monitoring** : Nombre d'IP uniques
- **Big data** : Cardinalité approximative

## Algorithmes SHA

### Qu'est-ce que SHA ?
**SHA (Secure Hash Algorithm)** est une famille de fonctions de hachage cryptographiques.

### Applications

#### Comparaison de fichiers
```python
import hashlib

def file_hash(filename):
    hasher = hashlib.sha256()
    with open(filename, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    return hasher.hexdigest()
```

#### Vérification de mots de passe
```python
def hash_password(password, salt):
    return hashlib.sha256((password + salt).encode()).hexdigest()

def verify_password(password, salt, hashed):
    return hash_password(password, salt) == hashed
```

### Propriétés
- **Déterministe** : Même entrée → même sortie
- **Non réversible** : Impossible de retrouver l'entrée
- **Effet avalanche** : Petit changement → grand changement
- **Résistance aux collisions** : Difficile de trouver deux entrées avec même sortie

## Hachage sensible à la localité (LSH)

### Qu'est-ce que c'est ?
**LSH (Locality-Sensitive Hashing)** est une technique de hachage qui place des éléments similaires dans les mêmes "buckets".

### Applications
- **Recherche approximative** : Images similaires, documents similaires
- **Déduplication** : Trouver des doublons approximatifs
- **Recommandation** : Produits similaires

### Principe
```python
import numpy as np

def lsh_hash(vectors, num_planes):
    # Plans aléatoires pour diviser l'espace
    planes = np.random.randn(num_planes, vectors.shape[1])
    
    # Calculer quel côté de chaque plan
    hash_codes = np.sign(np.dot(vectors, planes.T))
    
    return hash_codes
```

## Échange de clés Diffie-Hellman

### Qu'est-ce que c'est ?
**Diffie-Hellman** est un protocole cryptographique qui permet à deux parties d'établir une clé secrète partagée sur un canal non sécurisé.

### Applications
- **TLS/SSL** : Sécurisation des communications web
- **VPN** : Connexions sécurisées
- **Messagerie** : Chiffrement de bout en bout

### Principe de base
```python
import random

def diffie_hellman():
    # Paramètres publics (généralement prédéfinis)
    p = 23  # Nombre premier
    g = 5   # Générateur
    
    # Secrets privés
    a = random.randint(1, p-1)  # Secret d'Alice
    b = random.randint(1, p-1)  # Secret de Bob
    
    # Échanges publics
    A = pow(g, a, p)  # Public d'Alice
    B = pow(g, b, p)  # Public de Bob
    
    # Calcul du secret partagé
    secret_alice = pow(B, a, p)
    secret_bob = pow(A, b, p)
    
    # secret_alice == secret_bob (personne d'autre ne peut le calculer)
    return secret_alice == secret_bob
```

## Programmation linéaire

### Qu'est-ce que c'est ?
La **programmation linéaire** est une méthode d'optimisation où l'objectif et les contraintes sont des équations linéaires.

### Applications
- **Optimisation de ressources** : Allocation, planification
- **Finance** : Portefeuilles optimaux
- **Logistique** : Routes optimales
- **Production** : Maximisation des profits

### Exemple simple
```
Maximiser : profit = 3x + 5y
Contraintes :
    x + 2y ≤ 10
    3x + y ≤ 15
    x ≥ 0, y ≥ 0
```

## Épilogue : Votre parcours algorithmique

### Ce que vous avez appris
- **Structures de données** : Tableaux, listes, piles, files, arbres, graphes
- **Algorithmes fondamentaux** : Tri, recherche, parcours
- **Techniques avancées** : Programmation dynamique, algorithmes gloutons
- **Applications pratiques** : Machine learning, cryptographie

### Prochaines étapes
1. **Pratique** : Implémentez ces algorithmes
2. **Problèmes** : Résolvez des challenges sur des plateformes
3. **Théorie** : Approfondissez la complexité algorithmique
4. **Spécialisation** : Choisissez un domaine qui vous intéresse

### Ressources continues
- **Livres** : "Introduction to Algorithms" (CLRS)
- **Cours** : MIT OpenCourseWare, Coursera
- **Problèmes** : LeetCode, HackerRank, Project Euler
- **Communauté** : Stack Overflow, GitHub, forums spécialisés

### L'algorithmique dans votre carrière
- **Développement logiciel** : Algorithmes efficaces
- **Data Science** : Machine learning, analyse
- **Recherche** : Algorithmique théorique
- **Entreprise** : Optimisation, scalabilité

## Concepts clés du Chapitre 11

1. **Spécialisation** : Différents algorithmes pour différents problèmes
2. **Scalabilité** : Algorithmes distribués pour big data
3. **Probabiliste** : Structures de données avec garanties statistiques
4. **Cryptographie** : Sécurité et échange sécurisé

## Points à retenir

- Les arbres sont fondamentaux en informatique
- Les algorithmes distribués traitent des données massives
- Les structures probabilistes économisent de la mémoire
- La cryptographie protège nos communications
- L'apprentissage algorithmique est un parcours continu

---
*Extrait essentiel du Chapitre 11 de "Grokking Algorithms" par Aditya Y. Bhargava*
