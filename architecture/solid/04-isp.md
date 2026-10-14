# Interface Segregation Principle (ISP)

## Définition

Le **Interface Segregation Principle** (ISP) est le quatrième principe du SOLID. Il stipule que **les clients ne doivent pas être forcés de dépendre d'interfaces qu'ils n'utilisent pas**. En d'autres termes, il est préférable d'avoir plusieurs interfaces petites et spécifiques plutôt qu'une grande interface monolithique.

> "Les clients ne devraient pas être forcés de dépendre d'interfaces qu'ils n'utilisent pas." - Robert C. Martin

## Pourquoi c'est important ?

- **Flexibilité** : Les implémentations ne sont pas forcées d'implémenter des méthodes inutiles
- **Cohésion** : Interfaces regroupent des fonctionnalités logiquement liées
- **Maintenance** : Modifications localisées aux interfaces concernées
- **Testabilité** : Tests plus simples et ciblés

## Comment identifier une violation de l'ISP ?

Signes courants :
- Classes implémentant des interfaces avec des méthodes vides ou lançant des exceptions
- Classes qui n'utilisent qu'une partie des méthodes d'une interface
- Interfaces "fourre-tout" avec des responsabilités variées
- Modifications fréquentes d'interfaces pour ajouter de nouvelles fonctionnalités

## Exemples pratiques

### ❌ Mauvais exemple : Violation de l'ISP

```java
// Interface monolithique - VIOLATION ISP
public interface Worker {
    void work();
    void eat();
    void sleep();
    void attendMeeting();
    void takeBreak();
    void reportProgress();
}

// Implémentations forcées d'implémenter tout
public class Robot implements Worker {
    @Override
    public void work() {
        System.out.println("Robot working");
    }
    
    @Override
    public void eat() {
        // N'a pas besoin de manger - méthode vide
    }
    
    @Override
    public void sleep() {
        // N'a pas besoin de dormir - méthode vide
    }
    
    @Override
    public void attendMeeting() {
        System.out.println("Robot attending meeting");
    }
    
    @Override
    public void takeBreak() {
        // N'a pas besoin de pause - méthode vide
    }
    
    @Override
    public void reportProgress() {
        System.out.println("Robot reporting progress");
    }
}

public class HumanWorker implements Worker {
    @Override
    public void work() {
        System.out.println("Human working");
    }
    
    @Override
    public void eat() {
        System.out.println("Human eating");
    }
    
    @Override
    public void sleep() {
        System.out.println("Human sleeping");
    }
    
    @Override
    public void attendMeeting() {
        System.out.println("Human attending meeting");
    }
    
    @Override
    public void takeBreak() {
        System.out.println("Human taking break");
    }
    
    @Override
    public void reportProgress() {
        System.out.println("Human reporting progress");
    }
}
```

**Problèmes :**
- `Robot` est forcé d'implémenter des méthodes inutiles
- Violation du principe de responsabilité unique
- Interface trop large avec des responsabilités variées

### ✅ Bon exemple : Respect de l'ISP

```java
// 1. Interfaces petites et spécifiques
public interface Workable {
    void work();
}

public interface Eatable {
    void eat();
}

public interface Sleepable {
    void sleep();
}

public interface MeetingAttendee {
    void attendMeeting();
}

public interface BreakTaker {
    void takeBreak();
}

public interface ProgressReporter {
    void reportProgress();
}

// 2. Implémentations ciblées
public class Robot implements Workable, MeetingAttendee, ProgressReporter {
    @Override
    public void work() {
        System.out.println("Robot working");
    }
    
    @Override
    public void attendMeeting() {
        System.out.println("Robot attending meeting");
    }
    
    @Override
    public void reportProgress() {
        System.out.println("Robot reporting progress");
    }
}

public class HumanWorker implements Workable, Eatable, Sleepable, 
                                   MeetingAttendee, BreakTaker, ProgressReporter {
    @Override
    public void work() {
        System.out.println("Human working");
    }
    
    @Override
    public void eat() {
        System.out.println("Human eating");
    }
    
    @Override
    public void sleep() {
        System.out.println("Human sleeping");
    }
    
    @Override
    public void attendMeeting() {
        System.out.println("Human attending meeting");
    }
    
    @Override
    public void takeBreak() {
        System.out.println("Human taking break");
    }
    
    @Override
    public void reportProgress() {
        System.out.println("Human reporting progress");
    }
}

// 3. Robot plus spécialisé
public class SimpleRobot implements Workable {
    @Override
    public void work() {
        System.out.println("Simple robot working");
    }
}
```

