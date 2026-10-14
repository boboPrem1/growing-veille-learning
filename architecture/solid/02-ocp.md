# Open/Closed Principle (OCP)

## Définition

Le **Open/Closed Principle** (OCP) est le deuxième principe du SOLID. Il stipule que les entités logicielles (classes, modules, fonctions) doivent être **ouvertes à l'extension mais fermées à la modification**.

> "Les entités logicielles doivent être ouvertes à l'extension, mais fermées à la modification." - Bertrand Meyer

## Pourquoi c'est important ?

- **Stabilité** : Le code existant continue de fonctionner sans être modifié
- **Évolutivité** : Nouvelles fonctionnalités ajoutées sans toucher au code existant
- **Maintenance** : Moins de risques de régression lors des évolutions
- **Testabilité** : Tests existants restent valides

## Comment identifier une violation de l'OCP ?

Signes courants :
- Modification fréquente du même code pour ajouter des fonctionnalités
- Conditions `if/else` ou `switch` qui s'allongent avec le temps
- Code qui doit être modifié pour chaque nouveau cas d'usage
- Tests qui doivent être mis à jour régulièrement

## Exemples pratiques

### ❌ Mauvais exemple : Violation de l'OCP

```java
public class ShapeCalculator {
    public double calculateArea(Object shape) {
        if (shape instanceof Circle) {
            Circle circle = (Circle) shape;
            return Math.PI * circle.getRadius() * circle.getRadius();
        } else if (shape instanceof Rectangle) {
            Rectangle rectangle = (Rectangle) shape;
            return rectangle.getWidth() * rectangle.getHeight();
        } else if (shape instanceof Triangle) {
            Triangle triangle = (Triangle) shape;
            return 0.5 * triangle.getBase() * triangle.getHeight();
        }
        // Ajouter un nouveau type = modifier cette méthode
        return 0;
    }
}
```

**Problèmes :**
- Ajouter une nouvelle forme nécessite de modifier `ShapeCalculator`
- Risque de régression sur les formes existantes
- Méthode devient de plus en plus complexe

### ✅ Bon exemple : Respect de l'OCP

```java
// 1. Interface abstraite
public abstract class Shape {
    public abstract double calculateArea();
}

// 2. Implémentations concrètes
public class Circle extends Shape {
    private double radius;
    
    public Circle(double radius) {
        this.radius = radius;
    }
    
    @Override
    public double calculateArea() {
        return Math.PI * radius * radius;
    }
    
    public double getRadius() { return radius; }
}

public class Rectangle extends Shape {
    private double width;
    private double height;
    
    public Rectangle(double width, double height) {
        this.width = width;
        this.height = height;
    }
    
    @Override
    public double calculateArea() {
        return width * height;
    }
    
    public double getWidth() { return width; }
    public double getHeight() { return height; }
}

public class Triangle extends Shape {
    private double base;
    private double height;
    
    public Triangle(double base, double height) {
        this.base = base;
        this.height = height;
    }
    
    @Override
    public double calculateArea() {
        return 0.5 * base * height;
    }
    
    public double getBase() { return base; }
    public double getHeight() { return height; }
}

// 3. Ajout de nouvelles formes sans modifier le code existant
public class Square extends Shape {
    private double side;
    
    public Square(double side) {
        this.side = side;
    }
    
    @Override
    public double calculateArea() {
        return side * side;
    }
}

// 4. Calculator qui n'a pas besoin de changer
public class ShapeCalculator {
    public double calculateTotalArea(List<Shape> shapes) {
        return shapes.stream()
                   .mapToDouble(Shape::calculateArea)
                   .sum();
    }
}
```

## Autres exemples par domaine

### Gestion des notifications

❌ **Mauvais :**
```java
public class NotificationService {
    public void sendNotification(String type, String message, String recipient) {
        if (type.equals("EMAIL")) {
            // Logique d'envoi d'email
            EmailSender.send(recipient, message);
        } else if (type.equals("SMS")) {
            // Logique d'envoi SMS
            SmsSender.send(recipient, message);
        } else if (type.equals("PUSH")) {
            // Logique d'envoi push
            PushSender.send(recipient, message);
        }
        // Ajouter un nouveau type = modifier cette méthode
    }
}
```

