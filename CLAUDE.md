# STILLWORLD — repères pour Claude Code (lire en entier, c'est court)

Jeu de marche contemplative photoréaliste, **Unreal Engine 5.5+ C++**. Pas de HUD,
pas de musique, pas de gameplay : l'environnement est le jeu. Deux mondes
procéduraux (prairie brumeuse, ville reprise par la nature), seed aléatoire.

## Où est quoi
- `Stillworld/Source/Stillworld/` : tout le code (un fichier = un système, voir README).
- `Stillworld/Content/Python/setup_stillworld.py` : crée matériaux/sons/carte dans l'éditeur.
- `Stillworld/Config/DefaultGame.ini` : couches de végétation (`[/Script/Stillworld.StillworldAssetSettings]`).
- `docs/` : ASSETS.md (Fab), PERFORMANCE.md (benchmark), PROMPT.md (cahier des charges).
- `prototype-godot/` : ancien prototype, **ne pas y toucher**.

## Build (Linux)
```
cd Stillworld
$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh StillworldEditor Linux Development -Project="$PWD/Stillworld.uproject" -WaitMutex
```
Le log complet est bruyant : ne lire que les lignes `error:` (`grep -n "error:" build.log | head -40`).

## Règles de travail (économie de tokens)
- Réponses courtes, pas de récapitulatif de ce qui vient d'être fait, pas de plan avant d'agir pour une petite tâche.
- Ne jamais `cat` un fichier entier de > 200 lignes : `grep -n` puis lire la plage utile.
- Ne jamais lire `Stillworld/Tools/generated/`, `Saved/`, `Intermediate/`, `Binaries/`, `DerivedDataCache/`.
- Un commit par correction vérifiée, message d'une ligne.
- Vérifier avant d'affirmer : si ça n'a pas été compilé/lancé, le dire.
- Les sous-agents `builder` (Haiku) et `fixer` (Sonnet) existent dans `.claude/agents/` : les utiliser pour compiler et corriger ; garder Opus pour l'architecture et les décisions de rendu.

## Conventions C++
- Style Unreal (PascalCase, `b` pour les bool, `TObjectPtr`), pas de `std::`.
- Helpers partagés dans `Private/StillworldMath.h` (module en unity build : pas de doublons dans les namespaces anonymes).
- Jamais de UObject touché depuis un thread de travail (`BuildChunk` n'utilise que des copies).
