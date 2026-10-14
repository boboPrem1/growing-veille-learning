# Single Responsibility Principle (SRP)

## Définition

Le **Single Responsibility Principle** (SRP) est le premier principe du SOLID. Il stipule qu'une classe doit avoir une seule et unique raison de changer, ce qui signifie qu'elle ne doit avoir qu'une seule responsabilité.

> "Une classe doit avoir une seule raison de changer." - Robert C. Martin

## Pourquoi c'est important ?

- **Maintenabilité** : Code plus facile à comprendre et à modifier
- **Testabilité** : Classes plus simples à tester unitairement
- **Réutilisabilité** : Responsabilités isolées peuvent être réutilisées
- **Flexibilité** : Moins de couplage entre les fonctionnalités

## Comment identifier une violation du SRP ?

Signes courants :
- Une classe fait trop de choses différentes
- La classe a plusieurs raisons de changer
- Méthodes avec des logiques très différentes
- Classe difficile à nommer précisément

## Exemples pratiques

### ❌ Mauvais exemple : Violation du SRP

```java
public class User {
    private String name;
    private String email;
    
    // Données utilisateur
    public User(String name, String email) {
        this.name = name;
        this.email = email;
    }
    
    // Validation (autre responsabilité)
    public boolean isValid() {
        return email.contains("@") && name.length() > 2;
    }
    
    // Persistance (autre responsabilité)
    public void saveToDatabase() {
        // Code pour sauvegarder en base
    }
    
    // Notification (autre responsabilité)
    public void sendWelcomeEmail() {
        // Code pour envoyer un email
    }
    
    // Getters/Setters
    public String getName() { return name; }
    public String getEmail() { return email; }
}
```

**Problèmes :**
- Gestion des données utilisateur
- Validation des données
- Persistance en base
- Envoi d'emails

### ✅ Bon exemple : Respect du SRP

```java
// 1. Classe de données uniquement
public class User {
    private String name;
    private String email;
    
    public User(String name, String email) {
        this.name = name;
        this.email = email;
    }
    
    // Uniquement des getters/setters
    public String getName() { return name; }
    public String getEmail() { return email; }
}

// 2. Classe de validation
public class UserValidator {
    public boolean isValid(User user) {
        return user.getEmail().contains("@") && 
               user.getName().length() > 2;
    }
}

// 3. Classe de persistance
public class UserRepository {
    public void save(User user) {
        // Code pour sauvegarder en base
    }
}

// 4. Classe de notification
public class EmailService {
    public void sendWelcomeEmail(User user) {
        // Code pour envoyer un email
    }
}

// 5. Service qui orchestre le tout
public class UserService {
    private UserValidator validator;
    private UserRepository repository;
    private EmailService emailService;
    
    public UserService(UserValidator validator, 
                      UserRepository repository, 
                      EmailService emailService) {
        this.validator = validator;
        this.repository = repository;
        this.emailService = emailService;
    }
    
    public void registerUser(String name, String email) {
        User user = new User(name, email);
        
        if (validator.isValid(user)) {
            repository.save(user);
            emailService.sendWelcomeEmail(user);
        }
    }
}
```

## Autres exemples par domaine

### Reporting (exemple courant)

❌ **Mauvais :**
```java
public class ReportGenerator {
    public String generateReport() {
        // 1. Récupération des données
        List<Data> data = fetchData();
        
        // 2. Calcul des statistiques
        Statistics stats = calculateStats(data);
        
        // 3. Formatage du rapport
        String report = formatReport(stats);
        
        // 4. Envoi par email
        sendEmail(report);
        
        return report;
    }
}
```

✅ **Bon :**
```java
public class DataFetcher {
    public List<Data> fetchData() { /* ... */ }
}

public class StatisticsCalculator {
    public Statistics calculate(List<Data> data) { /* ... */ }
}

public class ReportFormatter {
    public String format(Statistics stats) { /* ... */ }
}

public class EmailNotifier {
    public void send(String content) { /* ... */ }
}

public class ReportService {
    private DataFetcher fetcher;
    private StatisticsCalculator calculator;
    private ReportFormatter formatter;
    private EmailNotifier notifier;
    
    public String generateAndSendReport() {
        List<Data> data = fetcher.fetchData();
        Statistics stats = calculator.calculate(data);
        String report = formatter.format(stats);
        notifier.send(report);
        return report;
    }
}
```

### Gestion de fichiers

❌ **Mauvais :**
```java
public class FileManager {
    public void processFile(String path) {
        // 1. Lecture du fichier
        String content = readFile(path);
        
        // 2. Parsing du contenu
        Data data = parseContent(content);
        
        // 3. Validation
        if (!isValid(data)) throw new Exception();
        
        // 4. Sauvegarde
        saveData(data);
    }
}
```

✅ **Bon :**
```java
public class FileReader {
    public String read(String path) { /* ... */ }
}

public class ContentParser {
    public Data parse(String content) { /* ... */ }
}

public class DataValidator {
    public boolean validate(Data data) { /* ... */ }
}

public class DataSaver {
    public void save(Data data) { /* ... */ }
}
```

