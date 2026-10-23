# STILLWORLD — Cahier des charges (version consolidée)

> Réécriture propre du brief d'origine (vision + plan + contraintes).
>
> **Mise à jour (décisions de l'utilisateur, dans l'ordre) :** moteur **Unreal
> Engine 5** (photoréalisme « bluffant », Lumen/Nanite) au lieu de Godot — le
> prototype Godot est conservé dans `prototype-godot/` ; référence visuelle =
> prairie grise et brumeuse ; menu magnifique et simple mais réglages
> graphiques complets ; **Ultra réellement ultra** (30-60 i/s acceptés) avec
> **ray tracing** et **génération d'images** AMD (FSR) et NVIDIA (DLSS) ;
> passage par **Proton** accepté ; second monde **inspiré de The Last of Us**
> (ville abandonnée reprise par la nature) ; **chaque carte générée
> aléatoirement**, **tous les mondes procéduraux** ; **sons réalistes et
> variés** (pas selon la surface, ambiances), toujours sans musique.
>
> Les sections ci-dessous gardent la vision d'origine ; quand elles parlent de
> Godot, lire « Unreal Engine 5 ».

## 1. Objectif
Jeu d'exploration à la première personne, contemplatif, dans une nature
photoréaliste et infinie. Aucun ennemi, quête, survie, combat, objet, succès ni
progression. On marche, on regarde, on écoute la pluie.

Référence d'ambiance : fidélité environnementale et atmosphère « The Last of Us
Part II » — **sans** aucun asset, niveau ou texture de ce jeu.

## 2. Cible matérielle
- Linux (CachyOS), Ryzen 9 5900X, Radeon RX 6900 XT 16 Go, 32 Go RAM.
- Écran 3440×1440 (21:9), 165 Hz. Objectif ≈ 100 FPS (budget 10 ms/frame) —
  c'est un objectif d'optimisation, pas une garantie.
- Godot 4.x stable (≥ 4.3), Forward+ / Vulkan (Mesa RADV récent recommandé),
  GDScript + shaders spatiaux Godot.

## 3. Rendu & ambiance (priorité n°1)
- Terrain PBR multi-matériaux (herbe, terre, boue, roche, sable, neige, mousse),
  transitions naturelles, variation macro anti-répétition, surfaces sèches/mouillées,
  flaques avec ondulations de pluie.
- Végétation organique instanciée (MultiMesh) : herbe dense en touffes variées,
  fleurs, conifères et feuillus à silhouette crédible, fougères, buissons, rochers,
  troncs tombés ; vent multi-échelle désynchronisé ; densité et LOD selon la distance.
- Ciel : atmosphère physique, nuages volumétriques raymarchés animés (technique
  inspirée de clayjohn/godot-volumetric-cloud-demo, MIT), brouillard et perspective
  aérienne, horizon convaincant (terrain lointain + brume).
- Éclairage : soleil directionnel + ombres PSSM, SSAO, SSR (optionnel), HDR,
  tonemapping filmique, SDFGI optionnel. Pas de faux ray tracing.

## 4. Météo
Pluie fine (particules orientées par le vent, collision sol), sol et feuillage
mouillés, flaques, brume, vent dans l'herbe, nuages évolutifs, intensité réglable.
Système extensible (brouillard, vent sec, ciel clair…). Météo pilotée par le biome.

## 5. Monde procédural infini
Chunks déterministes (seed), génération sur threads de travail, déchargement et
libération des ressources, LOD terrain + jupes anti-fissures, terrain lointain
basse résolution pour l'horizon, biomes multi-échelles (température/humidité)
mélangés géographiquement. Jamais de monde complet en mémoire.

Biomes minimum : **prairie pluvieuse**, **forêt dense envahie de ruines**,
**désert de dunes** avec montagnes lointaines. Lacs dans les creux, neige en altitude.

## 6. Joueur & interface
Observateur invisible, yeux à ~1,65 m, ZQSD/WASD + souris, accélération douce,
marche lente, collisions, suivi du sol, balancement de tête très léger et
réglable, pas de saut/sprint/flou de mouvement. FOV et sensibilité réglables.
Aucun HUD. Échap = menu pause minimal : reprendre, environnement (téléportation
vers un biome), graphismes (Ultra/High/Performance + réglages fins), contrôles,
audio, quitter. Pas de musique ; ambiance pluie/vent synthétisée et discrète.

## 7. Performance
Presets Ultra / High / Performance ; échelle de rendu + FSR 2 ; densités, distances
d'ombre, effets volumétriques, qualité nuages, distance de vue réglables.
Instancing GPU, visibility ranges, matériaux partagés, collisions seulement près
du joueur, budget de finalisation des chunks par frame. Overlay de profilage (F3,
masqué par défaut) et mode benchmark scripté (`-- --benchmark`). Ne jamais
supposer un gain sans le mesurer.

## 8. Assets & licences
Uniquement du contenu redistribuable : procédural original ou CC0 vérifié.
Tenir `ASSET_LICENSES.md` (nom, source, auteur, licence, attribution, restrictions).

## 9. Livraison par étapes
- **A** — tranche verticale jouable (prairie, herbe animée, nuages, soleil, pluie,
  brume, marche, menu, presets).
- **B** — profilage (frame time CPU/GPU, draw calls, mémoire) et optimisation
  fondée sur les mesures.
- **C** — streaming procédural (chargement/déchargement, LOD, pas de couture).
- **D** — biomes supplémentaires (forêt envahie, désert) à partir des mêmes systèmes.
- **E** — validation : ouverture du projet, tests headless, captures, rapport honnête
  (ce qui a été testé réellement, mesures, limites, prochaines étapes).

## 10. Qualité du code
Architecture modulaire (terrain, biomes, végétation, météo, éclairage, streaming,
joueur, UI séparés), algorithmes de rendu commentés, configuration reproductible,
README (version moteur, lancement, contrôles), aucune dépendance superflue.
