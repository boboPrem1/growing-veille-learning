# Arbres et Graphes - Guide Complet

## Introduction

Les **arbres** et les **graphes** sont des structures de données fondamentales en informatique. Ils permettent de représenter des relations hiérarchiques ou des réseaux de connexions complexes.

## Qu'est-ce qu'un Graphe ?

### Définition
Un **graphe** est une structure composée de :
- **Nœuds (Sommets/Vertices)** : Les entités
- **Arêtes (Edges)** : Les connexions entre les nœuds

### Terminologie
- **Degré d'un nœud** : Nombre d'arêtes connectées
- **Chemin** : Séquence de nœuds connectés
- **Cycle** : Chemin qui commence et termine au même nœud
- **Graphe connexe** : Tous les nœuds sont accessibles depuis n'importe quel autre nœud
- **Graphe pondéré** : Les arêtes ont des poids/coûts
- **Graphe orienté** : Les arêtes ont une direction

### Types de graphes

#### Graphe non orienté
```python
# Exemple : Réseau social
# A -- B -- C
# |    |
# D -- E
```

#### Graphe orienté
```python
# Exemple : Flux de travail
# A → B → C
# ↓   ↑
# D ← E
```

#### Graphe pondéré
```python
# Exemple : Carte routière
# A --(5)--> B --(3)--> C
# |          |
# (2)        (7)
# ↓          ↓
# D --(4)--> E
```

## Implémentation des Graphes en Python

### Représentation par liste d'adjacence
```python
class Graph:
    def __init__(self):
        self.graph = {}  # Dictionnaire de listes
    
    def add_edge(self, u, v, weight=None, directed=False):
        if u not in self.graph:
            self.graph[u] = []
        self.graph[u].append((v, weight))
        
        if not directed:
            if v not in self.graph:
                self.graph[v] = []
            self.graph[v].append((u, weight))
    
    def remove_edge(self, u, v):
        if u in self.graph:
            self.graph[u] = [edge for edge in self.graph[u] if edge[0] != v]
    
    def get_neighbors(self, node):
        return self.graph.get(node, [])
    
    def __str__(self):
        result = ""
        for node, edges in self.graph.items():
            result += f"{node}: {[f'{v}({w})' if w else v for v, w in edges]}\n"
        return result

# Exemple d'utilisation
g = Graph()
g.add_edge('A', 'B', 5)
g.add_edge('B', 'C', 3)
g.add_edge('A', 'D', 2)
g.add_edge('D', 'E', 4)

print(g)
# Output:
# A: ['B(5)', 'D(2)']
# B: ['A(5)', 'C(3)']
# C: ['B(3)']
# D: ['A(2)', 'E(4)']
# E: ['D(4)']
```

### Représentation par matrice d'adjacence
```python
import numpy as np

class GraphMatrix:
    def __init__(self, num_vertices):
        self.num_vertices = num_vertices
        self.matrix = np.zeros((num_vertices, num_vertices))
    
    def add_edge(self, u, v, weight=1):
        self.matrix[u][v] = weight
        self.matrix[v][u] = weight  # Pour graphe non orienté
    
    def remove_edge(self, u, v):
        self.matrix[u][v] = 0
        self.matrix[v][u] = 0
    
    def get_neighbors(self, vertex):
        neighbors = []
        for i in range(self.num_vertices):
            self.matrix[vertex][i] > 0 and neighbors.append(i)
        return neighbors

# Exemple
gm = GraphMatrix(4)
gm.add_edge(0, 1, 1)
gm.add_edge(1, 2, 1)
gm.add_edge(0, 3, 1)
print(gm.matrix)
# [[0. 1. 0. 1.]
#  [1. 0. 1. 0.]
#  [0. 1. 0. 0.]
#  [1. 0. 0. 0.]]
```

## Algorithmes sur les Graphes

### Parcours en profondeur (DFS)
```python
def dfs(graph, start, visited=None):
    if visited is None:
        visited = set()
    
    visited.add(start)
    print(start, end=' ')
    
    for neighbor, _ in graph.get_neighbors(start):
        if neighbor not in visited:
            dfs(graph, neighbor, visited)
    
    return visited

# Version itérative
def dfs_iterative(graph, start):
    visited = set()
    stack = [start]
    
    while stack:
        node = stack.pop()
        if node not in visited:
            visited.add(node)
            print(node, end=' ')
            
            for neighbor, _ in graph.get_neighbors(node):
                if neighbor not in visited:
                    stack.append(neighbor)
    
    return visited
```

