import bpy, sys
out = sys.argv[sys.argv.index("--") + 1]
sc = bpy.context.scene
for o in list(sc.objects):
    if o.type in {'CAMERA', 'LIGHT'} or o.hide_render:
        bpy.data.objects.remove(o, do_unlink=True)
TARGET = 150_000
# Bevels only round edges a few mm wide; at AR size they cost triangles without showing.
for o in sc.objects:
    for m in getattr(o, "modifiers", []):
        if m.type == 'BEVEL': m.show_viewport = False; m.show_render = False
dg = bpy.context.evaluated_depsgraph_get()
def tris(o):
    e = o.evaluated_get(dg); m = e.to_mesh(); m.calc_loop_triangles(); n = len(m.loop_triangles); e.to_mesh_clear()
    return n
meshes = [o for o in sc.objects if o.type == 'MESH']
counts = {o.name: tris(o) for o in meshes}
total = sum(counts.values())
# Two materials use nodes USD can't carry (hue/curve adjustments, an opacity mask on a
# wire mesh); give them the solid colors they render as in Blender.
def flatten(name, color, metallic, roughness):
    mat = bpy.data.materials.get(name)
    if not mat: return
    tree = mat.node_tree
    bsdf = next(n for n in tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    for key in ("Base Color", "Alpha", "Metallic", "Roughness"):
        for l in list(bsdf.inputs[key].links): tree.links.remove(l)
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Alpha"].default_value = 1
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
flatten("Wheel_Covers", (0.36, 0.14, 0.05), 0.0, 0.55)   # fiberglass fenders, burnt orange-brown
flatten("Wheel_Mesh", (0.12, 0.12, 0.12), 0.8, 0.5)      # zinc-coated wire mesh tires, dark

# Each large piece keeps ~4000 triangles but never less than 10%: below that thin
# shells (fenders, the antenna dish, tires) tear open.
big = [o for o in meshes if counts[o.name] > 4000]
print("TOTAL", total, "BIG", len(big))
for o in big:
    planar = o.modifiers.new("LumoriaPlanar", 'DECIMATE')
    planar.decimate_type = 'DISSOLVE'
    planar.angle_limit = 0.0349
    m = o.modifiers.new("LumoriaDecimate", 'DECIMATE')
    m.ratio = max(0.1, min(1.0, 4000 / counts[o.name]))
    m.use_collapse_triangulate = True

# Bake the modifiers into plain meshes, then drop duplicate and loose vertices they leave behind.
import bmesh
bpy.ops.object.select_all(action='DESELECT')
for o in sc.objects:
    if o.type in {'MESH', 'CURVE'}: o.select_set(True)
bpy.context.view_layer.objects.active = next(o for o in sc.objects if o.type == 'MESH')
bpy.ops.object.convert(target='MESH')
seen = set()
for o in sc.objects:
    if o.type != 'MESH' or o.data.name in seen: continue
    seen.add(o.data.name)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(o.data); bm.free()
bpy.ops.wm.usd_export(
    filepath=out, selected_objects_only=False, export_animation=False,
    export_materials=True, generate_preview_surface=True, export_textures_mode='NEW', convert_world_material=False,
    usdz_downscale_size='512', evaluation_mode='VIEWPORT',
    convert_orientation=True, export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
    export_cameras=False, export_lights=False)
print("EXPORTED", out)
