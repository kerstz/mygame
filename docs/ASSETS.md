# Assets photoréalistes (Fab / Megascans)

Le générateur décide **où** placer les choses ; le **réalisme** vient des
assets scannés. Sans eux, le jeu tourne (terrain + blocs de béton pour la
ville) mais n'est pas photoréaliste.

## Où les trouver

- **Fab** (<https://www.fab.com>), filtre *Megascans* et *Free*. Les Megascans
  sont gratuits pour une utilisation dans Unreal Engine (vérifie la licence
  affichée sur chaque fiche : en général *Fab Standard License*, usage UE).
- Dans l'éditeur : fenêtre **Fab** (plugin) → *Add to project*. Si le plugin
  Fab n'est pas disponible dans ton éditeur Linux, télécharge depuis le site au
  format *Unreal Engine* et copie le dossier dans `Stillworld/Content/`.
- Préfère les versions **Nanite** (arbres, rochers, bâtiments). Pour l'herbe
  très dense, les versions LOD classiques peuvent être plus rapides : mesure.

## Liste de courses (mots-clés de recherche)

**Prairie** — herbe haute sauvage (*wild grass*, *meadow grass*, *tall grass*),
herbe courte, épis / graminées en graines (*wheatgrass*, *seed head*, *dry
grass*), rochers de champ (*field rock*, *boulder*), quelques arbres isolés
(*beech*, *oak*), buissons. Textures : sol herbeux, terre boueuse, mousse.

**Ville reprise par la nature** — bâtiments abandonnés ou en ruine (*abandoned
building*, *ruined house*, *modular ruins*), voitures rouillées (*car wreck*,
*rusty car*), débris (*rubble*, *debris*, *concrete chunks*), herbe sauvage,
fougères (*fern*), lierre / buissons (*ivy*, *bush*), arbres. Textures :
*cracked asphalt*, *forest floor*, *mud*, *moss*.

## Les brancher

1. **Project Settings › Game › Stillworld** : chaque couche est déjà réglée
   (densité, distance, placement, ombres, collisions). Ajoute simplement les
   meshes dans *Meshes* (plusieurs variantes = plus de naturel).
   - `Buildings` (placement *Lot*) : l'axe X du mesh est aligné sur la rue. Les
     bâtiments trop grands pour une parcelle (≈ 29 m × 37 m) sont ignorés.
   - `Cars` (placement *Road*) : axe X = avant de la voiture.
2. **Textures du sol** : ouvre `MI_Terrain_Meadow` / `MI_Terrain_Reclaimed`
   (`Content/Stillworld/Materials`) et remplace les paramètres `Grass_*`,
   `Dirt_*`, `Asphalt_*`, `Moss_*` (BaseColor, Normal, Roughness). Les textures
   de rugosité doivent être en *Compression = Masks*, sRGB désactivé.
3. Note chaque asset utilisé dans `ASSET_LICENSES.md`.

Les assets Fab sont ignorés par git (licence non redistribuable dans un dépôt
public).

## Sons réalistes

Les 47 sons livrés sont des **placeholders synthétisés** (CC0). Pour un rendu
réaliste, remplace-les par des enregistrements CC0 (Freesound filtré par
licence *Creative Commons 0*, ou les bundles libres de droits *Sonniss GDC*) :
réimporte sur les **mêmes noms** (`/Game/Stillworld/Audio/SFX/Foot_Grass_01`,
…), aucun changement de code n'est nécessaire. Le jeu charge automatiquement
jusqu'à 12 variantes par catégorie (`_01` à `_12`).
