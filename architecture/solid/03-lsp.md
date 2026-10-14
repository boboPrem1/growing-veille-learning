# Liskov Substitution Principle (LSP)

## Définition

Le **Liskov Substitution Principle** (LSP) est le troisième principe du SOLID. Il stipule que si `S` est un sous-type de `T`, alors les objets de type `T` peuvent être remplacés par des objets de type `S` sans altérer les propriétés du programme (correction, tâches effectuées, etc.).

> "Les fonctions qui utilisent des pointeurs ou références à des classes de base doivent pouvoir utiliser des objets de classes dérivées sans le savoir." - Robert C. Martin

En termes simples : **un objet d'une classe fille doit pouvoir être utilisé partout où un objet de sa classe mère est attendu**.

## Pourquoi c'est important ?

- **Polymorphisme correct** : Garantit que l'héritage fonctionne comme attendu
- **Fiabilité** : Évite les comportements inattendus lors de la substitution
- **Réutilisabilité** : Code client fonctionne avec toutes les implémentations
- **Testabilité** : Tests peuvent utiliser des mocks sans surprises

## Comment identifier une violation du LSP ?

Signes courants :
- Une classe fille lève des exceptions que la classe mère ne lève pas
- Une classe fille retourne `null` alors que la mère ne le fait jamais
- Une classe fille a des préconditions plus strictes que la mère
- Une classe fille a des postconditions plus faibles que la mère
- Le code client doit vérifier le type concret avant d'utiliser un objet

## Exemples pratiques

### ❌ Mauvais exemple : Violation du LSP

```java
public class Rectangle {
    protected double width;
    protected double height;
    
    public void setWidth(double width) {
        this.width = width;
    }
    
    public void setHeight(double height) {
        this.height = height;
    }
    
    public double getWidth() { return width; }
    public double getHeight() { return height; }
    
    public double getArea() {
        return width * height;
    }
}

// Carré qui hérite de Rectangle - VIOLATION LSP
public class Square extends Rectangle {
    @Override
    public void setWidth(double width) {
        this.width = width;
        this.height = width; // Force l'égalité
    }
    
    @Override
    public void setHeight(double height) {
        this.width = height; // Force l'égalité
        this.height = height;
    }
}

// Code client qui casse
public class RectangleTest {
    public void testRectangle(Rectangle rectangle) {
        rectangle.setWidth(5);
        rectangle.setHeight(4);
        
        // Attend 20, mais obtient 16 si rectangle est un Square!
        double area = rectangle.getArea();
        System.out.println("Area: " + area); // 20 pour Rectangle, 16 pour Square
    }
}
```

**Problèmes :**
- `Square` ne peut pas être substitué à `Rectangle`
- Le comportement change selon l'implémentation concrète
- Violation du contrat de la classe mère

### ✅ Bon exemple : Respect du LSP

```java
// 1. Classe de base abstraite
public abstract class Shape {
    public abstract double getArea();
    public abstract double getPerimeter();
}

// 2. Rectangle indépendant
public class Rectangle extends Shape {
    protected double width;
    protected double height;
    
    public Rectangle(double width, double height) {
        this.width = width;
        this.height = height;
    }
    
    public void setWidth(double width) {
        this.width = width;
    }
    
    public void setHeight(double height) {
        this.height = height;
    }
    
    @Override
    public double getArea() {
        return width * height;
    }
    
    @Override
    public double getPerimeter() {
        return 2 * (width + height);
    }
    
    public double getWidth() { return width; }
    public double getHeight() { return height; }
}

// 3. Carré indépendant
public class Square extends Shape {
    private double side;
    
    public Square(double side) {
        this.side = side;
    }
    
    public void setSide(double side) {
        this.side = side;
    }
    
    @Override
    public double getArea() {
        return side * side;
    }
    
    @Override
    public double getPerimeter() {
        return 4 * side;
    }
    
    public double getSide() { return side; }
}

// 4. Code client qui fonctionne avec tous
public class ShapeCalculator {
    public double calculateTotalArea(List<Shape> shapes) {
        return shapes.stream()
                   .mapToDouble(Shape::getArea)
                   .sum();
    }
}
```

