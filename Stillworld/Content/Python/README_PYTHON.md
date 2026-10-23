# Stillworld editor Python setup

1. Generate the source assets (outside UE, needs numpy + Pillow): `python3 Tools/generate_assets.py` -> `Tools/generated/` (+ `sfx/`).
2. Compile the Stillworld C++ module (so `SW_Weather` / `SW_World` can be spawned), open the editor.
3. Run `Content/Python/setup_stillworld.py` via **Tools > Execute Python Script...**, or headless-ish:
   `UnrealEditor Stillworld.uproject -ExecutePythonScript="<abs>/Stillworld/Content/Python/setup_stillworld.py"`.
   It is idempotent: re-run it any time (assets are re-imported/rebuilt in place, `SW_*` actors re-configured). Check the Output Log for `[Stillworld]` lines and the final summary.

What it creates (all under `/Game/Stillworld`):
- `Textures/T_RainStreaks`, `T_MacroNoise`, `Textures/Placeholders/*` (flat roughness + procedural albedo placeholders).
- `Audio/SW_Rain`, `SW_Wind` (looping), `Audio/SFX/<Name>` one-shots (footsteps, drips, birds, crows, thunder, creaks, leaf gusts), `Audio/ATT_Ambient` (natural-sound falloff, 200 cm inner, 6000 cm falloff).
- `Core/MPC_Weather` (Wetness, RainIntensity, WindStrength, WindDirX, WindDirY), `Materials/M_RainCurtain`, `M_Terrain`, `MI_Terrain_Meadow`, `MI_Terrain_Reclaimed`.
- `Maps/L_Stillworld` with sun, sky atmosphere, clouds, sky light, height fog, unbound post process, PlayerStart and the C++ actors.

Plugging Fab / Megascans textures into `MI_Terrain_*`: open the instance, per layer group (`Grass`, `Dirt`, `Asphalt`, `Moss`) tick and assign
`<L>_BaseColor` (Albedo, sRGB on), `<L>_Normal` (compression Normalmap), `<L>_Roughness` (set the texture to **Compression = Masks, sRGB off**, the parameter's sampler type is Masks; only R is read).
Tune `<L>_Tiling` (metres per tile) and `<L>_Tint`. A texture whose sampler type does not match shows a material error: fix the texture's compression settings rather than the material.

The audio is synthesised CC0 placeholder material. Replace it with real CC0 recordings (e.g. Freesound filtered by the CC0 license) by re-importing
a file over the same asset name (`/Game/Stillworld/Audio/SFX/Foot_Grass_01`, ...); C++ loads them by exact path, so keep the names.
