# Dependency Inversion Principle (DIP)

## Définition

Le **Dependency Inversion Principle** (DIP) est le cinquième et dernier principe du SOLID. Il stipule que :

1. **Les modules de haut niveau ne doivent pas dépendre des modules de bas niveau. Les deux doivent dépendre d'abstractions.**
2. **Les abstractions ne doivent pas dépendre des détails. Les détails doivent dépendre des abstractions.**

> "Dépendez des abstractions, pas des implémentations concrètes." - Robert C. Martin

En termes simples : **les classes doivent dépendre d'interfaces ou de classes abstraites, pas de classes concrètes**.

## Pourquoi c'est important ?

- **Découplage** : Réduction des dépendances entre les modules
- **Testabilité** : Facilite les mocks et les tests unitaires
- **Flexibilité** : Permet de changer les implémentations sans modifier le code
- **Maintenance** : Modifications isolées aux implémentations concrètes

## Comment identifier une violation du DIP ?

Signes courants :
- Classes qui instancient directement d'autres classes (`new`)
- Dépendances "hard-codées" dans le code
- Difficulté à tester une classe sans ses dépendances réelles
- Modifications nécessaires dans plusieurs classes pour changer une implémentation

## Exemples pratiques

### ❌ Mauvais exemple : Violation du DIP

```java
// Module de haut niveau
public class LightSwitch {
    private LightBulb lightBulb;
    
    public LightSwitch() {
        // Dépendance directe sur l'implémentation concrète - VIOLATION DIP
        this.lightBulb = new LightBulb();
    }
    
    public void turnOn() {
        lightBulb.turnOn();
    }
    
    public void turnOff() {
        lightBulb.turnOff();
    }
}

// Module de bas niveau
public class LightBulb {
    public void turnOn() {
        System.out.println("Light bulb turned on");
    }
    
    public void turnOff() {
        System.out.println("Light bulb turned off");
    }
}

// Problème : LightSwitch ne peut fonctionner qu'avec LightBulb
// Impossible de tester LightSwitch sans LightBulb réelle
// Impossible de remplacer LightBulb par une autre lampe
```

### ✅ Bon exemple : Respect du DIP

```java
// 1. Abstraction (détail ne dépend pas de l'abstraction)
public interface Switchable {
    void turnOn();
    void turnOff();
}

// 2. Module de haut niveau (dépend de l'abstraction)
public class LightSwitch {
    private Switchable device;
    
    // Injection de dépendance via constructeur
    public LightSwitch(Switchable device) {
        this.device = device; // Dépend de l'abstraction, pas de l'implémentation
    }
    
    public void turnOn() {
        device.turnOn();
    }
    
    public void turnOff() {
        device.turnOff();
    }
}

// 3. Modules de bas niveau (dépendent de l'abstraction)
public class LightBulb implements Switchable {
    @Override
    public void turnOn() {
        System.out.println("Light bulb turned on");
    }
    
    @Override
    public void turnOff() {
        System.out.println("Light bulb turned off");
    }
}

public class Fan implements Switchable {
    @Override
    public void turnOn() {
        System.out.println("Fan turned on");
    }
    
    @Override
    public void turnOff() {
        System.out.println("Fan turned off");
    }
}

// 4. Configuration et utilisation
public class Main {
    public static void main(String[] args) {
        // Peut fonctionner avec n'importe quel Switchable
        Switchable lightBulb = new LightBulb();
        LightSwitch lightSwitch = new LightSwitch(lightBulb);
        lightSwitch.turnOn();
        
        Switchable fan = new Fan();
        LightSwitch fanSwitch = new LightSwitch(fan);
        fanSwitch.turnOn();
    }
}
```

## Autres exemples par domaine

### Gestion de notifications

