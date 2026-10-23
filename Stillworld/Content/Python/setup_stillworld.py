"""
STILLWORLD editor setup script (idempotent).

Run inside the Unreal Editor:
  * Tools > Execute Python Script... > Content/Python/setup_stillworld.py
  * or: UnrealEditor Stillworld.uproject -ExecutePythonScript="<abs path>/setup_stillworld.py"

Prerequisite: run `python3 Tools/generate_assets.py` first so that
Tools/generated/ contains the PNG/WAV sources.

Creates / refreshes:
  /Game/Stillworld/Textures/T_RainStreaks, T_MacroNoise, Placeholders/*
  /Game/Stillworld/Audio/SW_Rain, SW_Wind (looping), SFX/<Name> (one-shots), ATT_Ambient
  /Game/Stillworld/Core/MPC_Weather
  /Game/Stillworld/Materials/M_RainCurtain, M_Terrain, MI_Terrain_Meadow, MI_Terrain_Reclaimed
  /Game/Stillworld/Maps/L_Stillworld (+ SW_* actors)

Each section is wrapped in try/except: a failure is logged and the remaining
sections still run. Re-running is safe: assets are re-imported / rebuilt in
place, actors are found by their SW_ label and re-configured.
"""

import os
import traceback

import unreal

# ---------------------------------------------------------------------------
# Paths / tunables
# ---------------------------------------------------------------------------

ROOT = "/Game/Stillworld"
TEX_DIR = ROOT + "/Textures"
PLACEHOLDER_DIR = TEX_DIR + "/Placeholders"
AUDIO_DIR = ROOT + "/Audio"
SFX_DIR = AUDIO_DIR + "/SFX"
CORE_DIR = ROOT + "/Core"
MAT_DIR = ROOT + "/Materials"
MAP_PATH = ROOT + "/Maps/L_Stillworld"

MPC_PATH = CORE_DIR + "/MPC_Weather"
RAIN_MAT_PATH = MAT_DIR + "/M_RainCurtain"
TERRAIN_MAT_PATH = MAT_DIR + "/M_Terrain"

ENGINE_NORMAL = "/Engine/EngineMaterials/DefaultNormal"
ENGINE_DIFFUSE = "/Engine/EngineMaterials/DefaultDiffuse"

# Exposure (EV100, with r.DefaultFeature.AutoExposure.ExtendDefaultLuminanceRange=True).
# NOTE: a 2.5 lux sun lights an albedo-0.5 surface to roughly 0.4 cd/m2, i.e. an
# EV100 of about 1-2. Clamping to 7..12 would render nearly black, so the
# clamp range is set around the expected scene luminance. Raise both together
# if you raise the sun intensity (each doubling of lux = +1 EV).
EXPOSURE_MIN_EV100 = 0.0
EXPOSURE_MAX_EV100 = 4.0
SUN_LUX = 2.5
# UE white balance: WhiteTemp is the temperature that is rendered as white.
# Values BELOW 6500 shift the image cooler (bluer); above 6500 warmer.
WHITE_TEMP = 6200.0

LOOPS = ["SW_Rain", "SW_Wind"]
SFX_SETS = [("Foot_Grass", 6), ("Foot_Dirt", 6), ("Foot_Asphalt", 6), ("Foot_Wet", 4),
            ("Drip", 5), ("Bird", 4), ("Crow", 2), ("Thunder_Far", 2),
            ("Metal_Creak", 3), ("Leaves_Gust", 3)]

LAYERS = [
    # name, metres per tile, placeholder albedo
    ("Grass", 2.5, "T_SW_Placeholder_Grass"),
    ("Dirt", 3.0, "T_SW_Placeholder_Dirt"),
    ("Asphalt", 4.0, "T_SW_Placeholder_Asphalt"),
    ("Moss", 2.0, "T_SW_Placeholder_Moss"),
]

EAL = unreal.EditorAssetLibrary
MEL = unreal.MaterialEditingLibrary
ASSET_TOOLS = unreal.AssetToolsHelpers.get_asset_tools()

RESULTS = {}


def log(msg):
    unreal.log("[Stillworld] " + msg)


def warn(msg):
    unreal.log_warning("[Stillworld] " + msg)


def err(msg):
    unreal.log_error("[Stillworld] " + msg)


def section(name):
    def deco(fn):
        def run():
            log("=== %s ===" % name)
            try:
                fn()
                RESULTS[name] = "ok"
            except Exception as e:  # keep going with the other sections
                RESULTS[name] = "FAILED: %s" % e
                err("%s failed: %s\n%s" % (name, e, traceback.format_exc()))
        return run
    return deco