## Autres exemples par domaine

### Gestion de documents

❌ **Mauvais :**
```java
public interface DocumentProcessor {
    void read();
    void write();
    void print();
    void scan();
    void fax();
    void email();
    void encrypt();
    void compress();
}

public class TextEditor implements DocumentProcessor {
    @Override
    public void read() { /* lire document */ }
    
    @Override
    public void write() { /* écrire document */ }
    
    @Override
    public void print() { /* imprimer document */ }
    
    @Override
    public void scan() {
        throw new UnsupportedOperationException("Text editor cannot scan");
    }
    
    @Override
    public void fax() {
        throw new UnsupportedOperationException("Text editor cannot fax");
    }
    
    @Override
    public void email() { /* envoyer par email */ }
    
    @Override
    public void encrypt() { /* chiffrer document */ }
    
    @Override
    public void compress() { /* compresser document */ }
}
```

✅ **Bon :**
```java
// Interfaces spécifiques par fonctionnalité
public interface Readable {
    void read();
}

public interface Writable {
    void write();
}

public interface Printable {
    void print();
}

public interface Scannable {
    void scan();
}

public interface Faxable {
    void fax();
}

public interface Emailable {
    void email();
}

public interface Encryptable {
    void encrypt();
}

public interface Compressible {
    void compress();
}

// Implémentations ciblées
public class TextEditor implements Readable, Writable, Printable, Emailable, Encryptable, Compressible {
    @Override
    public void read() { /* lire document */ }
    
    @Override
    public void write() { /* écrire document */ }
    
    @Override
    public void print() { /* imprimer document */ }
    
    @Override
    public void email() { /* envoyer par email */ }
    
    @Override
    public void encrypt() { /* chiffrer document */ }
    
    @Override
    public void compress() { /* compresser document */ }
}

public class MultiFunctionPrinter implements Readable, Writable, Printable, Scannable, Faxable, Emailable {
    @Override
    public void read() { /* lire depuis scanner */ }
    
    @Override
    public void write() { /* écrire sur imprimante */ }
    
    @Override
    public void print() { /* imprimer */ }
    
    @Override
    public void scan() { /* scanner */ }
    
    @Override
    public void fax() { /* faxer */ }
    
    @Override
    public void email() { /* envoyer par email */ }
}

public class SimpleReader implements Readable {
    @Override
    public void read() { /* lire uniquement */ }
}
```

### Services web

❌ **Mauvais :**
```java
public interface UserService {
    User createUser(User user);
    User getUserById(Long id);
    List<User> getAllUsers();
    void updateUser(User user);
    void deleteUser(Long id);
    boolean authenticate(String username, String password);
    void resetPassword(String email);
    void changePassword(Long userId, String oldPassword, String newPassword);
    void sendWelcomeEmail(User user);
    void sendPasswordResetEmail(String email);
    void logActivity(User user, String activity);
    List<User> searchUsers(String query);
    void banUser(Long userId);
    void unbanUser(Long userId);
}

public class ReadOnlyUserService implements UserService {
    @Override
    public User createUser(User user) {
        throw new UnsupportedOperationException("Read-only service");
    }
    
    @Override
    public User getUserById(Long id) {
        // Implémentation
        return null;
    }
    
    @Override
    public List<User> getAllUsers() {
        // Implémentation
        return null;
    }
    
    @Override
    public void updateUser(User user) {
        throw new UnsupportedOperationException("Read-only service");
    }
    
    @Override
    public void deleteUser(Long id) {
        throw new UnsupportedOperationException("Read-only service");
    }
    
    // ... autres méthodes avec des exceptions
}
```