❌ **Mauvais :**
```java
public class UserService {
    private EmailNotification emailNotification;
    
    public UserService() {
        // Dépendance directe - VIOLATION DIP
        this.emailNotification = new EmailNotification();
    }
    
    public void registerUser(User user) {
        // Logique d'enregistrement...
        emailNotification.sendWelcomeEmail(user);
    }
}

public class EmailNotification {
    public void sendWelcomeEmail(User user) {
        // Envoyer email
    }
}
```

✅ **Bon :**
```java
// 1. Abstraction
public interface NotificationService {
    void sendWelcomeMessage(User user);
    void sendPasswordReset(User user);
}

// 2. Module de haut niveau
public class UserService {
    private NotificationService notificationService;
    private UserRepository userRepository;
    
    // Injection via constructeur
    public UserService(NotificationService notificationService, UserRepository userRepository) {
        this.notificationService = notificationService;
        this.userRepository = userRepository;
    }
    
    public void registerUser(User user) {
        userRepository.save(user);
        notificationService.sendWelcomeMessage(user);
    }
    
    public void resetPassword(User user) {
        // Logique de reset...
        notificationService.sendPasswordReset(user);
    }
}

// 3. Implémentations concrètes
public class EmailNotificationService implements NotificationService {
    @Override
    public void sendWelcomeMessage(User user) {
        System.out.println("Sending welcome email to " + user.getEmail());
    }
    
    @Override
    public void sendPasswordReset(User user) {
        System.out.println("Sending password reset email to " + user.getEmail());
    }
}

public class SmsNotificationService implements NotificationService {
    @Override
    public void sendWelcomeMessage(User user) {
        System.out.println("Sending welcome SMS to " + user.getPhone());
    }
    
    @Override
    public void sendPasswordReset(User user) {
        System.out.println("Sending password reset SMS to " + user.getPhone());
    }
}

public class PushNotificationService implements NotificationService {
    @Override
    public void sendWelcomeMessage(User user) {
        System.out.println("Sending welcome push notification to " + user.getDeviceId());
    }
    
    @Override
    public void sendPasswordReset(User user) {
        System.out.println("Sending password reset push notification");
    }
}
```

### Persistance de données

❌ **Mauvais :**
```java
public class OrderService {
    private MySqlOrderRepository orderRepository;
    
    public OrderService() {
        // Dépendance directe à MySQL - VIOLATION DIP
        this.orderRepository = new MySqlOrderRepository();
    }
    
    public Order createOrder(Order order) {
        // Validation...
        return orderRepository.save(order);
    }
    
    public Order getOrder(Long id) {
        return orderRepository.findById(id);
    }
}

public class MySqlOrderRepository {
    public Order save(Order order) {
        // Logique MySQL spécifique
        return order;
    }
    
    public Order findById(Long id) {
        // Logique MySQL spécifique
        return null;
    }
}
```

