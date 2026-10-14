# YAGNI — You Ain't Gonna Need It

## Définition

Le principe **YAGNI** (You Ain't Gonna Need It) stipule qu'il ne faut **jamais implémenter une fonctionnalité tant qu'elle n'est pas réellement nécessaire**. Pas "bientôt nécessaire", pas "probablement nécessaire" — **nécessaire maintenant**.

> "Always implement things when you actually need them, never when you just foresee that you need them." — Ron Jeffries (co-fondateur d'Extreme Programming)

Le principe est issu de l'**Extreme Programming (XP)** et repose sur une observation simple : la majorité des fonctionnalités anticipées ne sont jamais utilisées, et celles qui le sont arrivent souvent sous une forme différente de ce qu'on avait imaginé.

## Pourquoi c'est important ?

- **Temps gagné** : Ne pas développer l'inutile libère du temps pour ce qui compte
- **Complexité réduite** : Chaque fonctionnalité ajoutée augmente la surface de maintenance
- **Coût évité** : Code non écrit = code qui ne coûte rien à tester, documenter et maintenir
- **Focus** : L'équipe se concentre sur la valeur immédiate
- **Agilité** : Moins de code = plus de facilité à pivoter si les besoins changent
- **Moins de bugs** : Le code qui n'existe pas n'a pas de bugs

## Les chiffres qui parlent

Selon une étude du Standish Group :
- **64%** des fonctionnalités logicielles sont rarement ou jamais utilisées
- **20%** sont utilisées occasionnellement
- Seulement **16%** sont utilisées fréquemment

Chaque fonctionnalité "au cas où" a donc **5 chances sur 6** de ne servir à rien.

## Les formes courantes de violation du YAGNI

### 1. Fonctionnalités anticipées

```java
// ❌ "On aura sûrement besoin d'exporter en PDF un jour"
public class ReportService {
    
    public String generateHtmlReport(Data data) {
        // Le besoin actuel : un rapport HTML
        return buildHtml(data);
    }
    
    public byte[] generatePdfReport(Data data) {
        // Jamais demandé, jamais utilisé
        return convertToPdf(buildHtml(data));
    }
    
    public String generateCsvReport(Data data) {
        // "Au cas où"
        return buildCsv(data);
    }
    
    public String generateXmlReport(Data data) {
        // "On ne sait jamais"
        return buildXml(data);
    }
}
```

```java
// ✅ On implémente uniquement ce qui est demandé
public class ReportService {
    
    public String generateHtmlReport(Data data) {
        return buildHtml(data);
    }
}
// Quand le PDF sera demandé, on l'ajoutera. Pas avant.
```

### 2. Abstractions "au cas où"

```java
// ❌ Interface + Factory + Strategy pour un seul type de notification
public interface NotificationChannel {
    void send(String message, String recipient);
}

public class EmailChannel implements NotificationChannel {
    @Override
    public void send(String message, String recipient) {
        // Envoi par email
    }
}

public class SmsChannel implements NotificationChannel {
    @Override
    public void send(String message, String recipient) {
        // Jamais utilisé, "au cas où on ajoute le SMS"
    }
}

public class PushChannel implements NotificationChannel {
    @Override
    public void send(String message, String recipient) {
        // Jamais utilisé, "pour le futur"
    }
}

public class NotificationFactory {
    public static NotificationChannel getChannel(String type) {
        return switch (type) {
            case "email" -> new EmailChannel();
            case "sms" -> new SmsChannel();
            case "push" -> new PushChannel();
            default -> throw new IllegalArgumentException();
        };
    }
}
```

```java
// ✅ Direct : on n'a besoin que de l'email
public class EmailService {
    
    public void send(String message, String recipient) {
        // Envoi par email
    }
}
// Quand le SMS sera nécessaire, on extraira une interface à ce moment-là.
```

### 3. Paramétrage excessif

```java
// ❌ Configurable pour des scénarios qui n'existent pas
public class OrderProcessor {
    private int maxRetries = 3;
    private boolean enableCaching = true;
    private boolean enableAuditLog = true;
    private boolean enableNotifications = true;
    private String notificationMode = "email"; // email, sms, push, slack
    private boolean enableBatchProcessing = false;
    private int batchSize = 100;
    private boolean enableParallelProcessing = false;
    private int threadPoolSize = 4;
    private Duration timeout = Duration.ofSeconds(30);
    private boolean enableCircuitBreaker = false;
    private int circuitBreakerThreshold = 5;
    
    // 200 lignes de getters/setters pour des options jamais utilisées
}
```

```java
// ✅ Ce dont on a besoin maintenant
public class OrderProcessor {
    
    public void process(Order order) {
        validate(order);
        save(order);
        sendConfirmationEmail(order);
    }
}
// On ajoutera le retry, le cache, etc. quand ce sera nécessaire
```

### 4. Architecture sur-dimensionnée

```
❌ Pour un MVP avec 3 pages et 100 utilisateurs :
    - Kubernetes cluster (3 nœuds)
    - API Gateway (Kong)
    - Service Mesh (Istio)
    - Event Sourcing + CQRS
    - 5 microservices
    - Redis, RabbitMQ, Elasticsearch
    - Pipeline CI/CD avec 12 stages

✅ Pour un MVP :
    - 1 serveur (ou PaaS type Heroku/Railway)
    - 1 application monolithique
    - 1 base PostgreSQL
    - Déploiement via git push
```

## Exemples pratiques

### ❌ Mauvais exemple : Code "future-proof" inutile

```java
public class UserRepository {
    
    // Le besoin : trouver un utilisateur par ID
    public User findById(Long id) {
        return em.find(User.class, id);
    }
    
    // "On aura sûrement besoin de recherche avancée"
    public List<User> findByDynamicCriteria(Map<String, Object> criteria,
                                             String sortField,
                                             SortDirection direction,
                                             int page,
                                             int pageSize,
                                             boolean includeInactive,
                                             boolean includeDeleted,
                                             Set<String> fieldsToLoad) {
        CriteriaBuilder cb = em.getCriteriaBuilder();
        // ... 80 lignes de construction dynamique de requête
        // Jamais appelé nulle part dans le code
    }
    
    // "Au cas où on voudrait de l'export"
    public Stream<User> streamAll() {
        // Jamais utilisé
    }
    
    // "Pour les statistiques futures"
    public Map<String, Long> countByField(String fieldName) {
        // Jamais utilisé
    }
}
```

**Problèmes :**
- 3 méthodes sur 4 ne sont jamais appelées
- La méthode `findByDynamicCriteria` est complexe et probablement buggée (jamais testée en conditions réelles)
- Maintenance de code mort

### ✅ Bon exemple : Juste ce qu'il faut

```java
public class UserRepository {
    
    public User findById(Long id) {
        return em.find(User.class, id);
    }
    
    public List<User> findAll() {
        return em.createQuery("SELECT u FROM User u", User.class)
            .getResultList();
    }
}
// 2 méthodes, toutes les deux utilisées. Propre.
```

## Autres exemples par domaine

### Modèle de données

❌ **Mauvais :**
```java
// "Un jour on aura besoin de multi-langue, multi-devise, multi-tenant"
public class Product {
    private Long id;
    private Map<String, String> names;         // multi-langue
    private Map<String, BigDecimal> prices;    // multi-devise
    private String tenantId;                    // multi-tenant
    private Map<String, String> metadata;      // extensible
    private List<String> tags;                 // catégorisation future
    private String externalId;                 // intégration future
    private Integer version;                   // optimistic locking
    private ZonedDateTime createdAt;
    private ZonedDateTime updatedAt;
    private ZonedDateTime deletedAt;           // soft delete
    private String createdBy;                  // audit
    private String updatedBy;                  // audit
}
```

✅ **Bon :**
```java
// Le besoin actuel : un catalogue produit simple
public class Product {
    private Long id;
    private String name;
    private BigDecimal price;
    private String description;
}
// On ajoutera la multi-langue quand le client international arrivera.
// On ajoutera le multi-tenant quand le 2e client arrivera.
```

### API endpoints

❌ **Mauvais :**
```java
@RestController
@RequestMapping("/api/users")
public class UserController {
    
    @GetMapping("/{id}")
    public User getUser(@PathVariable Long id) { /* utilisé */ }
    
    @GetMapping
    public List<User> getAllUsers() { /* utilisé */ }
    
    @PostMapping
    public User createUser(@RequestBody User user) { /* utilisé */ }
    
    @PutMapping("/{id}")
    public User updateUser(@PathVariable Long id, @RequestBody User user) { /* jamais appelé */ }
    
    @PatchMapping("/{id}")
    public User patchUser(@PathVariable Long id, @RequestBody Map<String, Object> fields) { /* jamais appelé */ }
    
    @DeleteMapping("/{id}")
    public void deleteUser(@PathVariable Long id) { /* jamais appelé */ }
    
    @GetMapping("/{id}/orders")
    public List<Order> getUserOrders(@PathVariable Long id) { /* jamais appelé */ }
    
    @GetMapping("/search")
    public List<User> searchUsers(@RequestParam Map<String, String> params) { /* jamais appelé */ }
    
    @PostMapping("/bulk")
    public List<User> bulkCreate(@RequestBody List<User> users) { /* jamais appelé */ }
    
    @GetMapping("/export")
    public byte[] exportUsers(@RequestParam String format) { /* jamais appelé */ }
}
```

✅ **Bon :**
```java
@RestController
@RequestMapping("/api/users")
public class UserController {
    
    @GetMapping("/{id}")
    public User getUser(@PathVariable Long id) { /* ... */ }
    
    @GetMapping
    public List<User> getAllUsers() { /* ... */ }
    
    @PostMapping
    public User createUser(@RequestBody User user) { /* ... */ }
}
// 3 endpoints, tous utilisés par le front-end. On ajoute les autres à la demande.
```

### Gestion d'erreurs

❌ **Mauvais :**
```java
// Hiérarchie d'exceptions "complète" pour un CRUD basique
public class AppException extends RuntimeException { }
public class BusinessException extends AppException { }
public class TechnicalException extends AppException { }
public class ValidationException extends BusinessException { }
public class NotFoundException extends BusinessException { }
public class ConflictException extends BusinessException { }
public class ForbiddenException extends BusinessException { }
public class RateLimitException extends TechnicalException { }
public class CircuitBreakerException extends TechnicalException { }
public class TimeoutException extends TechnicalException { }
public class RetryableException extends TechnicalException { }
// 11 exceptions, dont 8 jamais lancées...
```

✅ **Bon :**
```java
// Ce dont on a besoin
public class NotFoundException extends RuntimeException {
    public NotFoundException(String message) {
        super(message);
    }
}

public class ValidationException extends RuntimeException {
    public ValidationException(String message) {
        super(message);
    }
}
// 2 exceptions, les deux utilisées. On en créera d'autres si nécessaire.
```

### Tests

❌ **Mauvais :**
```java
// Tester des cas qui n'existent pas dans le code
@Test
void testCreateUser_withNullName() { /* ... */ }

@Test
void testCreateUser_withEmptyName() { /* ... */ }

@Test
void testCreateUser_withNameTooLong() { /* ... */ }

@Test
void testCreateUser_withSpecialCharacters() { /* ... */ }

@Test
void testCreateUser_withUnicodeEmojis() { /* ... */ }

@Test
void testCreateUser_withSqlInjection() { /* ... */ }

@Test
void testCreateUser_withXssPayload() { /* ... */ }

@Test
void testCreateUser_concurrent() { /* ... */ }

@Test
void testCreateUser_withMaxIntId() { /* ... */ }
// 9 tests pour des validations qui n'existent pas dans le code...
```

✅ **Bon :**
```java
// Tester ce qui existe
@Test
void testCreateUser_success() {
    User user = userService.createUser("John", "john@email.com");
    assertNotNull(user.getId());
    assertEquals("John", user.getName());
}

@Test
void testCreateUser_invalidEmail() {
    assertThrows(ValidationException.class, 
        () -> userService.createUser("John", "invalid"));
}

@Test
void testFindUser_notFound() {
    assertThrows(NotFoundException.class, 
        () -> userService.findById(999L));
}
// 3 tests qui couvrent le code réel. On ajoute des tests quand on ajoute du code.
```

## Le coût caché du code "au cas où"

### Coûts directs

| Activité | Temps gaspillé |
|----------|---------------|
| Développement | Écrire du code inutile |
| Tests | Tester du code inutile |
| Code review | Relire du code inutile |
| Documentation | Documenter du code inutile |
| Debugging | Debugger des bugs dans du code inutile |
| Refactoring | Adapter du code inutile aux changements |

### Coûts indirects

- **Complexité cognitive** : Plus de code à comprendre pour chaque modification
- **Temps de build** : Plus de code à compiler
- **Décisions retardées** : L'abstraction prématurée fige des choix trop tôt
- **Faux sentiment de sécurité** : "C'est prévu" mais jamais testé en conditions réelles
- **Dette technique** : Code mort qui s'accumule et que personne n'ose supprimer

## YAGNI ≠ pas de design

YAGNI ne signifie **pas** écrire du code sale ou ignorer l'architecture. Il signifie :

```
✅ Ce que YAGNI dit :
    - N'implémente pas de fonctionnalités dont tu n'as pas besoin maintenant
    - N'ajoute pas de paramètres "au cas où"
    - Ne crée pas d'abstractions pour des variations qui n'existent pas

❌ Ce que YAGNI ne dit PAS :
    - Ignore les bonnes pratiques de code
    - N'écris pas de tests
    - Fais du code spaghetti
    - Ignore complètement le futur
```

### La nuance importante

```java
// YAGNI ne dit pas d'écrire ça :
public void processOrder(Order o) {
    // 200 lignes de code monolithique sans structure
}

// YAGNI dit d'écrire ça :
public void processOrder(Order order) {
    validate(order);
    calculateTotal(order);
    save(order);
    notifyCustomer(order);
}
// Code propre, bien structuré, mais sans fonctionnalités inutiles.
```

## Quand YAGNI ne s'applique PAS

Il existe des cas où anticiper est légitime :

### 1. Sécurité

```java
// ✅ Toujours anticiper la sécurité, même si "personne n'attaquera"
public void createUser(String name, String email) {
    // Validation et sanitization dès le départ
    String safeName = sanitize(name);
    String safeEmail = validateEmail(email);
    // ...
}
```

### 2. Choix irréversibles

```java
// ✅ Anticiper ce qui coûtera cher à changer
// - Format de stockage des données
// - Schéma de base de données public (API contract)
// - Protocoles de communication inter-services
```

### 3. Contraintes légales / réglementaires

```java
// ✅ RGPD, accessibilité, audit... même si pas demandé explicitement
public class UserService {
    public void deleteUser(Long id) {
        // Suppression RGPD-compliant dès le départ
        userRepository.anonymize(id);
        auditLog.record("USER_DELETED", id);
    }
}
```

### 4. Performance structurelle

```java
// ✅ Indexer les colonnes de recherche dès la création de la table
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_created ON orders(created_at);
// Le coût d'ajout d'un index sur 10M de lignes plus tard est énorme
```

## YAGNI vs les autres principes

| Principe | Relation avec YAGNI |
|----------|-------------------|
| **KISS** | Allié naturel — la simplicité et le "juste ce qu'il faut" vont de pair |
| **DRY** | Pas de conflit — DRY élimine la duplication du code existant, pas du code futur |
| **SOLID** | Appliquer SOLID au code qui existe, pas créer des abstractions SOLID "au cas où" |
| **Clean Code** | YAGNI + Clean Code = code propre ET minimal |
| **TDD** | Compatible — écrire le test du besoin actuel, pas du besoin imaginé |

## Comment appliquer le YAGNI en pratique

### 1. La règle d'or

> "Implémente la chose la plus simple qui puisse fonctionner."

À chaque fonctionnalité, demandez-vous :
- "Quelqu'un a-t-il **explicitement** demandé cette fonctionnalité ?"
- "Est-elle dans le sprint / l'itération actuelle ?"
- "Un utilisateur en a-t-il besoin **aujourd'hui** ?"

Si la réponse est "non" aux trois → **ne l'implémentez pas**.

### 2. Le processus itératif

```
1. Identifier le besoin RÉEL et IMMÉDIAT
2. Implémenter la solution la plus simple
3. Livrer et obtenir du feedback
4. Si un nouveau besoin apparaît → retour à l'étape 1
5. Refactoriser si nécessaire pour accueillir le nouveau besoin
```

### 3. Résister aux tentations courantes

| Tentation | Réponse YAGNI |
|-----------|--------------|
| "Et si on a 1M d'utilisateurs ?" | On optimisera quand on en aura 10 000 |
| "On devrait supporter le multi-tenant" | Quand on aura un 2e client |
| "Ajoutons un cache Redis" | Quand les perfs seront un problème mesuré |
| "Prévoyons l'internationalisation" | Quand le marché international sera confirmé |
| "Mettons une queue de messages" | Quand le traitement synchrone posera problème |
| "Faisons une API GraphQL" | Quand REST ne suffira plus |

### 4. Refactoriser plutôt qu'anticiper

```java
// Jour 1 : Un seul format de notification
public class NotificationService {
    public void notify(String email, String message) {
        sendEmail(email, message);
    }
}

// Jour 60 : Le besoin de SMS apparaît RÉELLEMENT
// On refactorise à ce moment-là
public interface NotificationChannel {
    void send(String recipient, String message);
}

public class EmailChannel implements NotificationChannel { /* ... */ }
public class SmsChannel implements NotificationChannel { /* ... */ }

public class NotificationService {
    private final List<NotificationChannel> channels;
    
    public void notify(String recipient, String message) {
        channels.forEach(ch -> ch.send(recipient, message));
    }
}
// L'abstraction arrive au bon moment, guidée par un besoin réel.
```

## Signaux d'alarme

Vous violez probablement YAGNI si :

- Vous dites **"on pourrait avoir besoin de..."**
- Vous ajoutez un paramètre **"pour plus de flexibilité"**
- Vous créez une interface avec **une seule implémentation**
- Vous construisez un framework interne **"pour gagner du temps plus tard"**
- Vous ajoutez des colonnes en base **"au cas où"**
- Vous passez plus de temps sur l'infrastructure que sur le produit
- Vous avez des classes/méthodes **jamais référencées**

## Checklist YAGNI

Avant chaque développement, vérifiez :

- [ ] Cette fonctionnalité est-elle demandée par un besoin réel et actuel ?
- [ ] Quelqu'un l'utilisera-t-il dès qu'elle sera livrée ?
- [ ] Ai-je résisté à l'envie d'ajouter des options "au cas où" ?
- [ ] Mon modèle de données ne contient-il que les champs nécessaires ?
- [ ] Mes abstractions sont-elles justifiées par au moins 2 cas concrets ?
- [ ] Ai-je supprimé le code mort et les fonctionnalités inutilisées ?
- [ ] L'architecture est-elle proportionnée au problème actuel ?
- [ ] Chaque ligne de code est-elle nécessaire pour le sprint en cours ?

## Résumé

Le YAGNI est un antidote à la sur-ingénierie et au gaspillage :

- **Implémentez** uniquement ce qui est nécessaire **maintenant**
- **Résistez** à la tentation du "au cas où" et du "on va sûrement en avoir besoin"
- **Acceptez** que prédire le futur est impossible — le besoin réel sera différent
- **Refactorisez** quand le besoin apparaît plutôt qu'anticiper des abstractions
- **Mesurez** : si du code n'est pas appelé, supprimez-le

Le meilleur code est celui qu'on n'a **pas eu besoin d'écrire**.
