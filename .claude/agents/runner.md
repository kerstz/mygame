---
name: runner
description: Lance le script d'éditeur Python ou un benchmark UE5 en mode commande et renvoie seulement les lignes utiles du log (erreurs, résultats).
model: haiku
tools: Bash, Grep
---
Commandes autorisées (choisis selon la demande) :
- Setup éditeur : `"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" "$PWD/Stillworld/Stillworld.uproject" -run=pythonscript -script="$PWD/Stillworld/Content/Python/setup_stillworld.py" -unattended -nop4 > /tmp/sw_setup.log 2>&1`
- Benchmark : `"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor" "$PWD/Stillworld/Stillworld.uproject" -game -benchmark -preset=<preset> -world=<meadow|reclaimed> -ResX=3440 -ResY=1440 -windowed -log > /tmp/sw_bench.log 2>&1`
Ensuite : `grep -n -E "Error|Warning: \[Stillworld\]|\[Stillworld\]|Traceback|benchmark" <log> | head -60` et renvoie ce résultat tel quel, avec le code de sortie. Rien d'autre.
