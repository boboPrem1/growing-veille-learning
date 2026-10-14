# Chapitre 8 - Arbres couvrants de poids minimum

## Qu'est-ce qu'un arbre couvrant de poids minimum ?

Un **arbre couvrant de poids minimum (MST)** est un sous-ensemble d'arêtes d'un graphe connexe qui :
- Connecte tous les nœuds
- Ne contient aucun cycle
- A le poids total minimum possible

## Problème type : Réseau électrique

### Scénario
Vous devez connecter plusieurs villes avec des lignes électriques au coût minimum.

### Contraintes
- Toutes les villes doivent être connectées
- Pas de cycles (inutile et coûteux)
- Coût total minimal

## Algorithmes pour les MST

### 1. Algorithme de Kruskal
- **Approche** : Ajouter les arêtes les moins chères qui ne créent pas de cycle
- **Structure** : Trie des arêtes par poids
- **Détection de cycles** : Union-Find (Disjoint Set)

### 2. Algorithme de Prim
- **Approche** : Faire pousser l'arbre à partir d'un nœud
- **Structure** : Similaire à Dijkstra
- **Choix** : Arête la moins chère connectant l'arbre

## Algorithme de Kruskal

### Étapes
1. **Trier** toutes les arêtes par poids croissant
2. **Initialiser** chaque nœud comme composant séparé
3. **Pour chaque arête** (dans l'ordre) :
   - Si elle connecte deux composants différents : l'ajouter
   - Sinon : l'ignorer (créerait un cycle)

### Exemple
```
Arêtes triées : (1,2):1, (3,4):2, (1,3):3, (2,4):4
Étape 1 : Ajouter (1,2):1
Étape 2 : Ajouter (3,4):2  
Étape 3 : Ajouter (1,3):3 → Connexe !
Étape 4 : Ignorer (2,4):4 (créerait un cycle)
```

### Implémentation
```python
class UnionFind:
    def __init__(self, n):
        self.parent = list(range(n))
        self.rank = [0] * n
    
    def find(self, x):
        if self.parent[x] != x:
            self.parent[x] = self.find(self.parent[x])
        return self.parent[x]
    
    def union(self, x, y):
        root_x = self.find(x)
        root_y = self.find(y)
        
        if root_x == root_y:
            return False  # Déjà connecté
        
        if self.rank[root_x] < self.rank[root_y]:
            self.parent[root_x] = root_y
        elif self.rank[root_x] > self.rank[root_y]:
            self.parent[root_y] = root_x
        else:
            self.parent[root_y] = root_x
            self.rank[root_x] += 1
        
        return True

def kruskal(graph):
    edges = []
    for u in graph:
        for v, weight in graph[u].items():
            edges.append((weight, u, v))
    
    edges.sort()  # Trier par poids
    uf = UnionFind(len(graph))
    mst = []
    total_weight = 0
    
    for weight, u, v in edges:
        if uf.union(u, v):
            mst.append((u, v, weight))
            total_weight += weight
    
    return mst, total_weight
```

## Algorithme de Prim

### Étapes
1. **Choisir** un nœud de départ
2. **Ajouter** toutes ses arêtes à une file de priorité
3. **Tant que** l'arbre n'est pas complet :
   - Prendre l'arête la moins chère
   - Si elle connecte un nouveau nœud : l'ajouter
   - Ajouter les nouvelles arêtes de ce nœud

### Implémentation
```python
import heapq

def prim(graph, start):
    visited = set()
    min_heap = [(0, start, None)]  # (poids, nœud, parent)
    mst = []
    total_weight = 0
    
    while min_heap and len(visited) < len(graph):
        weight, node, parent = heapq.heappop(min_heap)
        
        if node in visited:
            continue
        
        visited.add(node)
        
        if parent is not None:
            mst.append((parent, node, weight))
            total_weight += weight
        
        for neighbor, edge_weight in graph[node].items():
            if neighbor not in visited:
                heapq.heappush(min_heap, (edge_weight, neighbor, node))
    
    return mst, total_weight
```

## Comparaison Kruskal vs Prim

| Caractéristique | Kruskal | Prim |
|-----------------|---------|------|
| Approche | Arêtes globales | Croissance depuis un nœud |
| Structure | Union-Find | File de priorité |
| Complexité | O(E log E) | O(E log V) |
| Usage | Graphes peu denses | Graphes denses |
| Implémentation | Plus simple | Similaire à Dijkstra |

## Applications des MST

### 1. Réseaux
- **Électrique** : Connecter villes au coût minimum
- **Télécommunication** : Déployer fibre optique
- **Eau** : Réseau de distribution

### 2. Transport
- **Routes** : Réseau routier minimal
- **Métro** : Lignes optimales
- **Aviation** : Hub et spoke

### 3. Informatique
- **Clustering** : Regroupement de données
- **Image** : Segmentation d'images
- **Circuits** : Design de PCB

## Exemple pratique : Réseau de villes

### Graphe
```
A --(4)-- B --(8)-- C
| \       |       |
(3) (1)   (2)     (6)
|   \     |       |
D --(7)-- E --(5)-- F
```

### Kruskal étape par étape
1. **(1) A-E** : Ajouter
2. **(2) B-C** : Ajouter  
3. **(3) A-D** : Ajouter
4. **(4) A-B** : Ajouter (connecte composants)
5. **(5) E-F** : Ajouter
6. **(6) C-F** : Ignorer (crée cycle)
7. **(7) D-E** : Ignorer (crée cycle)
8. **(8) B-C** : Ignorer (crée cycle)

**MST final** : A-E, B-C, A-D, A-B, E-F
**Poids total** : 1 + 2 + 3 + 4 + 5 = 15

## Propriétés importantes

### Unicité
- Le MST n'est pas toujours unique
- Si plusieurs arêtes ont le même poids, plusieurs MST possibles

### Coupe (Cut Property)
- Pour toute partition du graphe, l'arête minimum traversant la coupe est dans un MST

### Cycle (Cycle Property)
- L'arête maximum dans tout cycle n'est dans aucun MST

## Limitations et extensions

### Graphes non pondérés
- Tous les MST ont le même poids
- Nombre d'arêtes = V - 1

### Graphes déconnectés
- Pas de MST possible
- Solution : Forêt couvrante minimum

### Graphes dirigés
- MST non défini
- Alternative : Arborescence couvrante minimum

## Concepts clés du Chapitre 8

1. **Arbre couvrant** : Connecte tous les nœuds sans cycle
2. **Optimalité** : Poids total minimum
3. **Kruskal** : Approche par arêtes triées
4. **Prim** : Approche par croissance d'arbre

## Points à retenir

- MST connecte tous les nœuds au coût minimum sans cycles
- Deux algorithmes principaux : Kruskal et Prim
- Kruskal utilise Union-Find, Prim utilise file de priorité
- Applications : réseaux, clustering, design
- Propriétés : unicité non garantie, coupe et cycle

---
*Extrait essentiel du Chapitre 8 de "Grokking Algorithms" par Aditya Y. Bhargava*