def generated_dir():
    # project_dir() is often relative to Engine/Binaries; make it absolute the UE way.
    proj = unreal.Paths.project_dir()
    try:
        proj = unreal.Paths.convert_relative_path_to_full(proj)
    except Exception:
        proj = os.path.abspath(proj)
    return os.path.join(proj, "Tools", "generated")


def set_prop(obj, name, value, quiet=False):
    """set_editor_property that logs instead of raising (property names drift between UE versions)."""
    try:
        obj.set_editor_property(name, value)
        return True
    except Exception as e:
        if not quiet:
            warn("could not set %s.%s: %s" % (type(obj).__name__, name, e))
        return False


def set_first(obj, names, value):
    """Try several property names (renamed across engine versions)."""
    for n in names:
        if set_prop(obj, n, value, quiet=True):
            return n
    warn("could not set any of %s on %s" % (names, type(obj).__name__))
    return None


def save(path):
    try:
        if not EAL.save_asset(path, only_if_is_dirty=False):
            warn("save_asset returned False for " + path)
    except Exception as e:
        warn("save failed for %s: %s" % (path, e))


def load(path):
    return EAL.load_asset(path) if EAL.does_asset_exist(path) else None


def get_or_create(path, cls, factory):
    obj = load(path)
    if obj is not None:
        return obj, False
    folder, name = path.rsplit("/", 1)
    obj = ASSET_TOOLS.create_asset(name, folder, cls, factory)
    if obj is None:
        raise RuntimeError("create_asset failed for " + path)
    return obj, True


def import_file(filename, dest_dir, dest_name):
    if not os.path.isfile(filename):
        raise RuntimeError("missing source file %s (run Tools/generate_assets.py first)" % filename)
    task = unreal.AssetImportTask()
    task.set_editor_property("filename", filename)
    task.set_editor_property("destination_path", dest_dir)
    task.set_editor_property("destination_name", dest_name)
    task.set_editor_property("automated", True)
    task.set_editor_property("replace_existing", True)
    task.set_editor_property("save", True)
    # UE 5.1+: Interchange may import asynchronously; force synchronous if the flag exists.
    set_prop(task, "async_", False, quiet=True)
    ASSET_TOOLS.import_asset_tasks([task])
    path = dest_dir + "/" + dest_name
    asset = load(path)
    if asset is None:
        raise RuntimeError("import produced no asset at " + path)
    return asset


# ---------------------------------------------------------------------------
# 1. Imports
# ---------------------------------------------------------------------------

def _configure_texture(tex, compression, srgb):
    set_prop(tex, "compression_settings", compression)
    set_prop(tex, "srgb", srgb)


@section("Import textures")
def import_textures():
    gen = generated_dir()
    tc = unreal.TextureCompressionSettings

    t = import_file(os.path.join(gen, "T_RainStreaks.png"), TEX_DIR, "T_RainStreaks")
    _configure_texture(t, tc.TC_GRAYSCALE, False)
    save(TEX_DIR + "/T_RainStreaks")

    t = import_file(os.path.join(gen, "T_MacroNoise.png"), TEX_DIR, "T_MacroNoise")
    _configure_texture(t, tc.TC_GRAYSCALE, False)
    save(TEX_DIR + "/T_MacroNoise")

    # Placeholder layer textures (used as parameter defaults so M_Terrain compiles
    # and reads plausibly before Fab/Megascans textures are assigned).
    t = import_file(os.path.join(gen, "T_SW_Default_Rough.png"), PLACEHOLDER_DIR, "T_SW_Default_Rough")
    _configure_texture(t, tc.TC_MASKS, False)          # -> sampler type Masks
    save(PLACEHOLDER_DIR + "/T_SW_Default_Rough")
    for _, _, tex_name in LAYERS:
        t = import_file(os.path.join(gen, tex_name + ".png"), PLACEHOLDER_DIR, tex_name)
        _configure_texture(t, tc.TC_DEFAULT, True)     # -> sampler type Color
        save(PLACEHOLDER_DIR + "/" + tex_name)
    log("textures imported")