## Comment appliquer le SRP en pratique

### 1. Identifier les responsabilités
Posez-vous ces questions :
- "Qu'est-ce que cette classe fait exactement ?"
- "Y a-t-il des raisons différentes pour lesquelles cette classe pourrait changer ?"
- "Puis-je décrire cette classe en une seule phrase simple ?"

### 2. Extraire les responsabilités
- Créez des classes séparées pour chaque responsabilité identifiée
- Utilisez l'injection de dépendances pour les faire collaborer
- Créez une classe "orchestrateur" si nécessaire

### 3. Refactoriser progressivement
```java
// Étape 1 : Identifier
public class OrderProcessor {
    public void process(Order order) {
        validateOrder(order);        // Validation
        calculateTotal(order);       // Calcul
        saveToDatabase(order);       // Persistance
        sendConfirmation(order);     // Notification
    }
}

// Étape 2 : Extraire progressivement
public class OrderValidator {
    public void validate(Order order) { /* ... */ }
}

// Étape 3 : Continuer l'extraction
public class OrderCalculator {
    public void calculateTotal(Order order) { /* ... */ }
}

// Étape 4 : Finaliser
public class OrderProcessor {
    private OrderValidator validator;
    private OrderCalculator calculator;
    private OrderRepository repository;
    private NotificationService notifier;
    
    public void process(Order order) {
        validator.validate(order);
        calculator.calculateTotal(order);
        repository.save(order);
        notifier.sendConfirmation(order);
    }
}
```

## Pièges courants à éviter

### 1. "God Classes"
Évitez les classes qui font tout :
```java
// ❌ À éviter
public class UserManager {
    // Gestion des utilisateurs
    // Authentification
    // Permissions
    // Logging
    // Notifications
    // Validation
    // Persistance
    // etc.
}
```

### 2. Classes "Manager" ou "Util" trop larges
```java
// ❌ Mauvais
public class Utils {
    public static String formatDate(Date date) { /* ... */ }
    public static boolean isValidEmail(String email) { /* ... */ }
    public static String generatePassword() { /* ... */ }
    public static void logError(Exception e) { /* ... */ }
    public static double calculateTax(double amount) { /* ... */ }
}

// ✅ Bon
public class DateUtils { /* uniquement formatage de dates */ }
public class EmailValidator { /* uniquement validation emails */ }
public class PasswordGenerator { /* uniquement génération passwords */ }
public class Logger { /* uniquement logging */ }
public class TaxCalculator { /* uniquement calcul taxes */ }
```

### 3. Sur-segmentation
Ne divisez pas trop :
```java
// ❌ Exagéré
public class FirstNameValidator { /* ... */ }
public class LastNameValidator { /* ... */ }
public class EmailValidator { /* ... */ }

// ✅ Équilibré
public class UserValidator {
    public boolean validate(User user) {
        return isValidName(user.getName()) && 
               isValidEmail(user.getEmail());
    }
    
    private boolean isValidName(String name) { /* ... */ }
    private boolean isValidEmail(String email) { /* ... */ }
}
```

## Avantages concrets

### Maintenance
- **Avant** : Modifier la logique d'email nécessite de toucher à la classe User
- **Après** : Modifier EmailService n'impacte que l'email

### Tests
```java
// ❌ Difficile à tester
@Test
void testUser() {
    // Besoin de mock BDD, email, etc.
}

// ✅ Facile à tester unitairement
@Test
void testUserValidation() {
    UserValidator validator = new UserValidator();
    assertTrue(validator.isValid(new User("John", "john@email.com")));
}

@Test
void testUserPersistence() {
    // Mock repository uniquement
}
```

### Réutilisation
```java
// EmailService peut être réutilisé pour d'autres entités
EmailService emailService = new EmailService();
emailService.sendOrderConfirmation(order);
emailService.sendPasswordReset(user);
emailService.sendNewsletter(subscribers);
```

## Checklist SRP

Pour chaque classe, demandez-vous :

- [ ] La classe a-t-elle un seul but clair ?
- [ ] Puis-je la décrire en une phrase ?
- [ ] Y a-t-il plusieurs raisons de la modifier ?
- [ ] Les méthodes ont-elles des logiques cohérentes ?
- [ ] Le nom de la classe reflète-t-il sa seule responsabilité ?
- [ ] Est-elle facile à tester unitairement ?
- [ ] Ses responsabilités pourraient-elles être réutilisées séparément ?

## Résumé

Le SRP est fondamental pour un code maintenable et évolutif. En séparant les responsabilités, vous obtenez :

- **Code plus clair** : Chaque classe a un but précis
- **Maintenance facilitée** : Modifications localisées
- **Tests simplifiés** : Unités logiques isolées
- **Réutilisation accrue** : Composants spécialisés

Commencez petit, identifiez les violations évidentes, et refactoriez progressivement vers un meilleur design.