✅ **Bon :**
```java
// Interfaces séparées par responsabilité
public interface UserReader {
    User getUserById(Long id);
    List<User> getAllUsers();
    List<User> searchUsers(String query);
}

public interface UserWriter {
    User createUser(User user);
    void updateUser(User user);
    void deleteUser(Long id);
}

public interface UserAuthenticator {
    boolean authenticate(String username, String password);
    void resetPassword(String email);
    void changePassword(Long userId, String oldPassword, String newPassword);
}

public interface UserNotifier {
    void sendWelcomeEmail(User user);
    void sendPasswordResetEmail(String email);
}

public interface UserActivityLogger {
    void logActivity(User user, String activity);
}

public interface UserModerator {
    void banUser(Long userId);
    void unbanUser(Long userId);
}

// Implémentations spécialisées
public class ReadOnlyUserService implements UserReader, UserActivityLogger {
    @Override
    public User getUserById(Long id) {
        // Implémentation
        return null;
    }
    
    @Override
    public List<User> getAllUsers() {
        // Implémentation
        return null;
    }
    
    @Override
    public List<User> searchUsers(String query) {
        // Implémentation
        return null;
    }
    
    @Override
    public void logActivity(User user, String activity) {
        // Logger l'activité
    }
}

public class FullUserService implements UserReader, UserWriter, 
                                     UserAuthenticator, UserNotifier, 
                                     UserActivityLogger, UserModerator {
    // Implémentation complète de toutes les méthodes
}

public class AuthenticationService implements UserAuthenticator {
    @Override
    public boolean authenticate(String username, String password) {
        // Logique d'authentification
        return false;
    }
    
    @Override
    public void resetPassword(String email) {
        // Logique de reset
    }
    
    @Override
    public void changePassword(Long userId, String oldPassword, String newPassword) {
        // Logique de changement
    }
}
```

### Système de plugins

❌ **Mauvais :**
```java
public interface Plugin {
    void initialize();
    void start();
    void stop();
    void configure(Properties config);
    void handleEvent(Event event);
    void registerListeners();
    void unregisterListeners();
    void cleanup();
    void getStatus();
    void performMaintenance();
}

public class SimplePlugin implements Plugin {
    @Override
    public void initialize() {
        // Initialisation
    }
    
    @Override
    public void start() {
        // Démarrage
    }
    
    @Override
    public void stop() {
        // Arrêt
    }
    
    @Override
    public void configure(Properties config) {
        // Configuration
    }
    
    @Override
    public void handleEvent(Event event) {
        throw new UnsupportedOperationException("Simple plugin doesn't handle events");
    }
    
    @Override
    public void registerListeners() {
        throw new UnsupportedOperationException("Simple plugin has no listeners");
    }
    
    @Override
    public void unregisterListeners() {
        throw new UnsupportedOperationException("Simple plugin has no listeners");
    }
    
    @Override
    public void cleanup() {
        // Nettoyage
    }
    
    @Override
    public void getStatus() {
        throw new UnsupportedOperationException("Simple plugin has no status");
    }
    
    @Override
    public void performMaintenance() {
        throw new UnsupportedOperationException("Simple plugin needs no maintenance");
    }
}
```