✅ **Bon :**
```java
// 1. Abstractions
public interface OrderRepository {
    Order save(Order order);
    Order findById(Long id);
    List<Order> findByCustomer(Long customerId);
    void delete(Long id);
}

public interface PaymentProcessor {
    boolean processPayment(Order order);
}

// 2. Module de haut niveau
public class OrderService {
    private OrderRepository orderRepository;
    private PaymentProcessor paymentProcessor;
    private NotificationService notificationService;
    
    // Injection de toutes les dépendances
    public OrderService(OrderRepository orderRepository, 
                        PaymentProcessor paymentProcessor,
                        NotificationService notificationService) {
        this.orderRepository = orderRepository;
        this.paymentProcessor = paymentProcessor;
        this.notificationService = notificationService;
    }
    
    public Order createOrder(Order order) {
        // Validation
        validateOrder(order);
        
        // Sauvegarde
        Order savedOrder = orderRepository.save(order);
        
        // Paiement
        boolean paymentSuccess = paymentProcessor.processPayment(savedOrder);
        if (!paymentSuccess) {
            throw new PaymentException("Payment failed");
        }
        
        // Notification
        notificationService.sendOrderConfirmation(savedOrder);
        
        return savedOrder;
    }
    
    public Order getOrder(Long id) {
        return orderRepository.findById(id);
    }
    
    private void validateOrder(Order order) {
        // Logique de validation
    }
}

// 3. Implémentations concrètes
public class MySqlOrderRepository implements OrderRepository {
    @Override
    public Order save(Order order) {
        // Logique MySQL spécifique
        System.out.println("Saving order to MySQL");
        return order;
    }
    
    @Override
    public Order findById(Long id) {
        // Logique MySQL spécifique
        System.out.println("Finding order in MySQL");
        return null;
    }
    
    @Override
    public List<Order> findByCustomer(Long customerId) {
        // Logique MySQL spécifique
        return new ArrayList<>();
    }
    
    @Override
    public void delete(Long id) {
        // Logique MySQL spécifique
        System.out.println("Deleting order from MySQL");
    }
}

public class PostgreSqlOrderRepository implements OrderRepository {
    @Override
    public Order save(Order order) {
        // Logique PostgreSQL spécifique
        System.out.println("Saving order to PostgreSQL");
        return order;
    }
    
    @Override
    public Order findById(Long id) {
        // Logique PostgreSQL spécifique
        System.out.println("Finding order in PostgreSQL");
        return null;
    }
    
    @Override
    public List<Order> findByCustomer(Long customerId) {
        // Logique PostgreSQL spécifique
        return new ArrayList<>();
    }
    
    @Override
    public void delete(Long id) {
        // Logique PostgreSQL spécifique
        System.out.println("Deleting order from PostgreSQL");
    }
}

public class CreditCardPaymentProcessor implements PaymentProcessor {
    @Override
    public boolean processPayment(Order order) {
        System.out.println("Processing credit card payment");
        return true;
    }
}

public class PayPalPaymentProcessor implements PaymentProcessor {
    @Override
    public boolean processPayment(Order order) {
        System.out.println("Processing PayPal payment");
        return true;
    }
}
```

### Logging

❌ **Mauvais :**
```java
public class DataProcessor {
    private FileLogger fileLogger;
    
    public DataProcessor() {
        // Dépendance directe - VIOLATION DIP
        this.fileLogger = new FileLogger();
    }
    
    public void processData(String data) {
        try {
            // Traitement des données
            fileLogger.log("Data processed successfully");
        } catch (Exception e) {
            fileLogger.log("Error processing data: " + e.getMessage());
        }
    }
}

public class FileLogger {
    public void log(String message) {
        // Écrire dans un fichier
        System.out.println("Writing to file: " + message);
    }
}
```

✅ **Bon :**
```java
// 1. Abstraction
public interface Logger {
    void log(String message);
    void logError(String error);
    void logInfo(String info);
    void logDebug(String debug);
}

// 2. Module de haut niveau
public class DataProcessor {
    private Logger logger;
    
    public DataProcessor(Logger logger) {
        this.logger = logger; // Dépend de l'abstraction
    }
    
    public void processData(String data) {
        try {
            // Traitement des données
            logger.logInfo("Data processed successfully");
            logger.logDebug("Processing details: " + data);
        } catch (Exception e) {
            logger.logError("Error processing data: " + e.getMessage());
        }
    }
}

// 3. Implémentations concrètes
public class FileLogger implements Logger {
    @Override
    public void log(String message) {
        System.out.println("FILE: " + message);
    }
    
    @Override
    public void logError(String error) {
        System.out.println("FILE ERROR: " + error);
    }
    
    @Override
    public void logInfo(String info) {
        System.out.println("FILE INFO: " + info);
    }
    
    @Override
    public void logDebug(String debug) {
        System.out.println("FILE DEBUG: " + debug);
    }
}

public class ConsoleLogger implements Logger {
    @Override
    public void log(String message) {
        System.out.println("CONSOLE: " + message);
    }
    
    @Override
    public void logError(String error) {
        System.err.println("CONSOLE ERROR: " + error);
    }
    
    @Override
    public void logInfo(String info) {
        System.out.println("CONSOLE INFO: " + info);
    }
    
    @Override
    public void logDebug(String debug) {
        System.out.println("CONSOLE DEBUG: " + debug);
    }
}

public class DatabaseLogger implements Logger {
    @Override
    public void log(String message) {
        System.out.println("DATABASE: " + message);
    }
    
    @Override
    public void logError(String error) {
        System.out.println("DATABASE ERROR: " + error);
    }
    
    @Override
    public void logInfo(String info) {
        System.out.println("DATABASE INFO: " + info);
    }
    
    @Override
    public void logDebug(String debug) {
        System.out.println("DATABASE DEBUG: " + debug);
    }
}
```

