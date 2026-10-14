# Chapitre 6 - Parcours en largeur (Breadth-First Search)

## Qu'est-ce que le parcours en largeur ?

Le **parcours en largeur (BFS)** est un algorithme de recherche dans un graphe qui explore les nœuds par niveaux, du plus proche au plus éloigné. C'est comme des ondulations dans l'eau - on explore de proche en proche.

## Application principale : Le plus court chemin

### Problème type
Trouver le chemin le plus court entre deux personnes dans un réseau social.

### Exemple concret
- Vous → Amis → Amis d'amis → Amis d'amis d'amis
- BFS trouve automatiquement le chemin le plus court

## Comment fonctionne BFS ?

### Étapes :
1. **Créer une file d'attente** avec le point de départ
2. **Créer un ensemble** des nœuds déjà visités
3. **Tant que la file n'est pas vide** :
   - Retirer le premier nœud
   - Vérifier si c'est la cible
   - Ajouter tous ses voisins non visités à la file

### Exemple : Réseau social

```python
from collections import deque

def bfs_search(graph, start, target):
    search_queue = deque()
    search_queue += graph[start]
    searched = set()
    
    while search_queue:
        person = search_queue.popleft()
        if person not in searched:
            if person == target:
                return True  # Trouvé !
            search_queue += graph[person]
            searched.add(person)
    return False  # Non trouvé
```

## Files d'attente (Queues)

### FIFO : First In, First Out
- **Structure** : Premier entré, premier sorti
- **Usage** : Essentiel pour BFS
- **Opérations** :
  - `enqueue` : Ajouter à la fin
  - `dequeue` : Retirer du début

### Implémentation en Python
```python
from collections import deque

# Création
queue = deque()

# Ajout (enqueue)
queue.append("A")
queue.append("B")
queue.append("C")

# Retrait (dequeue)
first = queue.popleft()  # "A"
```

## Exemple détaillé : Trouver un vendeur de mangues

### Graphe des relations
```
Vous → [Alice, Bob, Claire]
Alice → [Peggy]
Bob → [Anuj, Peggy]
Claire → [Thom, Jonny]
Peggy → []
Anuj → []
Thom → [Vendeur de mangues]
Jonny → []
```

### Exécution BFS
1. **File initiale** : [Alice, Bob, Claire]
2. **Traiter Alice** : Ajouter Peggy
3. **Traiter Bob** : Ajouter Anuj, Peggy (déjà dans file)
4. **Traiter Claire** : Ajouter Thom, Jonny
5. **Traiter Peggy** : Pas de voisins
6. **Traiter Anuj** : Pas de voisins
7. **Traiter Thom** : Trouvé vendeur de mangues !

## Arbres vs Graphes

### Arbres
- **Structure** : Hiérarchique, pas de cycles
- **BFS** : Trouve le chemin le plus court
- **Usage** : Arbres binaires, structures organisationnelles

### Graphes
- **Structure** : Connexions arbitraires, peut avoir des cycles
- **BFS** : Trouve le chemin le plus court en nombre d'arêtes
- **Usage** : Réseaux sociaux, cartes, dépendances

## Complexité de BFS

### Temps : O(V + E)
- **V** : Nombre de nœuds (vertices)
- **E** : Nombre d'arêtes (edges)
- Chaque nœud est visité une fois
- Chaque arête est examinée une fois

### Espace : O(V)
- File d'attente : O(V) dans le pire cas
- Ensemble visités : O(V)

## Applications de BFS

### 1. Réseaux sociaux
- Trouver les amis d'amis
- Calculer le degré de séparation

### 2. Jeux
- Plus court chemin dans un labyrinthe
- IA pour déplacement de personnages

### 3. Réseaux informatiques
- Routage de paquets
- Détection de cycles

### 4. Recommandations
- "Les personnes qui ont aimé X ont aussi aimé Y"
- Suggestion de connexions

## BFS vs DFS (Depth-First Search)

| Caractéristique | BFS | DFS |
|-----------------|-----|-----|
| Structure | File d'attente | Pile |
| Exploration | Par niveaux | En profondeur |
| Plus court chemin | Oui | Non |
| Mémoire | O(V) | O(V) mais souvent moins |
| Usage | Chemin le plus court | Exploration complète |

## Implémentation complète avec chemin

```python
def bfs_shortest_path(graph, start, target):
    queue = deque([(start, [start])])
    visited = set()
    
    while queue:
        current, path = queue.popleft()
        
        if current == target:
            return path
            
        if current not in visited:
            visited.add(current)
            for neighbor in graph[current]:
                if neighbor not in visited:
                    queue.append((neighbor, path + [neighbor]))
    
    return None  # Pas de chemin trouvé
```

## Concepts clés du Chapitre 6

1. **File d'attente** : Structure FIFO essentielle
2. **Exploration par niveaux** : Du plus proche au plus éloigné
3. **Plus court chemin** : BFS garantit le chemin minimal
4. **Graphes** : Structure de données flexible

## Points à retenir

- BFS trouve automatiquement le chemin le plus court
- Les files d'attente (FIFO) sont cruciales pour l'algorithme
- La complexité est O(V + E) - linéaire
- Applications : réseaux sociaux, jeux, recommandations
- Essentiel de marquer les nœuds visités pour éviter les cycles

---
*Extrait essentiel du Chapitre 6 de "Grokking Algorithms" par Aditya Y. Bhargava*