✅ **Bon :**
```java
// Interfaces de base
public interface LifecyclePlugin {
    void initialize();
    void start();
    void stop();
    void cleanup();
}

public interface ConfigurablePlugin {
    void configure(Properties config);
}

public interface EventHandlingPlugin {
    void handleEvent(Event event);
    void registerListeners();
    void unregisterListeners();
}

public interface StatusReportingPlugin {
    String getStatus();
}

public interface MaintenancePlugin {
    void performMaintenance();
}

// Implémentations spécialisées
public class SimplePlugin implements LifecyclePlugin, ConfigurablePlugin {
    @Override
    public void initialize() {
        System.out.println("Simple plugin initialized");
    }
    
    @Override
    public void start() {
        System.out.println("Simple plugin started");
    }
    
    @Override
    public void stop() {
        System.out.println("Simple plugin stopped");
    }
    
    @Override
    public void cleanup() {
        System.out.println("Simple plugin cleaned up");
    }
    
    @Override
    public void configure(Properties config) {
        System.out.println("Simple plugin configured");
    }
}

public class AdvancedPlugin implements LifecyclePlugin, ConfigurablePlugin, 
                                      EventHandlingPlugin, StatusReportingPlugin, 
                                      MaintenancePlugin {
    @Override
    public void initialize() {
        System.out.println("Advanced plugin initialized");
    }
    
    @Override
    public void start() {
        System.out.println("Advanced plugin started");
    }
    
    @Override
    public void stop() {
        System.out.println("Advanced plugin stopped");
    }
    
    @Override
    public void cleanup() {
        System.out.println("Advanced plugin cleaned up");
    }
    
    @Override
    public void configure(Properties config) {
        System.out.println("Advanced plugin configured");
    }
    
    @Override
    public void handleEvent(Event event) {
        System.out.println("Advanced plugin handling event");
    }
    
    @Override
    public void registerListeners() {
        System.out.println("Advanced plugin registering listeners");
    }
    
    @Override
    public void unregisterListeners() {
        System.out.println("Advanced plugin unregistering listeners");
    }
    
    @Override
    public String getStatus() {
        return "Advanced plugin is running";
    }
    
    @Override
    public void performMaintenance() {
        System.out.println("Advanced plugin performing maintenance");
    }
}
```

## Comment appliquer l'ISP en pratique

### 1. Identifier les responsabilités
Analysez les interfaces existantes pour identifier les groupes de méthodes logiquement liées :

```java
// Interface à analyser
public interface Device {
    void powerOn();
    void powerOff();
    void connectToNetwork();
    void downloadData();
    void uploadData();
    void processCommand(String command);
    void getStatus();
    void updateFirmware();
}

// Analyse des responsabilités :
// - Power management: powerOn(), powerOff()
// - Network operations: connectToNetwork(), downloadData(), uploadData()
// - Command processing: processCommand()
// - Status: getStatus()
// - Maintenance: updateFirmware()
```

### 2. Séparer les interfaces
Créez des interfaces spécifiques pour chaque groupe de responsabilités :

```java
public interface PowerControllable {
    void powerOn();
    void powerOff();
}

public interface NetworkCapable {
    void connectToNetwork();
    void downloadData();
    void uploadData();
}

public interface CommandProcessor {
    void processCommand(String command);
}

public interface StatusReporter {
    String getStatus();
}

public interface Updatable {
    void updateFirmware();
}
```

### 3. Combiner les interfaces
Utilisez l'héritage d'interfaces pour créer des combinaisons logiques :

```java
public interface SmartDevice extends PowerControllable, NetworkCapable, 
                                  CommandProcessor, StatusReporter, Updatable {
    // Interface combinée pour les appareils complets
}

public interface BasicDevice extends PowerControllable, StatusReporter {
    // Interface pour les appareils simples
}
```

### 4. Implémentations ciblées
Les classes n'implémentent que ce dont elles ont besoin :

```java
public class SimpleLamp implements PowerControllable, StatusReporter {
    @Override
    public void powerOn() {
        System.out.println("Lamp on");
    }
    
    @Override
    public void powerOff() {
        System.out.println("Lamp off");
    }
    
    @Override
    public String getStatus() {
        return "Lamp is " + (isOn ? "on" : "off");
    }
}

public class SmartSpeaker implements SmartDevice {
    @Override
    public void powerOn() {
        System.out.println("Smart speaker on");
    }
    
    @Override
    public void powerOff() {
        System.out.println("Smart speaker off");
    }
    
    @Override
    public void connectToNetwork() {
        System.out.println("Connecting to Wi-Fi");
    }
    
    @Override
    public void downloadData() {
        System.out.println("Downloading music");
    }
    
    @Override
    public void uploadData() {
        System.out.println("Uploading usage data");
    }
    
    @Override
    public void processCommand(String command) {
        System.out.println("Processing: " + command);
    }
    
    @Override
    public String getStatus() {
        return "Smart speaker is ready";
    }
    
    @Override
    public void updateFirmware() {
        System.out.println("Updating firmware");
    }
}
```