✅ **Bon :**
```java
// Interface pour les notifications
public interface NotificationChannel {
    void send(String recipient, String message);
    boolean supports(String type);
}

// Implémentations
public class EmailNotification implements NotificationChannel {
    @Override
    public void send(String recipient, String message) {
        EmailSender.send(recipient, message);
    }
    
    @Override
    public boolean supports(String type) {
        return "EMAIL".equals(type);
    }
}

public class SmsNotification implements NotificationChannel {
    @Override
    public void send(String recipient, String message) {
        SmsSender.send(recipient, message);
    }
    
    @Override
    public boolean supports(String type) {
        return "SMS".equals(type);
    }
}

// Service qui n'a pas besoin de changer
public class NotificationService {
    private List<NotificationChannel> channels;
    
    public NotificationService(List<NotificationChannel> channels) {
        this.channels = channels;
    }
    
    public void sendNotification(String type, String message, String recipient) {
        channels.stream()
                .filter(channel -> channel.supports(type))
                .findFirst()
                .ifPresent(channel -> channel.send(recipient, message));
    }
    
    // Ajout de nouveaux canaux sans modifier cette classe
    public void addChannel(NotificationChannel channel) {
        channels.add(channel);
    }
}
```

### Validation de données

❌ **Mauvais :**
```java
public class UserValidator {
    public boolean validate(User user) {
        // Validation email
        if (!user.getEmail().contains("@")) {
            return false;
        }
        
        // Validation âge
        if (user.getAge() < 18) {
            return false;
        }
        
        // Validation téléphone
        if (user.getPhone() != null && !user.getPhone().matches("\\d{10}")) {
            return false;
        }
        
        // Ajouter une nouvelle règle = modifier cette méthode
        return true;
    }
}
```

✅ **Bon :**
```java
// Interface pour les règles de validation
public interface ValidationRule<T> {
    boolean validate(T entity);
    String getErrorMessage();
}

// Règles concrètes
public class EmailValidationRule implements ValidationRule<User> {
    @Override
    public boolean validate(User user) {
        return user.getEmail() != null && 
               user.getEmail().contains("@");
    }
    
    @Override
    public String getErrorMessage() {
        return "Email invalide";
    }
}

public class AgeValidationRule implements ValidationRule<User> {
    @Override
    public boolean validate(User user) {
        return user.getAge() >= 18;
    }
    
    @Override
    public String getErrorMessage() {
        return "L'utilisateur doit être majeur";
    }
}

public class PhoneValidationRule implements ValidationRule<User> {
    @Override
    public boolean validate(User user) {
        return user.getPhone() == null || 
               user.getPhone().matches("\\d{10}");
    }
    
    @Override
    public String getErrorMessage() {
        return "Numéro de téléphone invalide";
    }
}

// Validator extensible
public class UserValidator {
    private List<ValidationRule<User>> rules;
    
    public UserValidator(List<ValidationRule<User>> rules) {
        this.rules = rules;
    }
    
    public ValidationResult validate(User user) {
        List<String> errors = new ArrayList<>();
        
        for (ValidationRule<User> rule : rules) {
            if (!rule.validate(user)) {
                errors.add(rule.getErrorMessage());
            }
        }
        
        return new ValidationResult(errors.isEmpty(), errors);
    }
    
    // Ajout de nouvelles règles sans modifier cette classe
    public void addRule(ValidationRule<User> rule) {
        rules.add(rule);
    }
}
```

### Calcul de prix

❌ **Mauvais :**
```java
public class PriceCalculator {
    public double calculatePrice(Product product, Customer customer) {
        double price = product.getBasePrice();
        
        // Réduction pour membre premium
        if (customer.isPremium()) {
            price *= 0.9;
        }
        
        // Réduction pour gros volume
        if (product.getQuantity() > 100) {
            price *= 0.95;
        }
        
        // Surcharge pour produits lourds
        if (product.getWeight() > 10) {
            price += 5.0;
        }
        
        // Ajouter une nouvelle règle = modifier cette méthode
        return price;
    }
}
```

✅ **Bon :**
```java
// Interface pour les stratégies de prix
public interface PricingStrategy {
    double apply(double currentPrice, Product product, Customer customer);
}

// Implémentations
public class PremiumDiscountStrategy implements PricingStrategy {
    @Override
    public double apply(double currentPrice, Product product, Customer customer) {
        return customer.isPremium() ? currentPrice * 0.9 : currentPrice;
    }
}

public class VolumeDiscountStrategy implements PricingStrategy {
    @Override
    public double apply(double currentPrice, Product product, Customer customer) {
        return product.getQuantity() > 100 ? currentPrice * 0.95 : currentPrice;
    }
}

public class WeightSurchargeStrategy implements PricingStrategy {
    @Override
    public double apply(double currentPrice, Product product, Customer customer) {
        return product.getWeight() > 10 ? currentPrice + 5.0 : currentPrice;
    }
}

// Calculator extensible
public class PriceCalculator {
    private List<PricingStrategy> strategies;
    
    public PriceCalculator(List<PricingStrategy> strategies) {
        this.strategies = strategies;
    }
    
    public double calculatePrice(Product product, Customer customer) {
        double price = product.getBasePrice();
        
        for (PricingStrategy strategy : strategies) {
            price = strategy.apply(price, product, customer);
        }
        
        return price;
    }
    
    // Ajout de nouvelles stratégies sans modifier cette classe
    public void addStrategy(PricingStrategy strategy) {
        strategies.add(strategy);
    }
}
```