## Autres exemples par domaine

### Gestion d'oiseaux

❌ **Mauvais :**
```java
public class Bird {
    public void fly() {
        System.out.println("Flying");
    }
}

public class Penguin extends Bird {
    @Override
    public void fly() {
        throw new UnsupportedOperationException("Penguins can't fly");
    }
}

// Code client qui casse
public class BirdTest {
    public void makeBirdFly(Bird bird) {
        bird.fly(); // Exception si bird est un Penguin!
    }
}
```

✅ **Bon :**
```java
// 1. Interface pour les capacités
public interface FlyingBird {
    void fly();
}

public interface SwimmingBird {
    void swim();
}

// 2. Implémentations appropriées
public class Eagle implements FlyingBird {
    @Override
    public void fly() {
        System.out.println("Eagle flying high");
    }
}

public class Penguin implements SwimmingBird {
    @Override
    public void swim() {
        System.out.println("Penguin swimming");
    }
}

public class Duck implements FlyingBird, SwimmingBird {
    @Override
    public void fly() {
        System.out.println("Duck flying");
    }
    
    @Override
    public void swim() {
        System.out.println("Duck swimming");
    }
}

// 3. Code client sécurisé
public class BirdHandler {
    public void makeBirdFly(FlyingBird bird) {
        bird.fly(); // Garanti de fonctionner
    }
    
    public void makeBirdSwim(SwimmingBird bird) {
        bird.swim(); // Garanti de fonctionner
    }
}
```

### Gestion de véhicules

❌ **Mauvais :**
```java
public class Vehicle {
    public void startEngine() {
        System.out.println("Engine started");
    }
    
    public void drive() {
        System.out.println("Driving");
    }
}

public class Bicycle extends Vehicle {
    @Override
    public void startEngine() {
        throw new UnsupportedOperationException("Bicycle has no engine");
    }
    
    @Override
    public void drive() {
        System.out.println("Pedaling");
    }
}
```

✅ **Bon :**
```java
// 1. Abstractions basées sur les capacités
public abstract class Vehicle {
    public abstract void move();
}

public abstract class MotorizedVehicle extends Vehicle {
    public abstract void startEngine();
    
    @Override
    public void move() {
        startEngine();
        drive();
    }
    
    protected abstract void drive();
}

public abstract class HumanPoweredVehicle extends Vehicle {
    @Override
    public void move() {
        propel();
    }
    
    protected abstract void propel();
}

// 2. Implémentations
public class Car extends MotorizedVehicle {
    @Override
    public void startEngine() {
        System.out.println("Car engine started");
    }
    
    @Override
    protected void drive() {
        System.out.println("Car driving");
    }
}

public class Bicycle extends HumanPoweredVehicle {
    @Override
    protected void propel() {
        System.out.println("Pedaling bicycle");
    }
}

public class ElectricScooter extends MotorizedVehicle {
    @Override
    public void startEngine() {
        System.out.println("Electric scooter powered on");
    }
    
    @Override
    protected void drive() {
        System.out.println("Electric scooter moving");
    }
}
```

### Collections et données

❌ **Mauvais :**
```java
public class PersistentStack<T> extends Stack<T> {
    private Database database;
    
    @Override
    public T push(T item) {
        T result = super.push(item);
        database.save(item); // Effet de bord inattendu
        return result;
    }
    
    @Override
    public T pop() {
        T item = super.pop();
        database.delete(item); // Effet de bord inattendu
        return item;
    }
}

// Code client qui s'attend à un comportement standard
public class StackProcessor {
    public void processStack(Stack<String> stack) {
        stack.push("test");
        stack.pop(); // Efface de la BDD si c'est un PersistentStack!
    }
}
```

