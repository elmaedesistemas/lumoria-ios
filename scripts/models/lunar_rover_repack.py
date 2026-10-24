import sys, os
from pxr import Usd, UsdShade, Sdf, UsdUtils
root, out = sys.argv[sys.argv.index("--") + 1:][:2]
src = os.path.join(root, "lunar-rover.usdc")
st = Usd.Stage.Open(src)
changed = 0
for prim in st.Traverse():
    if not prim.IsA(UsdShade.Shader): continue
    a = prim.GetAttribute("inputs:file")
    if not a or not a.Get(): continue
    path = a.Get().path
    full = lambda p: os.path.join(root, p.lstrip("./"))
    if path.endswith(".png") and not os.path.exists(full(path)) and os.path.exists(full(path[:-4] + ".jpg")):
        a.Set(Sdf.AssetPath(path[:-4] + ".jpg")); changed += 1
    elif not os.path.exists(full(path)):
        # Textures of the moon-scene rocks, which weren't extracted; the material keeps its base color.
        a.Set(Sdf.AssetPath("")); changed += 1
# Thin shells (fenders, antenna dish) are single sheets; Blender draws both sides, RealityKit only if told.
from pxr import UsdGeom
for prim in st.Traverse():
    if prim.IsA(UsdGeom.Mesh): UsdGeom.Mesh(prim).CreateDoubleSidedAttr(True)
st.GetRootLayer().Save()
print("REWROTE", changed)
print("PACKED", UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(src), out))
