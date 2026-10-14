# DRY — Don't Repeat Yourself

## Définition

Le principe **DRY** (Don't Repeat Yourself) stipule que chaque morceau de connaissance ou de logique doit avoir une **représentation unique, non ambiguë et faisant autorité** au sein d'un système.

> "Every piece of knowledge must have a single, unambiguous, authoritative representation within a system." — Andy Hunt & Dave Thomas, *The Pragmatic Programmer* (1999)

Le DRY ne concerne **pas seulement le code dupliqué**. Il s'applique à toute forme de connaissance : logique métier, configuration, documentation, schémas de base de données, etc.

## Pourquoi c'est important ?

- **Maintenabilité** : Une seule modification à un seul endroit pour corriger ou faire évoluer une logique
- **Cohérence** : Pas de risque de divergence entre des copies du même comportement
- **Lisibilité** : Le code exprime chaque idée une seule fois, ce qui le rend plus concis
- **Réduction des bugs** : Moins de risques d'oublier de mettre à jour l'une des copies
- **Productivité** : Moins de code à écrire, relire et tester

## Les 3 types de duplication

### 1. Duplication de code (la plus visible)

Le même bloc de code copié-collé à plusieurs endroits.

```java
// ❌ Duplication de code
public class OrderService {
    public double calculateTotal(Order order) {
        double total = 0;
        for (Item item : order.getItems()) {
            total += item.getPrice() * item.getQuantity();
        }
        total *= 1.20; // TVA 20%
        return total;
    }
}

public class InvoiceService {
    public double calculateInvoiceAmount(Order order) {
        double total = 0;
        for (Item item : order.getItems()) {
            total += item.getPrice() * item.getQuantity();
        }
        total *= 1.20; // TVA 20%
        return total;
    }
}
```

### 2. Duplication de logique (subtile)

Le code est différent syntaxiquement mais exprime la **même règle métier**.

```java
// ❌ Même logique, code différent
public class UserController {
    public boolean canAccess(User user) {
        return user.getAge() >= 18;
    }
}

public class ContentFilter {
    public boolean isAdult(User user) {
        return user.getBirthDate().isBefore(
            LocalDate.now().minusYears(18)
        );
    }
}
// Les deux expriment la même règle "l'utilisateur est majeur"
```

### 3. Duplication de connaissance (la plus insidieuse)

La même information métier est définie à plusieurs endroits (code, config, documentation, SQL…).

```
❌ Taux de TVA défini à 3 endroits :
- Dans OrderService.java : total *= 1.20;
- Dans application.properties : tax.rate=20
- Dans le script SQL : SELECT price * 1.20 FROM products;
```

## Exemples pratiques

### ❌ Mauvais exemple : Violation du DRY

```java
public class CustomerService {
    
    public void createCustomer(String name, String email) {
        // Validation dupliquée
        if (name == null || name.trim().isEmpty()) {
            throw new IllegalArgumentException("Le nom est obligatoire");
        }
        if (email == null || !email.matches("^[\\w.-]+@[\\w.-]+\\.[a-z]{2,}$")) {
            throw new IllegalArgumentException("Email invalide");
        }
        // Sauvegarde...
    }
    
    public void updateCustomer(Long id, String name, String email) {
        // Même validation copiée-collée
        if (name == null || name.trim().isEmpty()) {
            throw new IllegalArgumentException("Le nom est obligatoire");
        }
        if (email == null || !email.matches("^[\\w.-]+@[\\w.-]+\\.[a-z]{2,}$")) {
            throw new IllegalArgumentException("Email invalide");
        }
        // Mise à jour...
    }
}
```

**Problèmes :**
- Si la règle de validation de l'email change, il faut modifier **chaque** copie
- Risque d'oublier une occurrence lors de la modification
- La regex email dupliquée est un aimant à bugs

### ✅ Bon exemple : Respect du DRY

```java
public class CustomerValidator {
    
    private static final String EMAIL_REGEX = "^[\\w.-]+@[\\w.-]+\\.[a-z]{2,}$";
    
    public void validate(String name, String email) {
        validateName(name);
        validateEmail(email);
    }
    
    private void validateName(String name) {
        if (name == null || name.trim().isEmpty()) {
            throw new IllegalArgumentException("Le nom est obligatoire");
        }
    }
    
    private void validateEmail(String email) {
        if (email == null || !email.matches(EMAIL_REGEX)) {
            throw new IllegalArgumentException("Email invalide");
        }
    }
}

public class CustomerService {
    private final CustomerValidator validator;
    
    public CustomerService(CustomerValidator validator) {
        this.validator = validator;
    }
    
    public void createCustomer(String name, String email) {
        validator.validate(name, email);
        // Sauvegarde...
    }
    
    public void updateCustomer(Long id, String name, String email) {
        validator.validate(name, email);
        // Mise à jour...
    }
}
```

## Autres exemples par domaine

### Constantes magiques

❌ **Mauvais :**
```java
public class PricingService {
    public double applyDiscount(double price) {
        return price * 0.90; // 10% de réduction
    }
}

public class PromotionService {
    public String getPromotionLabel() {
        return "Profitez de 10% de réduction !";
    }
}

public class CartService {
    public double getDiscountedTotal(double total) {
        return total * 0.90; // 10% encore...
    }
}
```

✅ **Bon :**
```java
public class DiscountPolicy {
    public static final double STANDARD_DISCOUNT_RATE = 0.10;
    
    public double applyDiscount(double price) {
        return price * (1 - STANDARD_DISCOUNT_RATE);
    }
    
    public String getLabel() {
        return String.format("Profitez de %.0f%% de réduction !",
            STANDARD_DISCOUNT_RATE * 100);
    }
}
```

### Formatage et transformation

❌ **Mauvais :**
```java
public class OrderController {
    public String formatOrder(Order order) {
        return order.getId() + " - " + 
               order.getDate().format(DateTimeFormatter.ofPattern("dd/MM/yyyy")) +
               " - " + String.format("%.2f EUR", order.getTotal());
    }
}

public class InvoiceController {
    public String formatInvoice(Invoice invoice) {
        return invoice.getId() + " - " + 
               invoice.getDate().format(DateTimeFormatter.ofPattern("dd/MM/yyyy")) +
               " - " + String.format("%.2f EUR", invoice.getAmount());
    }
}
```

✅ **Bon :**
```java
public class Formatters {
    private static final DateTimeFormatter DATE_FORMAT = 
        DateTimeFormatter.ofPattern("dd/MM/yyyy");
    
    public static String formatDate(LocalDate date) {
        return date.format(DATE_FORMAT);
    }
    
    public static String formatCurrency(double amount) {
        return String.format("%.2f EUR", amount);
    }
}

public class OrderController {
    public String formatOrder(Order order) {
        return order.getId() + " - " + 
               Formatters.formatDate(order.getDate()) + " - " +
               Formatters.formatCurrency(order.getTotal());
    }
}
```

### Configuration dupliquée

❌ **Mauvais :**
```java
public class EmailService {
    private String smtpHost = "smtp.company.com";
    private int smtpPort = 587;
}

public class AlertService {
    private String mailHost = "smtp.company.com";
    private int mailPort = 587;
}
```

✅ **Bon :**
```java
// application.properties
// mail.smtp.host=smtp.company.com
// mail.smtp.port=587

public class MailConfig {
    @Value("${mail.smtp.host}")
    private String host;
    
    @Value("${mail.smtp.port}")
    private int port;
    
    // Getters...
}

// Injecté partout où nécessaire
public class EmailService {
    private final MailConfig mailConfig;
    // ...
}

public class AlertService {
    private final MailConfig mailConfig;
    // ...
}
```

## Techniques pour éliminer la duplication

### 1. Extraction de méthode

La technique la plus simple : extraire le code dupliqué dans une méthode.

```java
// Avant
public void processOrder(Order order) {
    log.info("[{}] Processing order #{}", LocalDateTime.now(), order.getId());
    // ...
    log.info("[{}] Order #{} processed", LocalDateTime.now(), order.getId());
}

public void cancelOrder(Order order) {
    log.info("[{}] Cancelling order #{}", LocalDateTime.now(), order.getId());
    // ...
    log.info("[{}] Order #{} cancelled", LocalDateTime.now(), order.getId());
}

// Après
private void logAction(String action, Order order) {
    log.info("[{}] {} order #{}", LocalDateTime.now(), action, order.getId());
}
```

### 2. Héritage et classes abstraites

Quand plusieurs classes partagent un comportement commun.

```java
public abstract class BaseRepository<T> {
    
    public T findById(Long id) {
        // Logique commune de recherche
    }
    
    public void save(T entity) {
        // Logique commune de sauvegarde
    }
    
    public void delete(Long id) {
        // Logique commune de suppression
    }
}

public class UserRepository extends BaseRepository<User> {
    // Méthodes spécifiques aux utilisateurs
}

public class ProductRepository extends BaseRepository<Product> {
    // Méthodes spécifiques aux produits
}
```

### 3. Composition et délégation

Préférée à l'héritage pour le partage de comportement (cf. principe "Composition over Inheritance").

```java
public class AuditLogger {
    public void logAction(String entity, String action, Long entityId) {
        log.info("[AUDIT] {} {} on {} #{}", 
            LocalDateTime.now(), action, entity, entityId);
    }
}

public class OrderService {
    private final AuditLogger audit;
    
    public void createOrder(Order order) {
        // Logique métier...
        audit.logAction("Order", "CREATE", order.getId());
    }
}

public class UserService {
    private final AuditLogger audit;
    
    public void createUser(User user) {
        // Logique métier...
        audit.logAction("User", "CREATE", user.getId());
    }
}
```

### 4. Template Method Pattern

Quand le squelette d'un algorithme est identique mais les étapes varient.

```java
public abstract class DataExporter {
    
    // Le squelette est défini une seule fois
    public final void export(List<Data> data) {
        String header = buildHeader();
        List<String> rows = data.stream()
            .map(this::formatRow)
            .collect(Collectors.toList());
        String footer = buildFooter(data.size());
        write(header, rows, footer);
    }
    
    protected abstract String buildHeader();
    protected abstract String formatRow(Data data);
    protected abstract String buildFooter(int count);
    protected abstract void write(String header, List<String> rows, String footer);
}

public class CsvExporter extends DataExporter {
    @Override protected String buildHeader() { return "id,name,value"; }
    @Override protected String formatRow(Data d) { 
        return d.getId() + "," + d.getName() + "," + d.getValue(); 
    }
    // ...
}

public class JsonExporter extends DataExporter {
    @Override protected String buildHeader() { return "["; }
    @Override protected String formatRow(Data d) { 
        return toJson(d); 
    }
    // ...
}
```

### 5. Génériques (Generics)

Éliminent la duplication liée au type.

```java
// ❌ Code dupliqué pour chaque type
public class IntegerList {
    public int findMax(List<Integer> list) { /* ... */ }
}
public class DoubleList {
    public double findMax(List<Double> list) { /* ... */ }
}

// ✅ Un seul code générique
public class MathUtils {
    public <T extends Comparable<T>> T findMax(List<T> list) {
        return list.stream()
            .max(Comparable::compareTo)
            .orElseThrow();
    }
}
```

## DRY au-delà du code

### Base de données

```sql
-- ❌ Logique métier dupliquée entre code et SQL
-- En Java : if (order.getStatus().equals("COMPLETED") && order.getTotal() > 100)
-- En SQL  : WHERE status = 'COMPLETED' AND total > 100

-- ✅ Centraliser via une vue ou un service unique
CREATE VIEW eligible_orders AS
SELECT * FROM orders WHERE status = 'COMPLETED' AND total > 100;
```

### Documentation

```
❌ Dupliquer les règles métier dans le code ET la doc :
    - Code : if (age >= 18) ...
    - Wiki : "L'utilisateur doit avoir au moins 18 ans"
    → Quand la règle change, on oublie souvent de mettre à jour la doc

✅ Générer la documentation depuis le code, ou documenter uniquement le "pourquoi" :
    - Code auto-documenté : if (user.isAdult()) ...
    - Doc : "Exigence légale : RGPD impose la majorité pour consentement"
```

### Tests

```java
// ❌ Données de test dupliquées
@Test void testCreate() {
    User user = new User("John", "john@email.com", 25);
    // ...
}
@Test void testUpdate() {
    User user = new User("John", "john@email.com", 25);
    // ...
}

// ✅ Factory ou Builder pour les données de test
public class TestFixtures {
    public static User defaultUser() {
        return new User("John", "john@email.com", 25);
    }
}

@Test void testCreate() {
    User user = TestFixtures.defaultUser();
    // ...
}
```

## Pièges courants à éviter

### 1. Confondre duplication de code et duplication de connaissance

Deux morceaux de code **identiques** ne sont pas forcément une violation du DRY s'ils représentent des **concepts différents**.

```java
// Ces deux validations se RESSEMBLENT mais n'expriment PAS la même règle
public class OrderValidator {
    public boolean isValid(Order order) {
        return order.getTotal() > 0; // Règle : une commande doit avoir un montant
    }
}

public class PaymentValidator {
    public boolean isValid(Payment payment) {
        return payment.getAmount() > 0; // Règle : un paiement doit être positif
    }
}
// Ne pas fusionner ! Ces règles pourraient évoluer indépendamment.
```

### 2. DRY prématuré — Créer des abstractions trop tôt

> "Duplication is far cheaper than the wrong abstraction." — Sandi Metz

```java
// ❌ Abstraction forcée pour 2 cas qui se ressemblent par hasard
public abstract class BaseProcessor<T> {
    public void process(T item) {
        validate(item);
        transform(item);
        save(item);
    }
    // ... 15 méthodes abstraites pour couvrir tous les cas
}

// ✅ Attendre d'avoir 3+ cas similaires avant d'abstraire
// Règle du "Rule of Three" : dupliquer 2 fois est acceptable,
// au 3e cas, on refactorise.
```

### 3. DRY obsessionnel — Sur-factorisation

```java
// ❌ Trop factorisé, illisible
public class StringUtils {
    public static boolean isNonEmpty(String s) {
        return s != null && !s.trim().isEmpty();
    }
}

// Utilisé partout pour un simple null-check :
if (StringUtils.isNonEmpty(name)) { ... }

// ✅ Parfois, une ligne simple est plus claire
if (name != null && !name.isBlank()) { ... }
```

### 4. Coupler des modules qui ne devraient pas l'être

```java
// ❌ Forcer un module partagé crée du couplage
// Module "shared-utils" utilisé par OrderService ET UserService
// → Un changement pour Order peut casser User

// ✅ Accepter une duplication légère entre modules indépendants
// Chaque module a sa propre copie, libre d'évoluer séparément
```

## DRY vs WET vs AHA

| Principe | Signification | Philosophie |
|----------|--------------|-------------|
| **DRY** | Don't Repeat Yourself | Chaque connaissance a une source unique |
| **WET** | Write Everything Twice | Dupliquer est OK tant qu'on n'a pas 3+ cas |
| **AHA** | Avoid Hasty Abstractions | Abstraire trop tôt est pire que dupliquer |

**En pratique**, la bonne approche combine les trois :
1. **Première occurrence** : écrire le code directement
2. **Deuxième occurrence** : dupliquer (c'est OK)
3. **Troisième occurrence** : refactoriser pour éliminer la duplication

## Comment appliquer le DRY en pratique

### 1. Identifier la duplication

Posez-vous ces questions :
- "Si cette règle métier change, combien d'endroits dois-je modifier ?"
- "Ce code copié-collé exprime-t-il la même **idée** ou juste la même **forme** ?"
- "Un changement ici doit-il automatiquement se répercuter là-bas ?"

### 2. Choisir la bonne technique

| Situation | Technique |
|-----------|-----------|
| Bloc de code dupliqué | Extraction de méthode |
| Comportement commun entre classes | Composition / Héritage |
| Valeurs répétées (URLs, taux, seuils) | Constantes / Configuration |
| Algorithme similaire, détails différents | Template Method / Strategy |
| Types différents, même logique | Génériques |
| Règle métier dispersée | Service dédié / Single Source of Truth |

### 3. Refactoriser progressivement

```java
// Étape 1 : Repérer la duplication
public class OrderService {
    public double calculateTotal(List<Item> items) {
        return items.stream()
            .mapToDouble(i -> i.getPrice() * i.getQuantity())
            .sum();
    }
}

public class CartService {
    public double getCartTotal(List<Item> items) {
        return items.stream()
            .mapToDouble(i -> i.getPrice() * i.getQuantity())
            .sum();
    }
}

// Étape 2 : Extraire dans un service commun
public class PricingCalculator {
    public double calculateItemsTotal(List<Item> items) {
        return items.stream()
            .mapToDouble(i -> i.getPrice() * i.getQuantity())
            .sum();
    }
}

// Étape 3 : Utiliser le service commun
public class OrderService {
    private final PricingCalculator calculator;
    
    public double calculateTotal(List<Item> items) {
        return calculator.calculateItemsTotal(items);
    }
}

public class CartService {
    private final PricingCalculator calculator;
    
    public double getCartTotal(List<Item> items) {
        return calculator.calculateItemsTotal(items);
    }
}
```

## Relation avec les autres principes

- **SRP (Single Responsibility)** : Le DRY pousse à centraliser chaque responsabilité → renforce le SRP
- **OCP (Open/Closed)** : Un code DRY bien factorisé est plus facile à étendre sans modification
- **DIP (Dependency Inversion)** : L'extraction de la logique commune mène naturellement à des abstractions
- **KISS** : Le DRY doit rester simple — ne pas créer d'abstractions complexes juste pour éviter 2 lignes dupliquées
- **YAGNI** : Ne pas abstraire prématurément "au cas où" — attendre le vrai besoin

## Checklist DRY

Pour chaque base de code, vérifiez :

- [ ] Les règles métier sont-elles définies à un seul endroit ?
- [ ] Les constantes (taux, seuils, URLs) sont-elles centralisées ?
- [ ] Les validations communes sont-elles factorisées ?
- [ ] Les transformations/formatages sont-ils partagés ?
- [ ] La configuration n'est-elle pas dupliquée entre fichiers ?
- [ ] Les données de test utilisent-elles des factories/builders ?
- [ ] Les abstractions créées ont-elles au moins 3 utilisateurs ?
- [ ] La duplication restante est-elle **intentionnelle** (modules découplés) ?

## Résumé

Le DRY est un pilier de la qualité logicielle, mais il demande du discernement :

- **Éliminez** la duplication de **connaissance** (même règle à plusieurs endroits)
- **Tolérez** la duplication de **code** si les concepts sont différents
- **Attendez** d'avoir 3+ cas avant de créer une abstraction (Rule of Three)
- **Préférez** une duplication simple à une mauvaise abstraction
- **Centralisez** constantes, configurations et règles métier

Le vrai DRY, c'est **une seule source de vérité par concept**, pas zéro ligne de code en doublon.