✅ **Bon :**
```java
// 1. Interface pour les opérations de pile
public interface Stack<T> {
    void push(T item);
    T pop();
    boolean isEmpty();
    int size();
}

// 2. Implémentation standard
public class ArrayStack<T> implements Stack<T> {
    private List<T> items = new ArrayList<>();
    
    @Override
    public void push(T item) {
        items.add(item);
    }
    
    @Override
    public T pop() {
        if (isEmpty()) {
            throw new EmptyStackException();
        }
        return items.remove(items.size() - 1);
    }
    
    @Override
    public boolean isEmpty() {
        return items.isEmpty();
    }
    
    @Override
    public int size() {
        return items.size();
    }
}

// 3. Implémentation persistante (decorator pattern)
public class PersistentStack<T> implements Stack<T> {
    private Stack<T> delegate;
    private Database database;
    
    public PersistentStack(Stack<T> delegate, Database database) {
        this.delegate = delegate;
        this.database = database;
    }
    
    @Override
    public void push(T item) {
        delegate.push(item);
        database.save(item);
    }
    
    @Override
    public T pop() {
        T item = delegate.pop();
        database.delete(item);
        return item;
    }
    
    @Override
    public boolean isEmpty() {
        return delegate.isEmpty();
    }
    
    @Override
    public int size() {
        return delegate.size();
    }
}
```

## Contrats du LSP

### 1. Préconditions
Une classe fille **ne peut pas renforcer** les préconditions de la classe mère.

❌ **Mauvais :**
```java
public class ListProcessor {
    public void process(List<String> list) {
        // Précondition : liste non nulle
        if (list == null) {
            throw new IllegalArgumentException("List cannot be null");
        }
        // Traitement...
    }
}

public class StrictListProcessor extends ListProcessor {
    @Override
    public void process(List<String> list) {
        // Précondition renforcée - VIOLATION LSP
        if (list == null || list.isEmpty()) {
            throw new IllegalArgumentException("List cannot be null or empty");
        }
        super.process(list);
    }
}
```

✅ **Bon :**
```java
public class ListProcessor {
    public void process(List<String> list) {
        if (list == null) {
            throw new IllegalArgumentException("List cannot be null");
        }
        // Traitement...
    }
}

public class EmptyListProcessor extends ListProcessor {
    @Override
    public void process(List<String> list) {
        if (list == null) {
            throw new IllegalArgumentException("List cannot be null");
        }
        
        if (list.isEmpty()) {
            return; // Comportement différent mais précondition respectée
        }
        
        super.process(list);
    }
}
```

### 2. Postconditions
Une classe fille **ne peut pas affaiblir** les postconditions de la classe mère.

❌ **Mauvais :**
```java
public class DataValidator {
    public String validate(String input) {
        // Postcondition : retourne toujours une chaîne non nulle
        if (input == null || input.trim().isEmpty()) {
            return "default";
        }
        return input.trim();
    }
}

public class LazyValidator extends DataValidator {
    @Override
    public String validate(String input) {
        // Postcondition affaiblie - peut retourner null - VIOLATION LSP
        if (input == null) {
            return null;
        }
        return input.trim();
    }
}
```

✅ **Bon :**
```java
public class DataValidator {
    public String validate(String input) {
        if (input == null || input.trim().isEmpty()) {
            return "default";
        }
        return input.trim();
    }
}

public class StrictValidator extends DataValidator {
    @Override
    public String validate(String input) {
        if (input == null || input.trim().isEmpty()) {
            throw new IllegalArgumentException("Input cannot be null or empty");
        }
        return input.trim(); // Postcondition respectée (non nul)
    }
}
```

### 3. Invariants
Une classe fille **doit préserver** les invariants de la classe mère.

❌ **Mauvais :**
```java
public class BankAccount {
    protected double balance;
    
    public BankAccount(double initialBalance) {
        if (initialBalance < 0) {
            throw new IllegalArgumentException("Balance cannot be negative");
        }
        this.balance = initialBalance;
    }
    
    public void withdraw(double amount) {
        if (amount > balance) {
            throw new IllegalArgumentException("Insufficient funds");
        }
        balance -= amount;
    }
    
    public double getBalance() { return balance; }
}

public class OverdraftAccount extends BankAccount {
    private double overdraftLimit;
    
    public OverdraftAccount(double initialBalance, double overdraftLimit) {
        super(initialBalance);
        this.overdraftLimit = overdraftLimit;
    }
    
    @Override
    public void withdraw(double amount) {
        // Violation de l'invariant (balance >= 0) - VIOLATION LSP
        if (amount > balance + overdraftLimit) {
            throw new IllegalArgumentException("Exceeds overdraft limit");
        }
        balance -= amount; // Peut devenir négatif!
    }
}
```