## Patterns d'injection de dépendances

### 1. Constructor Injection (recommandé)

```java
public class OrderService {
    private final OrderRepository orderRepository;
    private final PaymentProcessor paymentProcessor;
    
    // Injection via constructeur - garantit que les dépendances sont présentes
    public OrderService(OrderRepository orderRepository, PaymentProcessor paymentProcessor) {
        this.orderRepository = orderRepository;
        this.paymentProcessor = paymentProcessor;
    }
    
    public Order createOrder(Order order) {
        // Utilisation des dépendances
        return orderRepository.save(order);
    }
}
```

**Avantages :**
- Dépendances immuables (final)
- Garantit que l'objet est dans un état valide
- Facile à tester

### 2. Setter Injection

```java
public class OrderService {
    private OrderRepository orderRepository;
    private PaymentProcessor paymentProcessor;
    
    // Injection via setters
    public void setOrderRepository(OrderRepository orderRepository) {
        this.orderRepository = orderRepository;
    }
    
    public void setPaymentProcessor(PaymentProcessor paymentProcessor) {
        this.paymentProcessor = paymentProcessor;
    }
    
    public Order createOrder(Order order) {
        if (orderRepository == null) {
            throw new IllegalStateException("OrderRepository not set");
        }
        return orderRepository.save(order);
    }
}
```

**Avantages :**
- Permet les dépendances optionnelles
- Permet de changer les dépendances après création

**Inconvénients :**
- Objet peut être dans un état invalide
- Plus difficile à garantir la cohérence

### 3. Interface Injection

```java
public interface OrderRepositoryInjector {
    void injectOrderRepository(OrderRepository orderRepository);
}

public class OrderService implements OrderRepositoryInjector {
    private OrderRepository orderRepository;
    
    @Override
    public void injectOrderRepository(OrderRepository orderRepository) {
        this.orderRepository = orderRepository;
    }
    
    public Order createOrder(Order order) {
        return orderRepository.save(order);
    }
}
```

**Avantages :**
- Explicitement défini par l'interface
- Claire pour les clients

**Inconvénients :**
- Plus verbeux
- Moins courant

### 4. Field Injection (à éviter)

```java
public class OrderService {
    @Inject
    private OrderRepository orderRepository; // Non recommandé
    
    public Order createOrder(Order order) {
        return orderRepository.save(order);
    }
}
```

**Inconvénients :**
- Dépendances cachées
- Difficile à tester
- Brise l'immuabilité

## Conteneurs d'injection de dépendances

### Configuration manuelle

```java
public class DependencyContainer {
    private Map<Class<?>, Object> dependencies = new HashMap<>();
    
    public <T> void register(Class<T> type, T implementation) {
        dependencies.put(type, implementation);
    }
    
    public <T> T get(Class<T> type) {
        return type.cast(dependencies.get(type));
    }
    
    public static void main(String[] args) {
        // Configuration des dépendances
        DependencyContainer container = new DependencyContainer();
        
        // Enregistrement des implémentations
        container.register(OrderRepository.class, new MySqlOrderRepository());
        container.register(PaymentProcessor.class, new CreditCardPaymentProcessor());
        container.register(NotificationService.class, new EmailNotificationService());
        
        // Création du service avec ses dépendances
        OrderService orderService = new OrderService(
            container.get(OrderRepository.class),
            container.get(PaymentProcessor.class),
            container.get(NotificationService.class)
        );
        
        // Utilisation
        Order order = new Order();
        orderService.createOrder(order);
    }
}
```