@section("Import audio")
def import_audio():
    gen = generated_dir()
    for name in LOOPS:
        w = import_file(os.path.join(gen, name + ".wav"), AUDIO_DIR, name)
        set_prop(w, "looping", True)
        save(AUDIO_DIR + "/" + name)
    count = 0
    for base, n in SFX_SETS:
        for i in range(1, n + 1):
            name = "%s_%02d" % (base, i)
            try:
                w = import_file(os.path.join(gen, "sfx", name + ".wav"), SFX_DIR, name)
                set_prop(w, "looping", False)
                save(SFX_DIR + "/" + name)
                count += 1
            except Exception as e:
                err("SFX %s: %s" % (name, e))
    log("audio imported (%d loops, %d one-shots)" % (len(LOOPS), count))


@section("Sound attenuation")
def create_attenuation():
    path = AUDIO_DIR + "/ATT_Ambient"
    att, _ = get_or_create(path, unreal.SoundAttenuation, unreal.SoundAttenuationFactory())
    s = att.get_editor_property("attenuation")       # FSoundAttenuationSettings (copy)
    set_prop(s, "attenuate", True)
    set_prop(s, "spatialize", True)
    set_prop(s, "distance_algorithm", unreal.AttenuationDistanceModel.NATURAL_SOUND)
    set_prop(s, "attenuation_shape", unreal.AttenuationShape.SPHERE)
    set_prop(s, "attenuation_shape_extents", unreal.Vector(200.0, 0.0, 0.0))   # sphere: X = inner radius
    set_prop(s, "falloff_distance", 6000.0)
    set_prop(s, "db_attenuation_at_max", -60.0, quiet=True)
    set_prop(s, "attenuate_with_lpf", True, quiet=True)   # gentle air absorption with distance
    att.set_editor_property("attenuation", s)
    save(path)
    log("ATT_Ambient ready")


# ---------------------------------------------------------------------------
# 2. Material parameter collection
# ---------------------------------------------------------------------------

MPC_SCALARS = [("Wetness", 0.0), ("RainIntensity", 0.0), ("WindStrength", 0.5),
               ("WindDirX", 1.0), ("WindDirY", 0.0)]


def get_mpc():
    mpc = load(MPC_PATH)
    if mpc is None:
        raise RuntimeError("MPC_Weather missing")
    return mpc


@section("MPC_Weather")
def create_mpc():
    mpc, created = get_or_create(MPC_PATH, unreal.MaterialParameterCollection,
                                 unreal.MaterialParameterCollectionFactoryNew())
    # Keep existing entries (and their GUIDs, which materials reference), only
    # update defaults and append missing parameters.
    existing = list(mpc.get_editor_property("scalar_parameters"))
    by_name = {str(p.get_editor_property("parameter_name")): p for p in existing}
    out = []
    for name, default in MPC_SCALARS:
        p = by_name.pop(name, None)
        if p is None:
            p = unreal.CollectionScalarParameter()   # C++ ctor assigns a fresh GUID
            p.set_editor_property("parameter_name", name)
        p.set_editor_property("default_value", default)
        out.append(p)
    out.extend(by_name.values())   # never silently drop parameters someone added
    mpc.set_editor_property("scalar_parameters", out)
    save(MPC_PATH)
    log("MPC_Weather %s with %d scalars" % ("created" if created else "updated", len(out)))


# ---------------------------------------------------------------------------
# Material graph helpers
# ---------------------------------------------------------------------------

class Graph(object):
    def __init__(self, mat):
        self.mat = mat

    def node(self, cls, x, y, **props):
        e = MEL.create_material_expression(self.mat, cls, x, y)
        if e is None:
            raise RuntimeError("create_material_expression(%s) failed" % cls.__name__)
        for k, v in props.items():
            e.set_editor_property(k, v)
        return e

    @staticmethod
    def link(src, dst, dst_input="", src_output=""):
        """src may be an expression or (expression, output_name)."""
        if isinstance(src, tuple):
            src, src_output = src
        if not MEL.connect_material_expressions(src, src_output, dst, dst_input):
            raise RuntimeError("connect %s.%s -> %s.%s failed" % (
                type(src).__name__, src_output, type(dst).__name__, dst_input))

    def to_prop(self, src, prop):
        out = ""
        if isinstance(src, tuple):
            src, out = src
        if not MEL.connect_material_property(src, out, prop):
            raise RuntimeError("connect_material_property(%s) failed" % prop)

    # arithmetic sugar ------------------------------------------------------
    def mul(self, a, b=None, x=0, y=0, const_b=None):
        n = self.node(unreal.MaterialExpressionMultiply, x, y)
        self.link(a, n, "A")
        if b is not None:
            self.link(b, n, "B")
        else:
            n.set_editor_property("const_b", const_b)
        return n

    def add(self, a, b, x=0, y=0):
        n = self.node(unreal.MaterialExpressionAdd, x, y)
        self.link(a, n, "A")
        self.link(b, n, "B")
        return n

    def lerp(self, a, b, alpha, x=0, y=0, const_a=None, const_b=None, const_alpha=None):
        n = self.node(unreal.MaterialExpressionLinearInterpolate, x, y)
        if a is not None:
            self.link(a, n, "A")
        else:
            n.set_editor_property("const_a", const_a)
        if b is not None:
            self.link(b, n, "B")
        else:
            n.set_editor_property("const_b", const_b)
        if alpha is not None:
            self.link(alpha, n, "Alpha")
        else:
            n.set_editor_property("const_alpha", const_alpha)
        return n

    def scalar_param(self, name, default, x, y, group=None):
        n = self.node(unreal.MaterialExpressionScalarParameter, x, y,
                      parameter_name=name, default_value=default)
        if group:
            set_prop(n, "group", group, quiet=True)
        return n

    def collection(self, mpc, name, x, y):
        n = self.node(unreal.MaterialExpressionCollectionParameter, x, y)
        n.set_editor_property("collection", mpc)        # set first: name->GUID lookup uses it
        n.set_editor_property("parameter_name", name)
        return n


