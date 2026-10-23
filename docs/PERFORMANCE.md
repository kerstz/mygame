# Performance

**Aucune mesure n'a encore été faite sur la machine cible** (le projet a été
écrit sans accès à Unreal Engine ni à un GPU). Voici comment mesurer.

## Benchmark intégré

```bash
UnrealEditor Stillworld.uproject -game -benchmark -preset=ultra -world=meadow -ResX=3440 -ResY=1440 -windowed
# ou avec un build empaqueté :
./Stillworld.sh -benchmark -preset=high -world=reclaimed
```

12 s de préchauffage (compilation des shaders/PSO, cache Lumen) puis 30 s de
marche en ligne droite. Résultat dans `Saved/Benchmark/benchmark_<preset>.json` :
FPS moyen, temps de frame moyen et 99e centile, temps GPU moyen.
`-seed=N` rend la carte reproductible pour comparer deux réglages.

En jeu, **F3** affiche `stat fps` + `stat unit` (temps Game / Draw / GPU
séparés), puis `stat gpu` (détail par passe : Lumen, ombres, brouillard,
Nanite…). Pour une trace complète : Unreal Insights (`-trace=default,gpu`) et,
sur AMD, Radeon GPU Profiler.

## Objectifs des préréglages (3440×1440)

| Préréglage | Intention | Cible |
|---|---|---|
| Performance | qualité Élevée moteur, 58 % de résolution interne, Lumen logiciel, génération d'images si dispo | ≥ 100 i/s |
| Élevé | qualité Épique, 72 % | 60-90 i/s |
| Ultra | Cinématique, résolution native, ray tracing matériel + reflets tracés, végétation maximale | 30-60 i/s (assumé) |

Ce sont des intentions, pas des résultats : à valider avec le benchmark.

## Leviers déjà en place

- Terrain : chunks de 64 m générés sur threads, LOD 1/2/4/8 m selon la
  distance, collisions seulement autour du joueur, budget d'upload 3 ms/frame.
- Végétation : un ISM par mesh et par chunk, distances de cull par couche,
  WPO (vent) désactivé au-delà de 60 % de la distance de cull, herbe exclue de
  Lumen et du BVH ray tracing.
- Pluie : deux cylindres translucides autour de la caméra (pas de particules).
- Pas de flou de mouvement ni de profondeur de champ.