### Avec un framework (Spring)

```java
@Configuration
public class ApplicationConfig {
    
    @Bean
    public OrderRepository orderRepository() {
        return new MySqlOrderRepository();
    }
    
    @Bean
    public PaymentProcessor paymentProcessor() {
        return new CreditCardPaymentProcessor();
    }
    
    @Bean
    public NotificationService notificationService() {
        return new EmailNotificationService();
    }
    
    @Bean
    public OrderService orderService(OrderRepository orderRepository,
                                   PaymentProcessor paymentProcessor,
                                   NotificationService notificationService) {
        return new OrderService(orderRepository, paymentProcessor, notificationService);
    }
}

@Service
public class OrderService {
    private final OrderRepository orderRepository;
    private final PaymentProcessor paymentProcessor;
    private final NotificationService notificationService;
    
    // Injection automatique par Spring
    public OrderService(OrderRepository orderRepository,
                        PaymentProcessor paymentProcessor,
                        NotificationService notificationService) {
        this.orderRepository = orderRepository;
        this.paymentProcessor = paymentProcessor;
        this.notificationService = notificationService;
    }
}
```

## Comment appliquer le DIP en pratique

### 1. Identifier les dépendances

```java
public class ReportGenerator {
    public void generateReport() {
        // Dépendances identifiées :
        // - DatabaseConnection (accès aux données)
        // - FileExporter (exportation)
        // - EmailService (notification)
        // - Logger (logging)
    }
}
```

### 2. Créer les abstractions

```java
public interface DatabaseConnection {
    List<Data> fetchData(String query);
    void close();
}

public interface FileExporter {
    void exportToFile(List<Data> data, String filename);
}

public interface EmailService {
    void sendEmail(String to, String subject, String content);
}

public interface Logger {
    void log(String message);
}
```

### 3. Implémenter les classes concrètes

```java
public class MySqlDatabaseConnection implements DatabaseConnection {
    @Override
    public List<Data> fetchData(String query) {
        // Implémentation MySQL
        return new ArrayList<>();
    }
    
    @Override
    public void close() {
        // Fermer connexion MySQL
    }
}

public class PdfFileExporter implements FileExporter {
    @Override
    public void exportToFile(List<Data> data, String filename) {
        // Exporter en PDF
    }
}

public class GmailEmailService implements EmailService {
    @Override
    public void sendEmail(String to, String subject, String content) {
        // Envoyer via Gmail
    }
}

public class ConsoleLogger implements Logger {
    @Override
    public void log(String message) {
        System.out.println(message);
    }
}
```

### 4. Refactoriser la classe de haut niveau

```java
public class ReportGenerator {
    private final DatabaseConnection databaseConnection;
    private final FileExporter fileExporter;
    private final EmailService emailService;
    private final Logger logger;
    
    // Injection de toutes les dépendances
    public ReportGenerator(DatabaseConnection databaseConnection,
                         FileExporter fileExporter,
                         EmailService emailService,
                         Logger logger) {
        this.databaseConnection = databaseConnection;
        this.fileExporter = fileExporter;
        this.emailService = emailService;
        this.logger = logger;
    }
    
    public void generateReport() {
        try {
            logger.log("Starting report generation");
            
            List<Data> data = databaseConnection.fetchData("SELECT * FROM reports");
            fileExporter.exportToFile(data, "report.pdf");
            emailService.sendEmail("manager@company.com", "Report Ready", "The report is ready");
            
            logger.log("Report generated successfully");
        } catch (Exception e) {
            logger.log("Error generating report: " + e.getMessage());
        } finally {
            databaseConnection.close();
        }
    }
}
```