def sampler_type_for(tex):
    """Mirror of UMaterialExpressionTextureBase::GetSamplerTypeForTexture."""
    st = unreal.MaterialSamplerType
    tc = unreal.TextureCompressionSettings
    comp = tex.get_editor_property("compression_settings")
    srgb = tex.get_editor_property("srgb")
    if comp == tc.TC_NORMALMAP:
        return st.SAMPLERTYPE_NORMAL
    if comp == tc.TC_GRAYSCALE:
        return st.SAMPLERTYPE_GRAYSCALE if srgb else st.SAMPLERTYPE_LINEAR_GRAYSCALE
    if comp == tc.TC_ALPHA:
        return st.SAMPLERTYPE_ALPHA
    if comp == tc.TC_MASKS:
        return st.SAMPLERTYPE_MASKS
    if comp == tc.TC_DISTANCE_FIELD_FONT:
        return st.SAMPLERTYPE_DISTANCE_FIELD_FONT
    return st.SAMPLERTYPE_COLOR if srgb else st.SAMPLERTYPE_LINEAR_COLOR


def set_texture(node, tex):
    node.set_editor_property("texture", tex)
    node.set_editor_property("sampler_type", sampler_type_for(tex))
    # Shared wrap sampler: avoids the 16-sampler limit on the terrain material.
    set_prop(node, "sampler_source", unreal.SamplerSourceMode.SSM_WRAP_WORLD_GROUP_SETTINGS, quiet=True)


def reset_material(path):
    mat, created = get_or_create(path, unreal.Material, unreal.MaterialFactoryNew())
    if not created:
        MEL.delete_all_material_expressions(mat)
    return mat


def finish_material(mat, path):
    # Nodes are placed by hand above; the auto-layout is usually worse.
    MEL.recompile_material(mat)
    save(path)


# ---------------------------------------------------------------------------
# 3. M_RainCurtain
# ---------------------------------------------------------------------------