✅ **Bon :**
```java
public abstract class BankAccount {
    protected double balance;
    
    public BankAccount(double initialBalance) {
        if (initialBalance < 0) {
            throw new IllegalArgumentException("Balance cannot be negative");
        }
        this.balance = initialBalance;
    }
    
    public abstract void withdraw(double amount);
    
    public double getBalance() { return balance; }
}

public class RegularAccount extends BankAccount {
    public RegularAccount(double initialBalance) {
        super(initialBalance);
    }
    
    @Override
    public void withdraw(double amount) {
        if (amount > balance) {
            throw new IllegalArgumentException("Insufficient funds");
        }
        balance -= amount;
    }
}

public class OverdraftAccount extends BankAccount {
    private double overdraftLimit;
    private double actualBalance; // Sépare la logique
    
    public OverdraftAccount(double initialBalance, double overdraftLimit) {
        super(0); // Balance virtuelle commence à 0
        this.actualBalance = initialBalance;
        this.overdraftLimit = overdraftLimit;
    }
    
    @Override
    public void withdraw(double amount) {
        if (amount > actualBalance + overdraftLimit) {
            throw new IllegalArgumentException("Exceeds overdraft limit");
        }
        actualBalance -= amount;
        updateVirtualBalance();
    }
    
    @Override
    public double getBalance() {
        return actualBalance >= 0 ? actualBalance : 0;
    }
    
    private void updateVirtualBalance() {
        this.balance = Math.max(0, actualBalance);
    }
}
```

## Comment appliquer le LSP en pratique

### 1. Vérifier la substituabilité
Posez-vous ces questions :
- "Puis-je remplacer cette classe mère par sa fille partout ?"
- "Le code client doit-il connaître le type concret ?"
- "Les invariants sont-ils préservés ?"

### 2. Utiliser le Design by Contract
```java
public interface Contract {
    // Préconditions
    boolean validatePreconditions(Object... params);
    
    // Postconditions
    boolean validatePostconditions(Object result);
    
    // Invariants
    boolean validateInvariants();
}
```

### 3. Préférer la composition à l'héritage
Quand l'héritage viole le LSP, utilisez la composition :
```java
public class Bird {
    private FlyingBehavior flyingBehavior;
    private SwimmingBehavior swimmingBehavior;
    
    public Bird(FlyingBehavior flyingBehavior, SwimmingBehavior swimmingBehavior) {
        this.flyingBehavior = flyingBehavior;
        this.swimmingBehavior = swimmingBehavior;
    }
    
    public void fly() {
        if (flyingBehavior != null) {
            flyingBehavior.fly();
        }
    }
    
    public void swim() {
        if (swimmingBehavior != null) {
            swimmingBehavior.swim();
        }
    }
}
```

### 4. Tests de substitution
```java
@Test
void testRectangleSubstitution() {
    Rectangle rectangle = new Rectangle(5, 4);
    Rectangle squareAsRectangle = new Square(5); // Si Square héritait de Rectangle
    
    testRectangleBehavior(rectangle); // Doit passer
    testRectangleBehavior(squareAsRectangle); // Doit aussi passer si LSP respecté
}

private void testRectangleBehavior(Rectangle rect) {
    rect.setWidth(5);
    rect.setHeight(4);
    assertEquals(20, rect.getArea());
}
```

## Refactorisation étape par étape

### Étape 1 : Identifier la violation
```java
// Code qui casse avec la substitution
public void processPayment(PaymentMethod method) {
    method.process(); // Exception si method = CashPayment!
}
```

### Étape 2 : Analyser les responsabilités
```java
// PaymentMethod a trop de responsabilités
public abstract class PaymentMethod {
    public abstract void process();
    public abstract void refund(); // Pas applicable partout
}
```