## Patterns qui respectent l'OCP

### 1. Strategy Pattern
Permet de définir une famille d'algorithmes, encapsuler chacun et les rendre interchangeables.

```java
public interface PaymentStrategy {
    boolean processPayment(double amount);
}

public class CreditCardPayment implements PaymentStrategy {
    @Override
    public boolean processPayment(double amount) {
        // Logique carte de crédit
        return true;
    }
}

public class PayPalPayment implements PaymentStrategy {
    @Override
    public boolean processPayment(double amount) {
        // Logique PayPal
        return true;
    }
}

public class PaymentProcessor {
    private PaymentStrategy strategy;
    
    public PaymentProcessor(PaymentStrategy strategy) {
        this.strategy = strategy;
    }
    
    public boolean process(double amount) {
        return strategy.processPayment(amount);
    }
}
```

### 2. Template Method Pattern
Définit le squelette d'un algorithme et laisse les sous-classes implémenter certaines étapes.

```java
public abstract class DataProcessor {
    // Template method - ne change pas
    public final void processData() {
        loadData();
        validateData();
        transformData();
        saveData();
    }
    
    protected abstract void loadData();
    protected abstract void validateData();
    protected abstract void transformData();
    protected abstract void saveData();
}

public class CsvDataProcessor extends DataProcessor {
    @Override
    protected void loadData() {
        // Charger depuis CSV
    }
    
    @Override
    protected void validateData() {
        // Validation spécifique CSV
    }
    
    @Override
    protected void transformData() {
        // Transformation spécifique CSV
    }
    
    @Override
    protected void saveData() {
        // Sauvegarde spécifique CSV
    }
}
```

### 3. Observer Pattern
Permet à des objets d'être notifiés des changements d'état d'autres objets.

```java
public interface EventListener {
    void onEvent(String eventType, Object data);
}

public class EmailListener implements EventListener {
    @Override
    public void onEvent(String eventType, Object data) {
        if ("USER_REGISTERED".equals(eventType)) {
            // Envoyer email de bienvenue
        }
    }
}

public class LoggingListener implements EventListener {
    @Override
    public void onEvent(String eventType, Object data) {
        // Logger l'événement
    }
}

public class EventManager {
    private List<EventListener> listeners = new ArrayList<>();
    
    public void subscribe(EventListener listener) {
        listeners.add(listener);
    }
    
    public void notify(String eventType, Object data) {
        for (EventListener listener : listeners) {
            listener.onEvent(eventType, data);
        }
    }
}
```

## Comment appliquer l'OCP en pratique

### 1. Identifier les points d'extension
Cherchez les endroits où le code pourrait évoluer :
- Nouveaux types d'entités
- Nouvelles règles métier
- Nouveaux formats de données
- Nouveaux canaux de communication

### 2. Utiliser l'abstraction
Créez des interfaces ou classes abstraites pour représenter les concepts extensibles.

### 3. Encapsuler la variation
Isolez ce qui change dans des classes séparées.

### 4. Composer plutôt qu'hériter
Préférez la composition à l'héritage pour plus de flexibilité.

## Refactorisation étape par étape

### Étape 1 : Identifier le code qui change
```java
// Code qui change souvent
public class ReportGenerator {
    public String generate(String format) {
        if (format.equals("PDF")) {
            return generatePdf();
        } else if (format.equals("EXCEL")) {
            return generateExcel();
        }
        // Nouveaux formats = modification
        return "";
    }
}
```

### Étape 2 : Créer l'abstraction
```java
public interface ReportFormatter {
    String format(ReportData data);
}
```

### Étape 3 : Implémenter les variations
```java
public class PdfFormatter implements ReportFormatter {
    @Override
    public String format(ReportData data) {
        return generatePdf(data);
    }
}

public class ExcelFormatter implements ReportFormatter {
    @Override
    public String format(ReportData data) {
        return generateExcel(data);
    }
}
```

