# 🧭 Cours complet — nano, l'éditeur de texte en ligne de commande

> Nano est l'éditeur en ligne de commande préinstallé sur la plupart des distributions Linux : plus simple d'accès que vim ou emacs (pas de modes à apprendre), il reste l'outil de référence pour éditer rapidement un fichier de configuration sur un serveur distant en SSH.

---

## 🗺️ Plan du cours

| Partie | Niveau | Contenu |
| --- | --- | --- |
| 1 | 🟢 Fondamentaux | Installation, interface, navigation, édition, sauvegarde, recherche |
| 2 | 🟡 Intermédiaire | Buffers multiples, sélection avancée, indentation, undo/redo, commandes externes |
| 3 | 🔴 Avancé | `.nanorc`, coloration syntaxique custom, raccourcis personnalisés, linters, intégration système |

---

# 🟢 PARTIE 1 — FONDAMENTAUX

## 1. Installation

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install nano

# macOS (la version préinstallée est souvent ancienne)
brew install nano

# Vérifier la version installée
nano --version
```

## 2. Premiers pas

```bash
nano fichier.txt          # ouvrir (ou créer) un fichier
nano +45 fichier.txt      # ouvrir directement à la ligne 45
nano -v fichier.txt       # ouvrir en lecture seule (view mode)
```

### Anatomie de l'interface

```
┌─────────────────────────────────────────────┐
│  GNU nano 7.2          fichier.txt           │  ← barre de titre
├─────────────────────────────────────────────┤
│                                               │
│         (zone d'édition du texte)            │
│                                               │
├─────────────────────────────────────────────┤
│  [ Message de statut ]                       │  ← barre de statut
├─────────────────────────────────────────────┤
│ ^G Aide   ^O Écrire   ^W Chercher  ^X Quitter│  ← barre de raccourcis
│ ^R Insérer ^\ Remplacer ^K Couper  ^U Coller │
└─────────────────────────────────────────────┘
```

### Notation des raccourcis

| Symbole | Signifie |
| --- | --- |
| `^` (ex. `^O`) | Touche **Ctrl** + la lettre |
| `M-` (ex. `M-U`) | Touche **Alt** (ou Échap puis la lettre) + la lettre |

---

## 3. Navigation de base

| Raccourci | Action |
| --- | --- |
| Flèches | Déplacer le curseur |
| `Ctrl+A` | Aller au début de la ligne |
| `Ctrl+E` | Aller à la fin de la ligne |
| `Ctrl+Y` | Page précédente |
| `Ctrl+V` | Page suivante |
| `Ctrl+_` | Aller à une ligne (et colonne) précise |
| `Ctrl+Espace` | Mot suivant |
| `Alt+Espace` | Mot précédent |

---

## 4. Édition de base

| Raccourci | Action |
| --- | --- |
| `Ctrl+K` | Couper la ligne courante (dans le presse-papier interne) |
| `Ctrl+U` | Coller le contenu du presse-papier |
| `Ctrl+6` (ou `Alt+A`) | Démarrer une sélection |
| `Ctrl+J` | Justifier le paragraphe courant |
| `Retour arrière` / `Suppr` | Effacer un caractère |

---

## 5. Sauvegarder et quitter

| Raccourci | Action |
| --- | --- |
| `Ctrl+O` | Écrire (sauvegarder) — validez avec `Entrée` pour garder le nom, ou tapez un nouveau nom pour "Enregistrer sous" |
| `Ctrl+X` | Quitter (propose de sauvegarder s'il y a des modifications non enregistrées) |
| `Ctrl+C` | Afficher la position actuelle du curseur (ligne / colonne / %) |

---

## 6. Recherche et remplacement

| Raccourci | Action |
| --- | --- |
| `Ctrl+W` | Rechercher |
| `Ctrl+\` | Rechercher-remplacer |

Dans la barre de recherche, des options apparaissent en bas :

| Toggle | Effet |
| --- | --- |
| `Alt+C` | Recherche sensible à la casse |
| `Alt+R` | Active les expressions régulières |
| `Alt+B` | Recherche vers l'arrière |

---

## 📋 Récapitulatif — raccourcis essentiels

```
^G Aide        ^O Sauver       ^X Quitter      ^W Chercher
^K Couper      ^U Coller       ^\ Remplacer    ^C Position
^A Début ligne ^E Fin ligne    ^_ Aller ligne  ^6 Marquer sélection
```

---

# 🟡 PARTIE 2 — INTERMÉDIAIRE

## 7. Buffers multiples (éditer plusieurs fichiers à la fois)

```bash
nano fichier1.txt fichier2.txt   # ouvre les deux dans des buffers séparés
```

| Raccourci | Action |
| --- | --- |
| `Ctrl+R` | Insérer un fichier (dans un nouveau buffer si `set multibuffer` est actif) |
| `Alt+<` | Buffer précédent |
| `Alt+>` | Buffer suivant |
| `Ctrl+X` | Fermer le buffer courant (quitte nano seulement si c'est le dernier) |

## 8. Sélection et presse-papier avancés

- `Ctrl+6` puis flèches : étendre une sélection sur plusieurs lignes
- `Ctrl+K` répété plusieurs fois : coupe ligne par ligne, en cumulant dans le même presse-papier
- `Ctrl+U` : colle tout le contenu cumulé d'un coup
- `Alt+6` : copier la sélection **sans** la couper

## 9. Numéros de ligne et affichage

```bash
nano -l fichier.txt        # active les numéros de ligne pour cette session
nano -c fichier.txt        # affiche en permanence la position du curseur
```

## 10. Indentation et tabulations

```bash
nano -i fichier.txt        # auto-indentation
nano -T 4 fichier.txt      # taille de tabulation = 4
nano -E fichier.txt        # convertit les tabulations en espaces
```

| Raccourci | Action |
| --- | --- |
| `Alt+}` | Indenter la sélection |
| `Alt+{` | Désindenter la sélection |

## 11. Annuler / Rétablir

| Raccourci | Action |
| --- | --- |
| `Alt+U` | Annuler (Undo) |
| `Alt+E` | Rétablir (Redo) |

## 12. Exécuter une commande externe

`Ctrl+T` ouvre une invite pour exécuter une commande shell et **insérer sa sortie** directement dans le fichier — pratique pour insérer la date, le résultat d'un script, ou lancer un correcteur orthographique (`spell`) si configuré.

---

# 🔴 PARTIE 3 — AVANCÉ

## 13. Le fichier de configuration `~/.nanorc`

- Configuration système : `/etc/nanorc`
- Configuration utilisateur : `~/.nanorc`
- Charger une config personnalisée ponctuelle : `nano --rcfile monconfig.nanorc fichier.txt`

### Exemple de `~/.nanorc` commenté

```ini
set linenumbers        # afficher les numéros de ligne
set mouse               # activer le support de la souris
set autoindent          # conserver l'indentation de la ligne précédente
set tabstospaces        # convertir les tabulations en espaces
set tabsize 4
set softwrap            # retour à la ligne visuel sans couper les mots
set constantshow        # toujours afficher la position du curseur
set smoothscroll        # défilement ligne par ligne plus fluide

include "/usr/share/nano/*.nanorc"   # charger toutes les colorations syntaxiques fournies
```

## 14. Coloration syntaxique personnalisée

Nano fournit des définitions de syntaxe prêtes à l'emploi dans `/usr/share/nano/` (Python, YAML, Docker, etc.). Vous pouvez écrire la vôtre :

```ini
# ~/.nano/monlangage.nanorc
syntax "monlangage" "\.mlg$"
color green "\<(si|sinon|pour|tantque)\>"
color red "\".*\""
color brightblue "#.*$"
```

Puis l'inclure dans `~/.nanorc` :

```ini
include "~/.nano/monlangage.nanorc"
```

## 15. Raccourcis clavier personnalisés

Syntaxe : `bind <touche> <fonction> <menu>`

```ini
# ~/.nanorc
bind ^S writeout main   # Ctrl+S pour sauvegarder (plus intuitif que Ctrl+O)
bind ^Q exit main       # Ctrl+Q pour quitter
```

## 16. Linter et formateur intégrés

Dans un fichier de syntaxe, on peut associer un linter et un formateur à un type de fichier :

```ini
syntax "python" "\.py$"
linter pylint
formatter black
```

`Ctrl+T` déclenche alors le linter configuré ; les erreurs deviennent navigables directement dans nano.

## 17. Nano en environnement serveur / SSH

- Nano reste le choix par défaut sur de nombreux serveurs minimalistes : pas de mode à retenir, sauvegarde explicite (`Ctrl+O`), sortie sans risque de modification accidentelle
- Idéal pour éditer rapidement des fichiers sensibles en production (`/etc/nginx/nginx.conf`, un `docker-compose.yml`, un fichier `.env`)
- `sudo -e fichier` ouvre le fichier avec l'éditeur défini par `$EDITOR` (souvent nano par défaut sur Debian/Ubuntu), en gérant proprement les permissions

## 18. Configurer nano comme éditeur par défaut du système

```bash
# Dans ~/.bashrc ou ~/.zshrc, pour le rendre permanent
export EDITOR=nano
export VISUAL=nano

# Debian/Ubuntu : choisir l'éditeur système par défaut
sudo update-alternatives --config editor

# Git : utiliser nano comme éditeur de commit par défaut
git config --global core.editor "nano"
```

---

## 📖 Glossaire

| Terme | Définition |
| --- | --- |
| **Buffer** | Un fichier ouvert en mémoire dans nano ; on peut en avoir plusieurs simultanément |
| **Presse-papier interne** | Zone où `Ctrl+K` stocke le texte coupé, récupérable avec `Ctrl+U` |
| **nanorc** | Fichier de configuration de nano (syntaxe, options, raccourcis) |
| **Linter** | Outil qui analyse le code pour détecter des erreurs, intégrable via `Ctrl+T` |
| **Softwrap** | Retour à la ligne visuel qui ne coupe pas les mots au milieu |

---

## 🧪 Exercice pratique complet

- [ ] Ouvrir un `docker-compose.yml`, ajouter une ligne, sauvegarder avec `Ctrl+O` puis quitter avec `Ctrl+X`
- [ ] Dans un fichier `.env`, remplacer une variable en utilisant la recherche-remplacement avec expressions régulières (`Ctrl+\`, puis `Alt+R`)
- [ ] Créer un `~/.nanorc` avec numéros de ligne, souris, auto-indentation et tabulations en espaces
- [ ] Ouvrir 3 fichiers en buffers multiples et naviguer entre eux avec `Alt+<` / `Alt+>`
- [ ] Ajouter un raccourci personnalisé (`bind`) dans `~/.nanorc`
- [ ] Configurer nano comme éditeur par défaut de Git

---

## ✅ Checklist finale

- [ ] Navigation, édition, sauvegarde et recherche maîtrisées sans hésitation
- [ ] Capable de gérer plusieurs buffers et une sélection multi-lignes
- [ ] `~/.nanorc` personnalisé et fonctionnel
- [ ] Coloration syntaxique et/ou raccourcis personnalisés en place
- [ ] Nano configuré comme éditeur par défaut du système et de Git

---

*Fin du cours. Dites-moi si vous voulez approfondir un point (par exemple l'écriture de syntaxes de coloration complexes, ou l'usage de nano dans un script/automatisation).*