@section("M_RainCurtain")
def create_rain_material():
    mpc = get_mpc()
    tex = load(TEX_DIR + "/T_RainStreaks")
    if tex is None:
        raise RuntimeError("T_RainStreaks not imported")
    mat = reset_material(RAIN_MAT_PATH)
    set_prop(mat, "blend_mode", unreal.BlendMode.BLEND_TRANSLUCENT)
    set_prop(mat, "shading_model", unreal.MaterialShadingModel.MSM_DEFAULT_LIT)
    set_prop(mat, "two_sided", True)
    set_prop(mat, "translucency_lighting_mode", unreal.TranslucencyLightingMode.TLM_VOLUMETRIC_NON_DIRECTIONAL)
    # Translucent materials do not write scene depth by default; also make sure
    # the optional translucent depth/velocity output is off (name varies by version).
    set_prop(mat, "output_translucent_velocity", False, quiet=True)

    g = Graph(mat)
    # UV: TexCoord (V tiled x0.5) * Tiling, then V += Time * Speed (flip Speed's sign
    # if streaks scroll upward on the cylinder's UV layout).
    tc = g.node(unreal.MaterialExpressionTextureCoordinate, -1400, 0,
                coordinate_index=0, u_tiling=1.0, v_tiling=0.5)
    tiling = g.scalar_param("Tiling", 4.0, -1400, 150)
    uv = g.mul(tc, tiling, -1200, 50)
    time = g.node(unreal.MaterialExpressionTime, -1400, 300)
    speed = g.scalar_param("Speed", 1.5, -1400, 400)
    ts = g.mul(time, speed, -1200, 300)
    pan = g.node(unreal.MaterialExpressionAppendVector, -1050, 300)
    zero = g.node(unreal.MaterialExpressionConstant, -1200, 450, r=0.0)
    g.link(zero, pan, "A")
    g.link(ts, pan, "B")
    uv2 = g.add(uv, pan, -900, 100)

    samp = g.node(unreal.MaterialExpressionTextureSample, -700, 100)
    set_texture(samp, tex)
    g.link(uv2, samp, "UVs")

    layer_op = g.scalar_param("LayerOpacity", 0.5, -700, 350)
    rain = g.collection(mpc, "RainIntensity", -700, 450)
    o1 = g.mul((samp, "R"), layer_op, -450, 150)
    o2 = g.mul(o1, rain, -300, 200)
    o3 = g.mul(o2, None, -150, 200, const_b=0.4)
    # DepthFade with no input outputs OpacityDefault(1) * soft-intersection factor.
    df = g.node(unreal.MaterialExpressionDepthFade, -300, 400,
                fade_distance_default=150.0, opacity_default=1.0)
    opacity = g.mul(o3, df, 0, 250)
    g.to_prop(opacity, unreal.MaterialProperty.MP_OPACITY)

    base = g.node(unreal.MaterialExpressionConstant3Vector, 0, 0,
                  constant=unreal.LinearColor(0.75, 0.75, 0.75, 1.0))
    g.to_prop(base, unreal.MaterialProperty.MP_BASE_COLOR)
    rough = g.node(unreal.MaterialExpressionConstant, 0, 120, r=0.4)
    g.to_prop(rough, unreal.MaterialProperty.MP_ROUGHNESS)

    finish_material(mat, RAIN_MAT_PATH)
    log("M_RainCurtain built")


# ---------------------------------------------------------------------------
# 4. M_Terrain + instances
# ---------------------------------------------------------------------------

def _first_texture(paths):
    for p in paths:
        t = load(p)
        if t is not None:
            return t
    raise RuntimeError("none of these textures exist: %s" % paths)