### Parcours en largeur (BFS)
```python
from collections import deque

def bfs(graph, start):
    visited = set()
    queue = deque([start])
    visited.add(start)
    
    while queue:
        node = queue.popleft()
        print(node, end=' ')
        
        for neighbor, _ in graph.get_neighbors(node):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(neighbor)
    
    return visited
```

### Détection de cycle
```python
def has_cycle(graph):
    visited = set()
    
    def dfs_cycle(node, parent):
        visited.add(node)
        
        for neighbor, _ in graph.get_neighbors(node):
            if neighbor not in visited:
                if dfs_cycle(neighbor, node):
                    return True
            elif neighbor != parent:
                return True
        
        return False
    
    for node in graph.graph:
        if node not in visited:
            if dfs_cycle(node, None):
                return True
    
    return False
```

### Composantes connexes
```python
def connected_components(graph):
    visited = set()
    components = []
    
    for node in graph.graph:
        if node not in visited:
            component = dfs(graph, node, visited)
            components.append(component)
    
    return components
```

## Qu'est-ce qu'un Arbre ?

### Définition
Un **arbre** est un graphe spécial avec les propriétés suivantes :
- **Connexe** : Tous les nœuds sont accessibles
- **Acyclique** : Pas de cycles
- **Hiérarchique** : Un nœud racine, niveaux parent-enfant

### Terminologie des arbres
- **Racine (Root)** : Nœud supérieur
- **Feuille (Leaf)** : Nœud sans enfants
- **Nœud interne** : Nœud avec au moins un enfant
- **Hauteur** : Nombre de niveaux
- **Profondeur** : Distance depuis la racine
- **Taille** : Nombre total de nœuds

### Types d'arbres

#### Arbre binaire
```python
class TreeNode:
    def __init__(self, val=0, left=None, right=None):
        self.val = val
        self.left = left
        self.right = right

# Exemple d'arbre binaire
#       8
#      / \
#     3   10
#    / \    \
#   1   6    14
#      / \   /
#     4   7 13
```

#### Arbre binaire de recherche (BST)
```python
class BST:
    def __init__(self):
        self.root = None
    
    def insert(self, val):
        if not self.root:
            self.root = TreeNode(val)
        else:
            self._insert(self.root, val)
    
    def _insert(self, node, val):
        if val < node.val:
            if node.left:
                self._insert(node.left, val)
            else:
                node.left = TreeNode(val)
        else:
            if node.right:
                self._insert(node.right, val)
            else:
                node.right = TreeNode(val)
    
    def search(self, val):
        return self._search(self.root, val)
    
    def _search(self, node, val):
        if not node:
            return False
        if node.val == val:
            return True
        elif val < node.val:
            return self._search(node.left, val)
        else:
            return self._search(node.right, val)
    
    def inorder_traversal(self):
        result = []
        self._inorder(self.root, result)
        return result
    
    def _inorder(self, node, result):
        if node:
            self._inorder(node.left, result)
            result.append(node.val)
            self._inorder(node.right, result)
```

#### Arbre AVL (équilibré)
```python
class AVLNode:
    def __init__(self, key):
        self.key = key
        self.left = None
        self.right = None
        self.height = 1

class AVLTree:
    def __init__(self):
        self.root = None
    
    def insert(self, key):
        self.root = self._insert(self.root, key)
    
    def _insert(self, node, key):
        if not node:
            return AVLNode(key)
        
        if key < node.key:
            node.left = self._insert(node.left, key)
        else:
            node.right = self._insert(node.right, key)
        
        # Mettre à jour la hauteur
        node.height = 1 + max(self._get_height(node.left), 
                             self._get_height(node.right))
        
        # Vérifier l'équilibre
        balance = self._get_balance(node)
        
        # Rotations si nécessaire
        if balance > 1 and key < node.left.key:
            return self._right_rotate(node)
        if balance < -1 and key > node.right.key:
            return self._left_rotate(node)
        if balance > 1 and key > node.left.key:
            node.left = self._left_rotate(node.left)
            return self._right_rotate(node)
        if balance < -1 and key < node.right.key:
            node.right = self._right_rotate(node.right)
            return self._left_rotate(node)
        
        return node
    
    def _get_height(self, node):
        return node.height if node else 0
    
    def _get_balance(self, node):
        return self._get_height(node.left) - self._get_height(node.right) if node else 0
    
    def _right_rotate(self, z):
        y = z.left
        T3 = y.right
        
        y.right = z
        z.left = T3
        
        z.height = 1 + max(self._get_height(z.left), 
                          self._get_height(z.right))
        y.height = 1 + max(self._get_height(y.left), 
                          self._get_height(y.right))
        
        return y
    
    def _left_rotate(self, z):
        y = z.right
        T2 = y.left
        
        y.left = z
        z.right = T2
        
        z.height = 1 + max(self._get_height(z.left), 
                          self._get_height(z.right))
        y.height = 1 + max(self._get_height(y.left), 
                          self._get_height(y.right))
        
        return y
```

