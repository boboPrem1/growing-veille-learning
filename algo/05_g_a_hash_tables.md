# Chapitre 5 - Tables de Hachage

## Qu'est-ce qu'une table de hachage ?

Une **table de hachage** (hash table) est une structure de données qui associe des clés à des valeurs pour une recherche ultra-rapide. C'est comme un dictionnaire parfait où vous pouvez trouver n'importe quel mot instantanément.

## Comment ça fonctionne ?

### Fonction de hachage
- Transforme une clé en un indice de tableau
- Exemple : `"apple"` → `4`
- Doit être cohérente : même clé → même indice

### Gestion des collisions
**Collision** : Deux clés différentes donnent le même indice

**Solutions :**
1. **Chaînage** : Liste chaînée à chaque position
2. **Adressage ouvert** : Chercher la prochaine case libre

## Performance des tables de hachage

| Opération | Table de hachage | Tableau | Liste chaînée |
|-----------|------------------|---------|---------------|
| Recherche | O(1) | O(1) | O(n) |
| Insertion | O(1) | O(n) | O(1) |
| Suppression | O(1) | O(n) | O(1) |

*O(1) = temps constant, O(n) = temps linéaire*

## Exemple : Annuaire téléphonique

```python
# Création de la table de hachage
phone_book = {}

# Insertion (O(1))
phone_book["alice"] = "555-1234"
phone_book["bob"] = "555-5678"

# Recherche (O(1))
print(phone_book["alice"])  # "555-1234"

# Suppression (O(1))
del phone_book["bob"]
```

## Applications des tables de hachage

### 1. Mise en cache (Caching)
```python
cache = {}

def get_data(url):
    if url in cache:           # Cache hit
        return cache[url]
    else:                     # Cache miss
        data = download(url)
        cache[url] = data
        return data
```

### 2. Vérification de doublons
```python
def has_duplicates(arr):
    seen = set()
    for item in arr:
        if item in seen:
            return True
        seen.add(item)
    return False
```

### 3. Comptage de fréquences
```python
def count_votes(votes):
    results = {}
    for vote in votes:
        if vote in results:
            results[vote] += 1
        else:
            results[vote] = 1
    return results
```

## Bonnes propriétés d'une fonction de hachage

1. **Déterministe** : Même entrée → même sortie
2. **Uniforme** : Distribution égale des indices
3. **Rapide** : Calcul en O(1)
4. **Difficile à inverser** : Sécurité cryptographique

## Problèmes courants

### 1. Collisions excessives
- **Cause** : Mauvaise fonction de hachage
- **Solution** : Meilleure fonction ou plus de cases

### 2. Taux de remplissage élevé
- **Problème** : Trop de collisions
- **Solution** : Redimensionnement (rehashing)

### 3. Ordre non préservé
- **Limite** : Pas d'ordre naturel
- **Alternative** : Structures ordonnées si nécessaire

## Implémentation simple

```python
class HashTable:
    def __init__(self, size):
        self.size = size
        self.table = [[] for _ in range(size)]
    
    def _hash(self, key):
        return hash(key) % self.size
    
    def set(self, key, value):
        index = self._hash(key)
        for i, (k, v) in enumerate(self.table[index]):
            if k == key:
                self.table[index][i] = (key, value)
                return
        self.table[index].append((key, value))
    
    def get(self, key):
        index = self._hash(key)
        for k, v in self.table[index]:
            if k == key:
                return v
        return None
```

## Tables de hachage dans différents langages

| Langage | Implémentation | Nom |
|---------|----------------|-----|
| Python | dict | Dictionnaire |
| JavaScript | Object/Map | Objet/Carte |
| Java | HashMap | HashMap |
| C++ | unordered_map | Map non ordonnée |
| Ruby | Hash | Hash |

## Concepts clés du Chapitre 5

1. **Hachage** : Transformation clé → indice
2. **Collisions** : Gestion des conflits
3. **Performance O(1)** : Recherche ultra-rapide
4. **Applications** : Cache, doublons, comptage

## Points à retenir

- Les tables de hachage offrent des performances O(1) en moyenne
- La fonction de hachage est cruciale pour la performance
- Les collisions sont inévitables mais gérables
- Idéal pour les recherches rapides et la mise en cache
- Non adaptées si l'ordre des données est important

---
*Extrait essentiel du Chapitre 5 de "Grokking Algorithms" par Aditya Y. Bhargava*