@section("M_Terrain")
def create_terrain_material():
    mpc = get_mpc()
    normal_default = _first_texture([ENGINE_NORMAL])
    rough_default = _first_texture([PLACEHOLDER_DIR + "/T_SW_Default_Rough", ENGINE_DIFFUSE])
    macro_tex = _first_texture([TEX_DIR + "/T_MacroNoise"])

    mat = reset_material(TERRAIN_MAT_PATH)
    set_prop(mat, "blend_mode", unreal.BlendMode.BLEND_OPAQUE)
    set_prop(mat, "shading_model", unreal.MaterialShadingModel.MSM_DEFAULT_LIT)
    set_prop(mat, "tangent_space_normal", True)   # mesh supplies tangents
    g = Graph(mat)

    world_uv = g.node(unreal.MaterialExpressionTextureCoordinate, -3000, 0, coordinate_index=0)  # metres
    # VertexColor outputs are unnamed in UE (channel masks only), so split the
    # channels once with ComponentMask nodes and reuse them everywhere.
    vc = g.node(unreal.MaterialExpressionVertexColor, -3000, 1600)
    vc_raw = {}
    for i, ch in enumerate("RGBA"):
        m = g.node(unreal.MaterialExpressionComponentMask, -2850, 1600 + i * 80,
                   r=(ch == "R"), g=(ch == "G"), b=(ch == "B"), a=(ch == "A"))
        g.link(vc, m)   # "" = first (RGBA) output
        vc_raw[ch] = m
    # Normalise the ground weights so R+G+B = 1 even if a vertex drifts (or a
    # mesh without colours reads as white).
    w_sum = g.add(g.add(vc_raw["R"], vc_raw["G"], -2700, 1600), vc_raw["B"], -2600, 1600)
    w_max = g.node(unreal.MaterialExpressionMax, -2500, 1600, const_b=0.001)
    g.link(w_sum, w_max, "A")
    VC = {"A": vc_raw["A"]}
    for i, ch in enumerate("RGB"):
        d = g.node(unreal.MaterialExpressionDivide, -2400, 1600 + i * 80)
        g.link(vc_raw[ch], d, "A")
        g.link(w_max, d, "B")
        VC[ch] = d
    wet = g.collection(mpc, "Wetness", -3000, 1950)

    layers = {}
    y = -1600
    for name, tiling_default, placeholder in LAYERS:
        albedo_default = _first_texture([PLACEHOLDER_DIR + "/" + placeholder, ENGINE_DIFFUSE])
        tiling = g.scalar_param(name + "_Tiling", tiling_default, -2700, y, group=name)
        uv_a = g.node(unreal.MaterialExpressionDivide, -2500, y)
        g.link(world_uv, uv_a, "A")
        g.link(tiling, uv_a, "B")
        uv_b = g.mul(uv_a, None, -2350, y + 120, const_b=0.27)

        def tparam(suffix, tex, yy, uv):
            n = g.node(unreal.MaterialExpressionTextureSampleParameter2D, -2100, yy,
                       parameter_name="%s_%s" % (name, suffix))
            set_prop(n, "group", name, quiet=True)
            set_texture(n, tex)
            g.link(uv, n, "UVs")
            return n

        # Same parameter name twice = one parameter, two samples (anti-tiling).
        bc_a = tparam("BaseColor", albedo_default, y, uv_a)
        bc_b = tparam("BaseColor", albedo_default, y + 200, uv_b)
        nrm = tparam("Normal", normal_default, y + 400, uv_a)
        rgh = tparam("Roughness", rough_default, y + 600, uv_a)

        bc = g.lerp((bc_a, "RGB"), (bc_b, "RGB"), None, -1800, y + 100, const_alpha=0.3)
        tint = g.node(unreal.MaterialExpressionVectorParameter, -1800, y + 250,
                      parameter_name=name + "_Tint", default_value=unreal.LinearColor(1, 1, 1, 1))
        set_prop(tint, "group", name, quiet=True)
        tint_rgb = g.node(unreal.MaterialExpressionComponentMask, -1650, y + 250, r=True, g=True, b=True, a=False)
        g.link(tint, tint_rgb)
        layers[name] = {
            "base": g.mul(bc, tint_rgb, -1500, y + 150),
            "normal": (nrm, "RGB"),
            "rough": (rgh, "R"),
        }
        y += 900

    def blend3(key, x, yy):
        acc = None
        for name, ch in (("Grass", "R"), ("Dirt", "G"), ("Asphalt", "B")):
            term = g.mul(layers[name][key], VC[ch], x, yy)
            acc = term if acc is None else g.add(acc, term, x + 150, yy)
            yy += 120
        return g.lerp(acc, layers["Moss"][key], VC["A"], x + 300, yy)   # moss on top

    base = blend3("base", -1200, -400)
    normal = blend3("normal", -1200, 200)
    rough = blend3("rough", -1200, 800)

    # Macro variation (UV0 is metres: ~48 m and ~160 m periods).
    m1 = g.node(unreal.MaterialExpressionTextureSample, -1200, 1300)
    set_texture(m1, macro_tex)
    g.link(g.mul(world_uv, None, -1350, 1300, const_b=0.021), m1, "UVs")
    m2 = g.node(unreal.MaterialExpressionTextureSample, -1200, 1500)
    set_texture(m2, macro_tex)
    g.link(g.mul(world_uv, None, -1350, 1500, const_b=0.0063), m2, "UVs")
    mix = g.lerp((m1, "R"), (m2, "R"), None, -1000, 1400, const_alpha=0.4)
    macro = g.lerp(None, None, mix, -850, 1400, const_a=0.82, const_b=1.12)
    base = g.mul(base, macro, -700, -300)

    # Puddles: low-frequency noise (~9 m) on asphalt, not under moss, scaled by wetness.
    pn = g.node(unreal.MaterialExpressionTextureSample, -1200, 1750)
    set_texture(pn, macro_tex)
    g.link(g.mul(world_uv, None, -1350, 1750, const_b=0.11), pn, "UVs")
    p_sub = g.node(unreal.MaterialExpressionSubtract, -1000, 1750, const_b=0.55)
    g.link((pn, "R"), p_sub, "A")
    p_sat = g.node(unreal.MaterialExpressionSaturate, -700, 1750)
    g.link(g.mul(p_sub, None, -850, 1750, const_b=5.0), p_sat)
    no_moss = g.node(unreal.MaterialExpressionOneMinus, -850, 1900)
    g.link(VC["A"], no_moss)
    puddle = g.mul(g.mul(g.mul(p_sat, VC["B"], -550, 1750), wet, -400, 1750), no_moss, -250, 1750)

    # Wetness: darken albedo, smooth roughness; puddles go further.
    wet_dark = g.lerp(None, None, wet, -550, -200, const_a=1.0, const_b=0.55)
    base = g.mul(base, wet_dark, -400, -300)
    pud_dark = g.lerp(None, None, puddle, -250, -200, const_a=1.0, const_b=0.6)
    base = g.mul(base, pud_dark, -100, -300)

    rough = g.lerp(rough, None, wet, -550, 800, const_b=0.2)
    rough = g.lerp(rough, None, puddle, -250, 800, const_b=0.03)

    flat = g.node(unreal.MaterialExpressionConstant3Vector, -550, 450,
                  constant=unreal.LinearColor(0, 0, 1, 1))
    normal = g.lerp(normal, flat, puddle, -250, 300)

    g.to_prop(base, unreal.MaterialProperty.MP_BASE_COLOR)
    g.to_prop(normal, unreal.MaterialProperty.MP_NORMAL)
    g.to_prop(rough, unreal.MaterialProperty.MP_ROUGHNESS)
    finish_material(mat, TERRAIN_MAT_PATH)
    log("M_Terrain built")