### Étape 4 : Refactoriser la classe originale
```java
public class ReportGenerator {
    private Map<String, ReportFormatter> formatters;
    
    public ReportGenerator(Map<String, ReportFormatter> formatters) {
        this.formatters = formatters;
    }
    
    public String generate(String format, ReportData data) {
        ReportFormatter formatter = formatters.get(format);
        return formatter != null ? formatter.format(data) : "";
    }
    
    // Ajouter de nouveaux formatters sans modifier cette classe
    public void addFormatter(String format, ReportFormatter formatter) {
        formatters.put(format, formatter);
    }
}
```

## Pièges courants à éviter

### 1. Sur-abstraction
Ne créez pas d'abstractions pour tout :
```java
// ❌ Exagéré
public interface StringOperation {
    String execute(String input);
}

public class StringConcatenator implements StringOperation {
    @Override
    public String execute(String input) {
        return input + "suffix";
    }
}

// ✅ Simple et direct
public class StringUtils {
    public static String addSuffix(String input) {
        return input + "suffix";
    }
}
```

### 2. Prématurité
N'appliquez pas l'OCP si vous n'avez pas encore de preuve que le code va changer :
```java
// ❌ Prématuré
public interface PaymentMethod {
    void pay();
}

// ✅ Commencez simple
public class PaymentService {
    public void processPayment() {
        // Logique simple
    }
}
```

### 3. Complexité excessive
Évitez de rendre le code trop complexe au nom de l'OCP :
```java
// ❌ Trop complexe pour peu de valeur
public class NumberCalculator {
    private List<CalculationStrategy> strategies;
    
    public NumberCalculator(List<CalculationStrategy> strategies) {
        this.strategies = strategies;
    }
    
    public int add(int a, int b) {
        return strategies.stream()
                        .mapToInt(s -> s.calculate(a, b))
                        .sum();
    }
}

// ✅ Simple et efficace
public class NumberCalculator {
    public int add(int a, int b) {
        return a + b;
    }
}
```

## Avantages concrets

### Maintenance
- **Avant** : Ajouter un nouveau format de rapport = modifier `ReportGenerator`
- **Après** : Ajouter un nouveau format = créer `NewFormatter` et l'enregistrer

### Tests
```java
// ❌ Tests qui cassent à chaque ajout
@Test
void testReportGenerator() {
    ReportGenerator generator = new ReportGenerator();
    // Doit tester tous les formats existants
    // Nouveau format = modifier le test
}

// ✅ Tests isolés et stables
@Test
void testPdfFormatter() {
    PdfFormatter formatter = new PdfFormatter();
    // Test uniquement le formatage PDF
}

@Test
void testReportGenerator() {
    Map<String, ReportFormatter> formatters = Map.of("PDF", new PdfFormatter());
    ReportGenerator generator = new ReportGenerator(formatters);
    // Test stable, ne change pas avec l'ajout de formats
}
```

### Extensibilité
```java
// Ajout de nouvelles fonctionnalités sans toucher au code existant
public class JsonFormatter implements ReportFormatter {
    @Override
    public String format(ReportData data) {
        // Formatage JSON
        return toJson(data);
    }
}

// Enregistrement dynamique
reportGenerator.addFormatter("JSON", new JsonFormatter());
```

## Checklist OCP

Pour chaque classe, demandez-vous :

- [ ] Est-ce que cette classe doit être modifiée pour ajouter de nouvelles fonctionnalités ?
- [ ] Puis-je ajouter de nouveaux comportements sans modifier le code existant ?
- [ ] Les `if/else` ou `switch` peuvent-ils être remplacés par du polymorphisme ?
- [ ] Les abstractions sont-elles appropriées (ni trop, ni trop peu) ?
- [ ] Le code est-il prêt à évoluer sans risque de régression ?
- [ ] Les tests existants resteront-ils valides avec de nouvelles fonctionnalités ?

## Résumé

L'OCP est essentiel pour un code évolutif et maintenable. En l'appliquant, vous obtenez :

- **Stabilité** : Code existant protégé des modifications
- **Extensibilité** : Nouvelles fonctionnalités ajoutées proprement
- **Moins de régressions** : Tests existants restent valides
- **Architecture flexible** : Prête à évoluer avec les besoins métier

Commencez par identifier les points de changement fréquents, appliquez l'OCP progressivement, et trouvez le bon équilibre entre simplicité et extensibilité.