#### Trie (Arbre de préfixes)
```python
class TrieNode:
    def __init__(self):
        self.children = {}
        self.is_end_of_word = False

class Trie:
    def __init__(self):
        self.root = TrieNode()
    
    def insert(self, word):
        node = self.root
        for char in word:
            if char not in node.children:
                node.children[char] = TrieNode()
            node = node.children[char]
        node.is_end_of_word = True
    
    def search(self, word):
        node = self.root
        for char in word:
            if char not in node.children:
                return False
            node = node.children[char]
        return node.is_end_of_word
    
    def starts_with(self, prefix):
        node = self.root
        for char in prefix:
            if char not in node.children:
                return False
            node = node.children[char]
        return True
    
    def get_all_words(self):
        words = []
        self._dfs(self.root, "", words)
        return words
    
    def _dfs(self, node, prefix, words):
        if node.is_end_of_word:
            words.append(prefix)
        
        for char, child in node.children.items():
            self._dfs(child, prefix + char, words)
```

## Algorithmes sur les Arbres

### Parcours d'arbres
```python
# Parcours en ordre (inorder) - BST : donne éléments triés
def inorder_traversal(root):
    result = []
    def inorder(node):
        if node:
            inorder(node.left)
            result.append(node.val)
            inorder(node.right)
    inorder(root)
    return result

# Parcours préordre (preorder)
def preorder_traversal(root):
    result = []
    def preorder(node):
        if node:
            result.append(node.val)
            preorder(node.left)
            preorder(node.right)
    preorder(root)
    return result

# Parcours postordre (postorder)
def postorder_traversal(root):
    result = []
    def postorder(node):
        if node:
            postorder(node.left)
            postorder(node.right)
            result.append(node.val)
    postorder(root)
    return result

# Parcours par niveau (level order)
from collections import deque

def level_order_traversal(root):
    if not root:
        return []
    
    result = []
    queue = deque([root])
    
    while queue:
        level_size = len(queue)
        level = []
        
        for _ in range(level_size):
            node = queue.popleft()
            level.append(node.val)
            
            if node.left:
                queue.append(node.left)
            if node.right:
                queue.append(node.right)
        
        result.append(level)
    
    return result
```

### Validation d'arbre binaire de recherche
```python
def is_valid_bst(root):
    def validate(node, low=float('-inf'), high=float('inf')):
        if not node:
            return True
        
        if node.val <= low or node.val >= high:
            return False
        
        return (validate(node.left, low, node.val) and 
                validate(node.right, node.val, high))
    
    return validate(root)
```

### Hauteur et équilibre
```python
def tree_height(root):
    if not root:
        return 0
    return 1 + max(tree_height(root.left), tree_height(root.right))

def is_balanced(root):
    def check_balance(node):
        if not node:
            return 0, True
        
        left_height, left_balanced = check_balance(node.left)
        right_height, right_balanced = check_balance(node.right)
        
        current_height = 1 + max(left_height, right_height)
        current_balanced = (left_balanced and right_balanced and 
                          abs(left_height - right_height) <= 1)
        
        return current_height, current_balanced
    
    _, balanced = check_balance(root)
    return balanced
```

## Cas d'Usage Pratiques

### Graphes

#### Réseaux sociaux
```python
# Trouver les amis d'amis
def friends_of_friends(graph, user, depth=2):
    visited = set()
    result = set()
    
    def dfs(node, current_depth):
        if current_depth > depth or node in visited:
            return
        
        visited.add(node)
        
        if current_depth == depth:
            result.add(node)
            return
        
        for friend, _ in graph.get_neighbors(node):
            dfs(friend, current_depth + 1)
    
    for friend, _ in graph.get_neighbors(user):
        dfs(friend, 1)
    
    return result - {user} - set(graph.get_neighbors(user))
```

