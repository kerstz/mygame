# Reprendre STILLWORLD sur ton PC avec Claude Code (en économisant les tokens)

## 1. Récupérer le projet
```bash
git clone <url-du-dépôt> mygame && cd mygame
git checkout claude/great-clarke-4b4h6q
```
Installe UE 5.6 (compte Epic, build Linux) et exporte `UE_ROOT` dans ton shell :
```bash
echo 'export UE_ROOT=$HOME/UnrealEngine-5.6' >> ~/.bashrc   # adapte le chemin
```

## 2. Lancer Claude Code et le bon modèle
```bash
cd mygame
claude --model opus        # Opus 5.5 réfléchit et pilote
```
Dans la session :
- `/caveman` (plugin « Caveman Mode: Short Answers ») — réponses courtes, pas de blabla : à activer en premier.
- `/model` pour vérifier, `/cost` pour suivre la dépense, `/compact` dès que le contexte dépasse ~60 % (ou `/clear` entre deux tâches sans rapport).

## 3. Qui fait quoi (Opus pense, les petits exécutent)
Le dépôt contient déjà trois sous-agents dans `.claude/agents/` :

| Agent | Modèle | Rôle |
|---|---|---|
| `builder` | Haiku | compile et ne renvoie que `fichier:ligne:erreur` |
| `fixer` | Sonnet | applique les corrections minimales, relance `builder` (3 boucles max) |
| `runner` | Haiku | lance le script d'éditeur / le benchmark et filtre le log |

Opus (la session principale) ne lit jamais un log de build : il reçoit 40 lignes
d'erreurs, décide, délègue. Les décisions d'architecture et de rendu restent à Opus.

Prompts types (copie-colle) :
```
Lance l'agent builder, puis donne les erreurs à l'agent fixer. Ne lis pas le log toi-même.
```
```
Lance l'agent runner pour setup_stillworld.py et rapporte seulement les sections en échec.
```
```
Planifie (sans coder) : <sujet>. 10 lignes max, puis délègue l'implémentation à un agent sonnet.
```
Pour une tâche mécanique isolée : `claude --model sonnet` suffit (3-5× moins cher).

## 4. Boucle de reprise conseillée
1. `builder` → `fixer` jusqu'à **BUILD OK** (première fois : attends-toi à quelques erreurs ; le code n'a jamais été compilé).
2. Ouvre l'éditeur, exécute `Content/Python/setup_stillworld.py` (ou via `runner`). Regarde le résumé par section en fin de log.
3. Project Settings › Game › Stillworld : ajoute les meshes Fab/Megascans (`docs/ASSETS.md`).
4. Play. Puis `runner` benchmark par préréglage, et ajuste `DefaultGame.ini` sur des chiffres.

## 5. Règles qui font vraiment économiser
- `CLAUDE.md` à la racine est court et dit où est chaque chose : Claude n'explore pas le dépôt à chaque session.
- Ne jamais coller un log entier dans le chat : `grep -n "error:" | head -40`.
- Une tâche = un prompt précis avec fichier et ligne quand tu les connais.
- `/compact` plutôt que laisser gonfler ; `/clear` avant de changer de sujet.
- Les gros fichiers (`setup_stillworld.py` 800 lignes, `StillworldWorld.cpp` 700 lignes) : demande de lire une plage, pas le fichier.
- Garde les relectures « indépendantes » (second agent) pour les changements à risque uniquement.
