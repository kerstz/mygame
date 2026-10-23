# STILLWORLD

Expérience de marche contemplative à la première personne, photoréaliste, sous
**Unreal Engine 5**. Pas de combat, pas de quête, pas de HUD, pas de musique :
seulement l'environnement, la pluie, le vent et tes pas.

Deux mondes **entièrement procéduraux** — chaque partie génère une nouvelle carte
infinie à partir d'une seed aléatoire :

| Monde | Ambiance |
|---|---|
| **Prairie sous la pluie** | herbes hautes, épis, bruine, brume épaisse sans horizon (référence visuelle fournie) |
| **Ville reprise par la nature** | inspirée de l'atmosphère de *The Last of Us* : rues désertes, carcasses de voitures, bâtiments en ruine, végétation qui a tout repris (aucun asset ni contenu du jeu n'est utilisé) |

> ⚠️ **État actuel, honnêtement :** le code C++ et les scripts d'éditeur n'ont
> **pas pu être compilés ni lancés** dans l'environnement où ils ont été écrits
> (pas d'Unreal Engine ni de GPU disponibles). Ils ont été relus en détail par
> trois passes indépendantes contre l'API réelle d'UE 5.5/5.6 (sept erreurs de
> compilation et un bug bloquant du script de matériaux ont été corrigés), mais
> un premier build réserve toujours des surprises : envoie-moi le log, je
> corrige. Aucune mesure de performance n'existe encore (voir
> `docs/PERFORMANCE.md`). Le photoréalisme final dépend des assets
> Megascans/Fab à ajouter localement (`docs/ASSETS.md`).

## Structure

```
Stillworld/                   projet Unreal Engine 5 (C++)
  Source/Stillworld/          code du jeu
    StillworldGenerator       fonctions du monde : relief, routes, parcelles, surfaces (déterministes)
    StillworldWorld           streaming infini des chunks (threads), terrain + végétation + bâtiments
    StillworldWeather         pluie, mouillage, vent, brume qui respire, boucles sonores
    StillworldSoundscape      pas selon la surface + mouillé, sons ponctuels spatialisés
    StillworldCharacter       marcheur invisible, hauteur d'œil 1,65 m, pas de saut/sprint
    StillworldPlayerController  entrées (ZQSD/WASD), menus, F3, benchmark
    SStillworldMenu           écran titre + pause + réglages (Slate, en français)
    StillworldSettings        préréglages, upscalers, génération d'images, ray tracing
  Content/Python/             setup_stillworld.py : crée matériaux, MPC, sons, carte, éclairage
  Tools/                      generate_assets.py + assets CC0 générés (textures pluie, sons)
  Config/                     Lumen, Nanite, VSM, TSR, Vulkan SM6 / DX12 SM6, couches de dispersion
docs/                         cahier des charges, assets Fab, performance
prototype-godot/              premier prototype (Godot 4), conservé pour référence
```

## Installation (CachyOS / Arch)

1. **Unreal Engine 5.6** (5.5+ fonctionne) : build Linux officiel depuis
   <https://www.unrealengine.com/linux> (compte Epic requis), ou paquet AUR
   `unreal-engine-bin`. Mesa/RADV récent recommandé (≥ 25.x).
2. Générer les fichiers projet et compiler :
   ```bash
   cd Stillworld
   "$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh" StillworldEditor Linux Development \
       -Project="$PWD/Stillworld.uproject" -WaitMutex
   "$UE_ROOT/Engine/Binaries/Linux/UnrealEditor" "$PWD/Stillworld.uproject"
   ```
3. Dans l'éditeur : **Tools › Execute Python Script › `Content/Python/setup_stillworld.py`**
   (crée matériaux, sons, carte `L_Stillworld`, éclairage, brouillard, post-process).
4. **Assets photoréalistes** (indispensable pour le rendu) : voir `docs/ASSETS.md`
   — Megascans/Fab gratuits pour UE, à brancher dans *Project Settings › Game › Stillworld*
   (les couches sont déjà configurées, il ne manque que les meshes).
5. Jouer : bouton Play, ou empaqueter (*Platforms › Linux* ou *Windows*).

### Génération d'images (FSR / DLSS) et Proton

- **Ray tracing** : activé dans le projet (`r.RayTracing=True`) ; le préréglage
  **Ultra** utilise Lumen matériel + reflets tracés si le GPU le permet (RDNA2+, RTX).
- **Upscaling / génération d'images** : installe le plugin **AMD FSR** (FSR 3.1/4,
  MIT) et/ou **NVIDIA DLSS + Streamline** dans `Stillworld/Plugins/`. Le jeu les
  détecte automatiquement (noms de cvars dans `Config/DefaultGame.ini
  [Stillworld.Vendor]`) et affiche les options correspondantes.
- Ces plugins ne gèrent la génération d'images qu'en **DirectX 12** : sur Linux,
  empaquette la version **Windows** et lance-la via **Proton** (Steam › « Ajouter
  un jeu non-Steam »), ce qui fonctionne avec RADV (vkd3d-proton). La version
  Linux native (Vulkan) garde TSR/FSR upscaling + ray tracing, sans génération
  d'images.

## Contrôles

ZQSD / WASD / flèches : marcher · souris : regarder · Échap ou Tab : menu ·
F3 : statistiques (développeur). Aucune interface pendant la marche.

## Licences

Code : voir dépôt. Assets livrés ici : originaux CC0 (`ASSET_LICENSES.md`).
Les assets Fab/Megascans ne sont **pas** versionnés (licence non redistribuable).