MI_SETTINGS = {
    "MI_Terrain_Meadow": {
        "vectors": {"Grass_Tint": (0.62, 0.64, 0.47), "Dirt_Tint": (0.92, 0.88, 0.82),
                    "Moss_Tint": (0.85, 0.9, 0.75)},
        "scalars": {},
    },
    "MI_Terrain_Reclaimed": {
        "vectors": {"Grass_Tint": (0.72, 0.74, 0.58), "Dirt_Tint": (0.8, 0.76, 0.7),
                    "Asphalt_Tint": (0.82, 0.82, 0.84), "Moss_Tint": (0.9, 1.0, 0.78)},
        "scalars": {"Moss_Tiling": 1.6},
    },
}


@section("Terrain material instances")
def create_terrain_instances():
    parent = load(TERRAIN_MAT_PATH)
    if parent is None:
        raise RuntimeError("M_Terrain missing")
    for name, cfg in MI_SETTINGS.items():
        path = MAT_DIR + "/" + name
        mi, _ = get_or_create(path, unreal.MaterialInstanceConstant,
                              unreal.MaterialInstanceConstantFactoryNew())
        MEL.set_material_instance_parent(mi, parent)
        for p, c in cfg["vectors"].items():
            MEL.set_material_instance_vector_parameter_value(mi, p, unreal.LinearColor(c[0], c[1], c[2], 1.0))
        for p, v in cfg["scalars"].items():
            MEL.set_material_instance_scalar_parameter_value(mi, p, v)
        MEL.update_material_instance(mi)
        save(path)
        log(name + " ready")


# ---------------------------------------------------------------------------
# 5. Level
# ---------------------------------------------------------------------------

def actor_subsystem():
    return unreal.get_editor_subsystem(unreal.EditorActorSubsystem)


def find_actor(label):
    for a in actor_subsystem().get_all_level_actors():
        try:
            if a.get_actor_label() == label:
                return a
        except Exception:
            pass
    return None


def ensure_actor(label, cls, loc=None, rot=None):
    loc = loc or unreal.Vector(0, 0, 0)
    rot = rot or unreal.Rotator(roll=0.0, pitch=0.0, yaw=0.0)
    a = find_actor(label)
    if a is None:
        a = actor_subsystem().spawn_actor_from_class(cls, loc, rot)
        if a is None:
            raise RuntimeError("spawn failed for " + label)
        a.set_actor_label(label)
        log("spawned " + label)
    else:
        a.set_actor_location(loc, False, False)
        a.set_actor_rotation(rot, False)
    return a


def comp(actor, cls):
    c = actor.get_component_by_class(cls)
    if c is None:
        raise RuntimeError("%s has no %s" % (actor.get_actor_label(), cls.__name__))
    return c


def guarded(label, fn):
    try:
        fn()
    except Exception as e:
        err("%s: %s\n%s" % (label, e, traceback.format_exc()))