## Patterns qui respectent l'ISP

### 1. Role Interface Pattern
Créez des interfaces basées sur les rôles plutôt que sur les entités :

```java
// Au lieu d'une interface par entité
public interface User {
    void login();
    void postContent();
    void moderateContent();
    void analyzeData();
}

// Créez des interfaces par rôle
public interface Authenticatable {
    void login();
    void logout();
}

public interface ContentCreator {
    void postContent();
    void editContent();
}

public interface Moderator {
    void moderateContent();
    void banUser();
}

public interface Analyst {
    void analyzeData();
    void generateReport();
}
```

### 2. Interface Segregation with Composition
Utilisez la composition pour combiner des comportements :

```java
public class User implements Authenticatable, ContentCreator {
    private Authenticatable authenticator;
    private ContentCreator creator;
    
    public User(Authenticatable authenticator, ContentCreator creator) {
        this.authenticator = authenticator;
        this.creator = creator;
    }
    
    @Override
    public void login() {
        authenticator.login();
    }
    
    @Override
    public void logout() {
        authenticator.logout();
    }
    
    @Override
    public void postContent() {
        creator.postContent();
    }
    
    @Override
    public void editContent() {
        creator.editContent();
    }
}
```

### 3. Marker Interfaces
Utilisez des interfaces marqueurs pour les capacités :

```java
public interface Closable {
    void close();
}

public interface Flushable {
    void flush();
}

public interface Resettable {
    void reset();
}

public class DatabaseConnection implements Closable, Flushable, Resettable {
    @Override
    public void close() {
        // Fermer la connexion
    }
    
    @Override
    public void flush() {
        // Vider le cache
    }
    
    @Override
    public void reset() {
        // Réinitialiser la connexion
    }
}
```

## Refactorisation étape par étape

### Étape 1 : Identifier l'interface problématique
```java
public interface MultimediaPlayer {
    void playAudio();
    void playVideo();
    void displayImage();
    void showSubtitle();
    void adjustBrightness();
    void adjustVolume();
    void connectToInternet();
    void streamContent();
}
```

### Étape 2 : Analyser les implémentations
```java
public class AudioPlayer implements MultimediaPlayer {
    @Override
    public void playAudio() { /* OK */ }
    
    @Override
    public void playVideo() {
        throw new UnsupportedOperationException("Audio player cannot play video");
    }
    
    @Override
    public void displayImage() {
        throw new UnsupportedOperationException("Audio player cannot display images");
    }
    
    // ... autres méthodes inutiles
}
```

### Étape 3 : Séparer les responsabilités
```java
public interface AudioPlayable {
    void playAudio();
    void adjustVolume();
}

public interface VideoPlayable {
    void playVideo();
    void showSubtitle();
}

public interface ImageDisplayable {
    void displayImage();
    void adjustBrightness();
}

public interface Streamable {
    void connectToInternet();
    void streamContent();
}
```

### Étape 4 : Refactoriser les implémentations
```java
public class AudioPlayer implements AudioPlayable {
    @Override
    public void playAudio() {
        System.out.println("Playing audio");
    }
    
    @Override
    public void adjustVolume() {
        System.out.println("Adjusting volume");
    }
}

public class VideoPlayer implements AudioPlayable, VideoPlayable {
    @Override
    public void playAudio() {
        System.out.println("Playing video audio");
    }
    
    @Override
    public void adjustVolume() {
        System.out.println("Adjusting video volume");
    }
    
    @Override
    public void playVideo() {
        System.out.println("Playing video");
    }
    
    @Override
    public void showSubtitle() {
        System.out.println("Showing subtitles");
    }
}

public class SmartTV implements VideoPlayable, ImageDisplayable, Streamable {
    @Override
    public void playVideo() {
        System.out.println("TV playing video");
    }
    
    @Override
    public void showSubtitle() {
        System.out.println("TV showing subtitles");
    }
    
    @Override
    public void displayImage() {
        System.out.println("TV displaying image");
    }
    
    @Override
    public void adjustBrightness() {
        System.out.println("TV adjusting brightness");
    }
    
    @Override
    public void connectToInternet() {
        System.out.println("TV connecting to internet");
    }
    
    @Override
    public void streamContent() {
        System.out.println("TV streaming content");
    }
}
```