### Étape 3 : Séparer les concepts
```java
// Interface de base
public interface PaymentProcessor {
    void process();
}

// Interface pour les remboursements
public interface RefundablePayment {
    void refund();
}
```

### Étape 4 : Implémentations correctes
```java
public class CreditCardPayment implements PaymentProcessor, RefundablePayment {
    @Override
    public void process() { /* traiter paiement carte */ }
    
    @Override
    public void refund() { /* rembourser carte */ }
}

public class CashPayment implements PaymentProcessor {
    @Override
    public void process() { /* traiter paiement espèces */ }
    // Pas de refund - pas de violation LSP
}
```

## Pièges courants à éviter

### 1. Héritage pour la réutilisation
N'héritez pas juste pour réutiliser du code :
```java
// ❌ Mauvais - hérite pour réutiliser
public class UserManager extends ArrayList<User> {
    public void notifyUsers() {
        for (User user : this) {
            user.notify();
        }
    }
}

// ✅ Bon - composition
public class UserManager {
    private List<User> users = new ArrayList<>();
    
    public void addUser(User user) {
        users.add(user);
    }
    
    public void notifyUsers() {
        for (User user : users) {
            user.notify();
        }
    }
}
```

### 2. Violation subtile des invariants
```java
// ❌ Invariant de taille violé
public class BoundedList<T> extends ArrayList<T> {
    private int maxSize;
    
    public BoundedList(int maxSize) {
        this.maxSize = maxSize;
    }
    
    @Override
    public boolean add(T item) {
        if (size() >= maxSize) {
            return false; // ArrayList.add() retourne toujours true
        }
        return super.add(item);
    }
}
```

### 3. Changement de comportement inattendu
```java
// ❌ Comportement différent selon le type
public class CachedRepository<T> implements Repository<T> {
    private Repository<T> delegate;
    private Map<Long, T> cache = new HashMap<>();
    
    @Override
    public T findById(Long id) {
        return cache.computeIfAbsent(id, delegate::findById);
        // Cache peut retourner des données périmées
    }
}
```

## Avantages concrets

### Fiabilité du polymorphisme
```java
// ✅ Confiance dans la substitution
List<Shape> shapes = Arrays.asList(
    new Rectangle(5, 4),
    new Square(3),
    new Circle(2)
);

for (Shape shape : shapes) {
    System.out.println(shape.getArea()); // Fonctionne pour tous
}
```

### Tests robustes
```java
// ✅ Tests avec mocks fiables
@Test
void testShapeProcessor() {
    Shape mockShape = mock(Shape.class);
    when(mockShape.getArea()).thenReturn(10.0);
    
    ShapeProcessor processor = new ShapeProcessor();
    double result = processor.calculateArea(mockShape);
    
    assertEquals(10.0, result); // Prévisible et fiable
}
```

### Maintenance facilitée
```java
// ✅ Ajout de nouvelles implémentations sans risque
public class Triangle implements Shape {
    @Override
    public double getArea() {
        // Implémentation respectant le contrat
        return 0.5 * base * height;
    }
}
```

## Checklist LSP

Pour chaque relation d'héritage, demandez-vous :

- [ ] La classe fille peut-elle remplacer la mère partout ?
- [ ] Les préconditions sont-elles respectées (pas plus strictes) ?
- [ ] Les postconditions sont-elles respectées (pas plus faibles) ?
- [ ] Les invariants sont-ils préservés ?
- [ ] Le code client doit-il vérifier le type concret ?
- [ ] Les exceptions sont-elles cohérentes entre mère et fille ?
- [ ] Le comportement est-il prévisible et cohérent ?

## Résumé

Le LSP est fondamental pour un polymorphisme fiable. En le respectant, vous obtenez :

- **Substituabilité garantie** : Code client fonctionne avec toutes les implémentations
- **Polymorphisme sécurisé** : Pas de surprises lors de l'utilisation
- **Tests fiables** : Mocks et stubs prévisibles
- **Architecture cohérente** : Hiérarchies d'héritage significatives

Analysez toujours vos relations d'héritage, testez la substituabilité, et n'hésitez pas à utiliser la composition quand l'héritage n'est pas approprié.