@section("Level")
def build_level():
    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    if EAL.does_asset_exist(MAP_PATH):
        if not les.load_level(MAP_PATH):
            raise RuntimeError("load_level failed")
        log("loaded " + MAP_PATH)
    else:
        if not les.new_level(MAP_PATH):
            raise RuntimeError("new_level failed")
        log("created " + MAP_PATH)

    movable = unreal.ComponentMobility.MOVABLE

    def sun():
        a = ensure_actor("SW_Sun", unreal.DirectionalLight,
                         rot=unreal.Rotator(roll=0.0, pitch=-35.0, yaw=40.0))
        c = comp(a, unreal.DirectionalLightComponent)
        c.set_mobility(movable)
        set_prop(c, "intensity", SUN_LUX)
        set_prop(c, "cast_shadows", True)
        set_prop(c, "atmosphere_sun_light", True)
        set_prop(c, "cast_cloud_shadows", True, quiet=True)

    def sky_atmosphere():
        ensure_actor("SW_SkyAtmosphere", unreal.SkyAtmosphere)

    def clouds():
        ensure_actor("SW_VolumetricCloud", unreal.VolumetricCloud)

    def sky_light():
        a = ensure_actor("SW_SkyLight", unreal.SkyLight)
        c = comp(a, unreal.SkyLightComponent)
        c.set_mobility(movable)
        set_prop(c, "real_time_capture", True)

    def fog():
        a = ensure_actor("SW_HeightFog", unreal.ExponentialHeightFog)
        c = comp(a, unreal.ExponentialHeightFogComponent)
        set_prop(c, "fog_density", 0.05)
        set_prop(c, "fog_height_falloff", 0.1)
        # UE 5.1 renamed FogInscatteringColor -> FogInscatteringLuminance.
        set_first(c, ["fog_inscattering_luminance", "fog_inscattering_color"],
                  unreal.LinearColor(0.55, 0.58, 0.6, 1.0))
        set_first(c, ["volumetric_fog", "enable_volumetric_fog"], True)
        set_prop(c, "volumetric_fog_extinction_scale", 1.5)
        set_prop(c, "start_distance", 0.0)

    def post():
        a = ensure_actor("SW_PostProcess", unreal.PostProcessVolume)
        set_prop(a, "unbound", True)       # infinite extent
        set_prop(a, "blend_weight", 1.0, quiet=True)
        s = a.get_editor_property("settings")

        def ov(field, value):
            ok = set_prop(s, field, value, quiet=True)
            set_prop(s, "override_" + field, True, quiet=True)
            if not ok:
                warn("post process setting %s not available" % field)

        ov("auto_exposure_method", unreal.AutoExposureMethod.AEM_HISTOGRAM)
        ov("auto_exposure_bias", 0.3)
        ov("auto_exposure_min_brightness", EXPOSURE_MIN_EV100)
        ov("auto_exposure_max_brightness", EXPOSURE_MAX_EV100)
        ov("bloom_intensity", 0.3)
        ov("vignette_intensity", 0.25)
        ov("film_grain_intensity", 0.15)
        ov("color_saturation", unreal.Vector4(0.82, 0.82, 0.82, 1.0))
        ov("color_contrast", unreal.Vector4(0.97, 0.97, 0.97, 1.0))
        ov("white_temp", WHITE_TEMP)
        ov("motion_blur_amount", 0.0)
        ov("lumen_final_gather_quality", 1.0)
        ov("lumen_reflection_quality", 1.0)
        # Local exposure: left at engine defaults (no overrides).
        a.set_editor_property("settings", s)

    def stillworld_actor(label, class_path):
        cls = None
        try:
            cls = unreal.load_class(None, class_path)
        except Exception:
            cls = None
        if cls is None:
            warn("%s not found - compile the Stillworld C++ module, then re-run this script" % class_path)
            return
        ensure_actor(label, cls)

    def player_start():
        ensure_actor("SW_PlayerStart", unreal.PlayerStart, loc=unreal.Vector(0.0, 0.0, 20000.0))

    for label, fn in (("Sun", sun), ("SkyAtmosphere", sky_atmosphere), ("VolumetricCloud", clouds),
                      ("SkyLight", sky_light), ("HeightFog", fog), ("PostProcess", post),
                      ("Weather", lambda: stillworld_actor("SW_Weather", "/Script/Stillworld.StillworldWeather")),
                      ("World", lambda: stillworld_actor("SW_World", "/Script/Stillworld.StillworldWorld")),
                      ("PlayerStart", player_start)):
        guarded("Level/" + label, fn)

    if not les.save_current_level():
        warn("save_current_level returned False")
    log("level saved")


def main():
    import_textures()
    import_audio()
    create_attenuation()
    create_mpc()
    create_rain_material()
    create_terrain_material()
    create_terrain_instances()
    build_level()
    log("---- summary ----")
    for k, v in RESULTS.items():
        (log if v == "ok" else err)("%-28s %s" % (k, v))


main()