#### Systèmes de recommandation
```python
def recommend_items(user_item_graph, user):
    # Trouver des utilisateurs similaires
    similar_users = []
    for other_user in user_item_graph.graph:
        if other_user != user:
            common_items = len(set(user_item_graph.get_neighbors(user)) & 
                             set(user_item_graph.get_neighbors(other_user)))
            if common_items > 0:
                similar_users.append((other_user, common_items))
    
    # Trier par similarité
    similar_users.sort(key=lambda x: x[1], reverse=True)
    
    # Recommander les items des utilisateurs similaires
    recommendations = set()
    user_items = set(user_item_graph.get_neighbors(user))
    
    for similar_user, _ in similar_users[:5]:  # Top 5 similaires
        for item, _ in user_item_graph.get_neighbors(similar_user):
            if item not in user_items:
                recommendations.add(item)
    
    return list(recommendations)
```

#### Détection de communautés
```python
def detect_communities(graph):
    communities = connected_components(graph)
    return communities
```

### Arbres

#### Systèmes de fichiers
```python
class FileSystemNode:
    def __init__(self, name, is_file=False):
        self.name = name
        self.is_file = is_file
        self.children = {}
        self.size = 0 if is_file else None

class FileSystem:
    def __init__(self):
        self.root = FileSystemNode("/")
    
    def add_file(self, path, size):
        parts = path.split('/')[1:]
        node = self.root
        
        for part in parts[:-1]:
            if part not in node.children:
                node.children[part] = FileSystemNode(part, False)
            node = node.children[part]
        
        filename = parts[-1]
        node.children[filename] = FileSystemNode(filename, True)
        node.children[filename].size = size
    
    def calculate_sizes(self):
        def calculate(node):
            if node.is_file:
                return node.size
            
            total = 0
            for child in node.children.values():
                total += calculate(child)
            node.size = total
            return total
        
        calculate(self.root)
    
    def find_large_files(self, min_size):
        result = []
        
        def dfs(node, path):
            if node.is_file and node.size >= min_size:
                result.append((path + "/" + node.name, node.size))
            
            for child in node.children.values():
                dfs(child, path + "/" + node.name)
        
        dfs(self.root, "")
        return result
```

#### Moteurs de recherche (Trie)
```python
class SearchEngine:
    def __init__(self):
        self.trie = Trie()
        self.word_to_docs = {}
    
    def add_document(self, doc_id, content):
        words = content.lower().split()
        for word in set(words):  # Éviter les doublons
            self.trie.insert(word)
            if word not in self.word_to_docs:
                self.word_to_docs[word] = []
            if doc_id not in self.word_to_docs[word]:
                self.word_to_docs[word].append(doc_id)
    
    def search(self, query):
        words = query.lower().split()
        if not words:
            return []
        
        # Trouver les documents contenant tous les mots
        result_sets = []
        for word in words:
            if word in self.word_to_docs:
                result_sets.append(set(self.word_to_docs[word]))
        
        if not result_sets:
            return []
        
        # Intersection des ensembles
        result = result_sets[0]
        for s in result_sets[1:]:
            result = result.intersection(s)
        
        return list(result)
    
    def autocomplete(self, prefix):
        # Trouver tous les mots avec ce préfixe
        words = []
        def dfs(node, current_word):
            if node.is_end_of_word:
                words.append(current_word)
            for char, child in node.children.items():
                dfs(child, current_word + char)
        
        node = self.trie.root
        for char in prefix:
            if char not in node.children:
                return []
            node = node.children[char]
        
        dfs(node, prefix)
        return words
```