## Refactorisation étape par étape

### Étape 1 : Identifier les dépendances directes
```java
public class PaymentService {
    private CreditCardProcessor processor = new CreditCardProcessor(); // Dépendance directe
    private EmailNotifier notifier = new EmailNotifier(); // Dépendance directe
    
    public void processPayment(Payment payment) {
        processor.charge(payment);
        notifier.sendConfirmation(payment);
    }
}
```

### Étape 2 : Extraire les abstractions
```java
public interface PaymentProcessor {
    boolean charge(Payment payment);
}

public interface NotificationService {
    void sendConfirmation(Payment payment);
}
```

### Étape 3 : Implémenter les abstractions
```java
public class CreditCardProcessor implements PaymentProcessor {
    @Override
    public boolean charge(Payment payment) {
        // Logique carte de crédit
        return true;
    }
}

public class PayPalProcessor implements PaymentProcessor {
    @Override
    public boolean charge(Payment payment) {
        // Logique PayPal
        return true;
    }
}

public class EmailNotifier implements NotificationService {
    @Override
    public void sendConfirmation(Payment payment) {
        // Logique email
    }
}

public class SmsNotifier implements NotificationService {
    @Override
    public void sendConfirmation(Payment payment) {
        // Logique SMS
    }
}
```

### Étape 4 : Refactoriser la classe de haut niveau
```java
public class PaymentService {
    private final PaymentProcessor paymentProcessor;
    private final NotificationService notificationService;
    
    public PaymentService(PaymentProcessor paymentProcessor, 
                         NotificationService notificationService) {
        this.paymentProcessor = paymentProcessor;
        this.notificationService = notificationService;
    }
    
    public void processPayment(Payment payment) {
        boolean success = paymentProcessor.charge(payment);
        if (success) {
            notificationService.sendConfirmation(payment);
        }
    }
}
```

## Pièges courants à éviter

### 1. Abstractions trop larges
```java
// ❌ Abstraction trop large
public interface SystemService {
    void processPayment();
    void sendEmail();
    void saveData();
    void generateReport();
    void authenticateUser();
}

// ✅ Abstractions spécifiques
public interface PaymentProcessor {
    boolean processPayment(Payment payment);
}

public interface EmailService {
    void sendEmail(String to, String subject, String content);
}
```

### 2. Dépendances cycliques
```java
// ❌ Dépendance cyclique
public class ServiceA {
    private ServiceB serviceB;
    
    public ServiceA(ServiceB serviceB) {
        this.serviceB = serviceB;
    }
}

public class ServiceB {
    private ServiceA serviceA;
    
    public ServiceB(ServiceA serviceA) {
        this.serviceA = serviceA;
    }
}

// ✅ Solution : introduire une abstraction
public interface ServiceAInterface {
    void doSomething();
}

public class ServiceA implements ServiceAInterface {
    private ServiceB serviceB;
    
    public ServiceA(ServiceB serviceB) {
        this.serviceB = serviceB;
    }
    
    @Override
    public void doSomething() {
        // Logique
    }
}

public class ServiceB {
    private ServiceAInterface serviceA;
    
    public ServiceB(ServiceAInterface serviceA) {
        this.serviceA = serviceA;
    }
}
```

### 3. Injection de trop nombreuses dépendances
```java
// ❌ Trop de dépendances
public class GodService {
    public GodService(ServiceA a, ServiceB b, ServiceC c, ServiceD d, 
                    ServiceE e, ServiceF f, ServiceG g, ServiceH h) {
        // Constructeur trop complexe
    }
}

// ✅ Diviser en responsabilités
public class PaymentService {
    public PaymentService(PaymentProcessor processor, NotificationService notifier) {
        // Responsabilité unique
    }
}

public class UserService {
    public UserService(UserRepository repository, EmailService emailService) {
        // Responsabilité unique
    }
}
```

