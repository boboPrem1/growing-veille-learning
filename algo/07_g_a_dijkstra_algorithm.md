# Chapitre 7 - Algorithmes de Dijkstra

## Qu'est-ce que l'algorithme de Dijkstra ?

L'**algorithme de Dijkstra** est un algorithme qui trouve le chemin le plus court dans un graphe pondéré. Contrairement à BFS, il prend en compte le "coût" ou "poids" de chaque arête.

## BFS vs Dijkstra

### BFS (Chapitre 6)
- **Graphe non pondéré** : Toutes les arêtes ont le même coût
- **Objectif** : Minimum d'arêtes
- **Usage** : Réseaux sociaux, labyrinthes simples

### Dijkstra
- **Graphe pondéré** : Les arêtes ont des coûts différents
- **Objectif** : Coût total minimum
- **Usage** : GPS, routage réseau, optimisation

## Problème type : Le réseau routier

### Exemple
```
Paris → (15min) → Lyon
Paris → (20min) → Marseille
Lyon → (12min) → Marseille
```

**Question** : Quel est le chemin le plus rapide de Paris à Marseille ?

- **Direct** : Paris → Marseille = 20min
- **Via Lyon** : Paris → Lyon → Marseille = 15 + 12 = 27min
- **Plus court** : Route directe (20min)

## Comment fonctionne Dijkstra ?

### Étapes de l'algorithme

1. **Initialiser** :
   - Distances : ∞ pour tous, sauf départ = 0
   - Nœuds à traiter : tous les nœuds
   - Nœuds traités : aucun

2. **Boucle principale** :
   - Choisir le nœud non traité avec la plus petite distance
   - Mettre à jour les distances de ses voisins
   - Marquer le nœud comme traité

3. **Répéter** jusqu'à ce que tous les nœuds soient traités

### Exemple détaillé

```python
# Graphe pondéré
graph = {
    'start': {'a': 6, 'b': 2},
    'a': {'fin': 1},
    'b': {'a': 3, 'fin': 5},
    'fin': {}
}

def dijkstra(graph):
    costs = {'start': 0}
    parents = {}
    processed = set()
    
    node = find_lowest_cost_node(costs, processed)
    
    while node:
        cost = costs[node]
        neighbors = graph[node]
        
        for n in neighbors:
            new_cost = cost + neighbors[n]
            if n not in costs or new_cost < costs[n]:
                costs[n] = new_cost
                parents[n] = node
        
        processed.add(node)
        node = find_lowest_cost_node(costs, processed)
    
    return costs, parents
```

## Terminologie

### Poids (Weight)
- Valeur numérique associée à chaque arête
- Peut représenter : temps, distance, coût, etc.

### Coût (Cost)
- Distance accumulée depuis le départ
- Mis à jour pendant l'algorithme

### Nœud traité (Processed Node)
- Nœud dont on a trouvé la distance finale
- Plus jamais mis à jour

## Implémentation complète

```python
import heapq

def dijkstra(graph, start, end):
    # File de priorité : (coût, nœud)
    heap = [(0, start)]
    distances = {start: 0}
    previous = {}
    visited = set()
    
    while heap:
        current_cost, current_node = heapq.heappop(heap)
        
        if current_node in visited:
            continue
            
        visited.add(current_node)
        
        if current_node == end:
            # Reconstituer le chemin
            path = []
            while current_node in previous:
                path.append(current_node)
                current_node = previous[current_node]
            path.append(start)
            return path[::-1], current_cost
        
        for neighbor, weight in graph[current_node].items():
            if neighbor in visited:
                continue
                
            new_cost = current_cost + weight
            
            if neighbor not in distances or new_cost < distances[neighbor]:
                distances[neighbor] = new_cost
                previous[neighbor] = current_node
                heapq.heappush(heap, (new_cost, neighbor))
    
    return None, float('inf')  # Pas de chemin
```

## Exemple pratique : Réseau de transport

### Graphe
```
A → (6) → B → (1) → C
A → (2) → D → (5) → C
D → (3) → B
```

### Exécution étape par étape

**Étape 1** : Départ A
- Distances : A=0, B=6, D=2
- Plus petit non traité : D

**Étape 2** : Traiter D
- Mettre à jour B : min(6, 2+3) = 5
- Mettre à jour C : 2+5 = 7
- Plus petit non traité : B

**Étape 3** : Traiter B
- Mettre à jour C : min(7, 5+1) = 6
- Plus petit non traité : C

**Résultat** : A → D → B → C (coût = 6)

## Limitations de Dijkstra

### 1. Poids négatifs
- **Problème** : Dijkstra ne fonctionne pas avec des poids négatifs
- **Solution** : Algorithme de Bellman-Ford

### 2. Performance
- **Complexité** : O(V²) avec implémentation simple
- **Optimisé** : O(E + V log V) avec tas binaire

### 3. Graphe dynamique
- **Limite** : Recalculer tout si le graphe change
- **Alternative** : Algorithmes adaptatifs

## Applications de Dijkstra

### 1. GPS et navigation
- Calcul d'itinéraires
- Optimisation de trajets

### 2. Réseaux informatiques
- Routage de paquets (protocole OSPF)
- Optimisation de bande passante

### 3. Jeux vidéo
- Pathfinding pour IA
- Navigation dans les mondes virtuels

### 4. Logistique
- Optimisation de livraisons
- Planification de routes

## Variantes et améliorations

### A* (A-star)
- Dijkstra avec heuristique
- Plus rapide pour certains problèmes
- Usage : jeux, planification

### Bidirectional Dijkstra
- Recherche depuis départ et arrivée
- Réduit l'espace de recherche

## Concepts clés du Chapitre 7

1. **Graphes pondérés** : Arêtes avec coûts différents
2. **File de priorité** : Toujours choisir le nœud le moins cher
3. **Mise à jour gloutonne** : Améliorer les distances progressivement
4. **Optimalité** : Garantit le chemin le plus court

## Points à retenir

- Dijkstra trouve le chemin le plus court dans les graphes pondérés
- Utilise une file de priorité pour toujours traiter le nœud le moins cher
- Ne fonctionne pas avec des poids négatifs
- Complexité : O(V²) ou O(E + V log V) optimisé
- Applications : GPS, réseaux, jeux, logistique

---
*Extrait essentiel du Chapitre 7 de "Grokking Algorithms" par Aditya Y. Bhargava*