#### Arbres de décision (Machine Learning)
```python
class DecisionTreeNode:
    def __init__(self, feature=None, threshold=None, left=None, right=None, value=None):
        self.feature = feature
        self.threshold = threshold
        self.left = left
        self.right = right
        self.value = value  # Pour les feuilles

class SimpleDecisionTree:
    def __init__(self, max_depth=3):
        self.max_depth = max_depth
        self.root = None
    
    def fit(self, X, y):
        self.root = self._build_tree(X, y, depth=0)
    
    def _build_tree(self, X, y, depth):
        # Critères d'arrêt
        if depth >= self.max_depth or len(set(y)) == 1:
            return DecisionTreeNode(value=max(set(y), key=y.count))
        
        # Trouver la meilleure séparation
        best_feature, best_threshold = self._find_best_split(X, y)
        
        if best_feature is None:
            return DecisionTreeNode(value=max(set(y), key=y.count))
        
        # Diviser les données
        left_indices = [i for i, x in enumerate(X) if x[best_feature] <= best_threshold]
        right_indices = [i for i, x in enumerate(X) if x[best_feature] > best_threshold]
        
        if not left_indices or not right_indices:
            return DecisionTreeNode(value=max(set(y), key=y.count))
        
        left_X = [X[i] for i in left_indices]
        left_y = [y[i] for i in left_indices]
        right_X = [X[i] for i in right_indices]
        right_y = [y[i] for i in right_indices]
        
        left_child = self._build_tree(left_X, left_y, depth + 1)
        right_child = self._build_tree(right_X, right_y, depth + 1)
        
        return DecisionTreeNode(best_feature, best_threshold, left_child, right_child)
    
    def _find_best_split(self, X, y):
        # Implémentation simplifiée - trouver la meilleure gini impurity
        best_gini = float('inf')
        best_feature = None
        best_threshold = None
        
        for feature in range(len(X[0])):
            thresholds = sorted(set(x[feature] for x in X))
            for threshold in thresholds:
                left_indices = [i for i, x in enumerate(X) if x[feature] <= threshold]
                right_indices = [i for i, x in enumerate(X) if x[feature] > threshold]
                
                if not left_indices or not right_indices:
                    continue
                
                left_y = [y[i] for i in left_indices]
                right_y = [y[i] for i in right_indices]
                
                gini = self._gini_impurity(left_y) + self._gini_impurity(right_y)
                
                if gini < best_gini:
                    best_gini = gini
                    best_feature = feature
                    best_threshold = threshold
        
        return best_feature, best_threshold
    
    def _gini_impurity(self, y):
        if not y:
            return 0
        
        total = len(y)
        proportions = [y.count(c) / total for c in set(y)]
        return 1 - sum(p * p for p in proportions)
    
    def predict(self, X):
        predictions = []
        for x in X:
            predictions.append(self._predict_single(x))
        return predictions
    
    def _predict_single(self, x):
        node = self.root
        while node.value is None:
            if x[node.feature] <= node.threshold:
                node = node.left
            else:
                node = node.right
        return node.value
```

## Comparaison Arbres vs Graphes

| Caractéristique | Arbres | Graphes |
|-----------------|--------|---------|
| **Structure** | Hiérarchique, sans cycles | Réseau, peut avoir des cycles |
| **Connexité** | Toujours connexe | Peut être déconnecté |
| **Racine** | Une seule racine | Pas de racine |
| **Complexité** | Plus simple | Plus complexe |
| **Parcours** | DFS, BFS, inorder, preorder, postorder | DFS, BFS |
| **Applications** | Hiérarchies, recherche, décision | Réseaux, optimisation, social |

## Performance et Complexité

### Graphes
- **Représentation liste d'adjacence** :
  - Espace : O(V + E)
  - Vérification arête : O(V)
  - Voisins d'un nœud : O(degré)

- **Représentation matrice d'adjacence** :
  - Espace : O(V²)
  - Vérification arête : O(1)
  - Voisins d'un nœud : O(V)

### Arbres
- **Arbre binaire équilibré** :
  - Recherche : O(log n)
  - Insertion : O(log n)
  - Suppression : O(log n)

- **Arbre binaire déséquilibré** :
  - Recherche : O(n)
  - Insertion : O(n)
  - Suppression : O(n)

## Conclusion

Les **arbres** et les **graphes** sont des structures de données puissantes et polyvalentes :

- **Arbres** : Idéaux pour les hiérarchies, la recherche efficace et les structures ordonnées
- **Graphes** : Parfaits pour les réseaux, les relations complexes et l'optimisation

Le choix entre les deux dépend du problème :
- Utilisez des **arbres** pour les relations parent-enfant et la recherche rapide
- Utilisez des **graphes** pour les réseaux complexes et les relations arbitraires

La maîtrise de ces structures est essentielle pour résoudre efficacement de nombreux problèmes en informatique.