## Pièges courants à éviter

### 1. Sur-segmentation
Ne divisez pas trop les interfaces :

```java
// ❌ Trop granulaire
public interface Clickable {
    void onClick();
}

public interface DoubleClickable {
    void onDoubleClick();
}

public interface RightClickable {
    void onRightClick();
}

public interface Hoverable {
    void onHover();
}

// ✅ Équilibré
public interface MouseInteractable {
    void onClick();
    void onDoubleClick();
    void onRightClick();
    void onHover();
}
```

### 2. Interfaces avec une seule méthode (sauf cas spécifiques)
Évitez les interfaces trop petites sauf pour les cas fonctionnels :

```java
// ❌ Inutilement petit
public interface NameProvider {
    String getName();
}

public interface AgeProvider {
    int getAge();
}

// ✅ Cohérent
public interface PersonInfo {
    String getName();
    int getAge();
    String getEmail();
}
```

### 3. Ignorer le contexte métier
Les interfaces doivent refléter le domaine métier :

```java
// ❌ Basé sur l'implémentation
public interface DatabaseAccessible {
    void connect();
    void query();
    void disconnect();
}

// ✅ Basé sur le métier
public interface DataRepository {
    List<User> findActiveUsers();
    void saveUser(User user);
    void deleteUser(Long userId);
}
```

## Avantages concrets

### Code plus maintenable
```java
// ✅ Ajout de nouvelles fonctionnalités sans impact
public interface VoiceControllable {
    void processVoiceCommand(String command);
}

// Les classes existantes ne sont pas affectées
public class SmartTV implements VideoPlayable, ImageDisplayable, Streamable, VoiceControllable {
    // Implémentation existante + nouvelle méthode
}
```

### Tests plus simples
```java
// ✅ Tests ciblés par interface
@Test
void testAudioPlayback() {
    AudioPlayable player = new AudioPlayer();
    player.playAudio();
    // Test uniquement les fonctionnalités audio
}

@Test
void testVideoPlayback() {
    VideoPlayable player = new VideoPlayer();
    player.playVideo();
    // Test uniquement les fonctionnalités vidéo
}
```

### Flexibilité accrue
```java
// ✅ Composition dynamique des capacités
public class DeviceFactory {
    public static Device createBasicDevice() {
        return new BasicDevice(); // Implémente PowerControllable, StatusReporter
    }
    
    public static Device createSmartDevice() {
        return new SmartDevice(); // Implémente toutes les interfaces
    }
    
    public static Device createNetworkOnlyDevice() {
        return new NetworkDevice(); // Implémente NetworkCapable uniquement
    }
}
```

## Checklist ISP

Pour chaque interface, demandez-vous :

- [ ] L'interface a-t-elle une seule responsabilité claire ?
- [ ] Toutes les méthodes sont-elles logiquement liées ?
- [ ] Les implémentations utilisent-elles toutes les méthodes ?
- [ ] Y a-t-il des méthodes vides ou des exceptions dans les implémentations ?
- [ ] L'interface peut-elle être divisée en interfaces plus petites ?
- [ ] Le nom de l'interface reflète-t-il sa responsabilité unique ?
- [ ] Les clients dépendent-ils uniquement des méthodes qu'ils utilisent ?

## Résumé

L'ISP est essentiel pour des interfaces propres et maintenables. En l'appliquant, vous obtenez :

- **Interfaces cohérentes** : Chaque interface a une responsabilité unique
- **Implémentations ciblées** : Pas de méthodes inutiles
- **Flexibilité** : Combinaison modulaire des fonctionnalités
- **Maintenance facilitée** : Modifications localisées

Analysez vos interfaces, séparez les responsabilités, et créez des combinaisons logiques pour une architecture flexible et évolutive.