### 4. Ignorer le cycle de vie des dépendances
```java
// ❌ Problème de cycle de vie
public class DatabaseService {
    private Connection connection;
    
    public DatabaseService() {
        this.connection = new Connection(); // Connexion créée trop tôt
    }
}

// ✅ Gestion appropriée du cycle de vie
public class DatabaseService {
    private Connection connection;
    
    public void initialize() {
        this.connection = new Connection(); // Initialisation explicite
    }
    
    public void cleanup() {
        if (connection != null) {
            connection.close();
        }
    }
}
```

## Avantages concrets

### Testabilité
```java
// ✅ Tests faciles avec des mocks
@Test
void testOrderService() {
    // Création de mocks
    OrderRepository mockRepo = mock(OrderRepository.class);
    PaymentProcessor mockProcessor = mock(PaymentProcessor.class);
    NotificationService mockNotifier = mock(NotificationService.class);
    
    // Configuration des mocks
    when(mockRepo.save(any())).thenReturn(new Order());
    when(mockProcessor.processPayment(any())).thenReturn(true);
    
    // Création du service avec des dépendances mockées
    OrderService orderService = new OrderService(mockRepo, mockProcessor, mockNotifier);
    
    // Test
    Order order = orderService.createOrder(new Order());
    
    // Vérifications
    verify(mockRepo).save(any());
    verify(mockProcessor).processPayment(any());
    verify(mockNotifier).sendOrderConfirmation(any());
}
```

### Flexibilité
```java
// ✅ Changement d'implémentation sans modifier le code
public class Application {
    public static void main(String[] args) {
        // Configuration pour le développement
        if (args.length > 0 && args[0].equals("dev")) {
            OrderRepository repo = new InMemoryOrderRepository();
            PaymentProcessor processor = new MockPaymentProcessor();
            NotificationService notifier = new ConsoleNotificationService();
            
            OrderService service = new OrderService(repo, processor, notifier);
        }
        // Configuration pour la production
        else {
            OrderRepository repo = new MySqlOrderRepository();
            PaymentProcessor processor = new CreditCardPaymentProcessor();
            NotificationService notifier = new EmailNotificationService();
            
            OrderService service = new OrderService(repo, processor, notifier);
        }
    }
}
```

### Maintenance
```java
// ✅ Ajout de nouvelles fonctionnalités sans modifier le code existant
public class StripePaymentProcessor implements PaymentProcessor {
    @Override
    public boolean processPayment(Payment payment) {
        // Nouvelle implémentation Stripe
        return true;
    }
}

// Le service existant fonctionne avec la nouvelle implémentation
OrderService service = new OrderService(repo, new StripePaymentProcessor(), notifier);
```

## Checklist DIP

Pour chaque classe, demandez-vous :

- [ ] La classe dépend-elle d'abstractions plutôt que d'implémentations concrètes ?
- [ ] Les dépendances sont-elles injectées plutôt qu'instanciées en interne ?
- [ ] Les abstractions sont-elles stables et ne changent-elles pas souvent ?
- [ ] Les implémentations concrètes dépendent-elles des abstractions ?
- [ ] Le code est-il facile à tester sans dépendances réelles ?
- [ ] Puis-je changer les implémentations sans modifier le code client ?
- [ ] Les dépendances sont-elles clairement visibles (constructeur) ?

## Résumé

Le DIP est fondamental pour une architecture découplée et maintenable. En l'appliquant, vous obtenez :

- **Découplage maximal** : Modules indépendants
- **Testabilité accrue** : Tests isolés et rapides
- **Flexibilité** : Changement d'implémentation sans impact
- **Maintenance facilitée** : Modifications localisées

Créez des abstractions stables, injectez les dépendances, et utilisez des conteneurs pour gérer le cycle de vie des objets. Votre code devient plus robuste, testable et évolutif.