"""Builds the character models used by the Character Creator from the downloaded character packs.

Sources (read straight from the downloaded archives, never modified):
  <people>/drive-download-*.zip                    "Ultimate Modular Males" by Quaternius, CC0 1.0
  <people>/Universal Base Characters[Standard].zip  "Universal Base Characters (Standard)" by
                                                    Quaternius, CC0 1.0
  <people>/source.zip  (Separate_assets_glb.zip)    "Creative Characters FREE" by ithappy,
                                                    royalty-free licence WITHOUT a redistribution
                                                    grant: built locally, git-ignored, never
                                                    committed (see CREDITS.md)

<people> defaults to C:/Users/Grev/Downloads/People; pass another folder as the first argument.

Writes, under assets/characters/ (runtime models, imported by Godot):
  quaternius_modular_males/<outfit>_<part>.glb   one GLB per outfit part (head, body, legs,
                                                 feet, backpack). Every part keeps the full
                                                 62-bone rig so parts can share one skeleton.
                                                 Parts identical to an earlier one are skipped.
  quaternius_modular_males/animations.glb        the pack's 24 animations on the rig, no meshes
  quaternius_modular_males/hat_<name>.glb        hats split off the heads they were modelled on
                                                 (by material: worker hard hat, farmer straw hat,
                                                 king's crown), so any modular head can wear them
  quaternius_universal_base/<model>.glb          two base bodies and the hairstyles, eyebrows
                                                 and beard rigged to the head bone
  quaternius_universal_base/textures/*.png       one copy of each texture the models reference
  ithappy_creative_characters/<item>.glb         the body and 29 items (local only)
  ithappy_creative_characters/textures/*.png     the pack's one shared palette texture
and a .import file next to each model so Godot renames its bones to the humanoid profile
(assets/characters/rigs/*.bone_map.tres) when it imports it. That is what lets one animation set
drive all three skeletons (CharacterRig / RetargetModifier3D at runtime).

The original archives are also copied to authoring/characters/source/ (git-ignored, .gdignore) so
the project keeps the untouched originals, including the .blend and .fbx files Godot does not use.

Needs Python 3 only (no Blender). Re-running gives the same files and leaves unchanged ones alone.
Run:  python tools/import_character_assets.py [people folder]
"""
import glob
import hashlib
import io
import json
import os
import shutil
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_pack import Gltf, write_file  # noqa: E402  (tool-local module)

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PEOPLE = 'C:/Users/Grev/Downloads/People'
OUT = os.path.join(PROJECT, 'assets', 'characters')
SOURCE_COPY = os.path.join(PROJECT, 'authoring', 'characters', 'source')

MODULAR_DIR = 'quaternius_modular_males'
UNIVERSAL_DIR = 'quaternius_universal_base'
ITHAPPY_DIR = 'ithappy_creative_characters'

# Outfit glTF file -> output prefix. Every file holds the same rig and the same 24 animations.
MODULAR_OUTFITS = ['Adventurer', 'Beach', 'Casual_2', 'Casual_Hoodie', 'Farmer', 'King', 'Punk',
                   'Spacesuit', 'Suit', 'Swat', 'Worker']
MODULAR_SKIP = {'Pistol', 'Sword'}  # the pack's prop weapons; F2F has its own weapons
MODULAR_ANIMATION_SOURCE = 'Swat'
# Hats modelled into a head, split off by material: outfit -> (output name, materials).
MODULAR_HATS = {
    'Worker': ('hat_hard_hat', {'Worker_Yellow'}),
    'Farmer': ('hat_straw_hat', {'Beige', 'Red'}),
    'King': ('hat_crown', {'Gold'}),
}

UNIVERSAL_ROOT = 'Universal Base Characters[Standard]/'
UNIVERSAL_BODIES = 'Base Characters/Godot - UE/'
UNIVERSAL_HAIR = 'Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/'
# Textures the glTF files name but the pack ships under another name.
UNIVERSAL_TEXTURE_ALIASES = {'T_Hair_1_Normal_png.png': 'T_Hair_1_Normal.png',
                             'T_Eye_Normal_png.png': 'T_Eye_Normal.png'}
# The pack's light skin textures (not referenced by any glTF; offered as a skin choice).
UNIVERSAL_EXTRA_TEXTURES = ['Base Characters/Textures/T_Superhero_Male_Ligh.png',
                            'Base Characters/Textures/T_Superhero_Female_Light_BaseColor.png']

# Godot node path of the Skeleton3D each pack's files import with, and its bone map.
RIGS = {
    MODULAR_DIR: ('CharacterArmature/Skeleton3D', 'res://assets/characters/rigs/quaternius_modular.bone_map.tres'),
    UNIVERSAL_DIR: ('Armature/Skeleton3D', 'res://assets/characters/rigs/quaternius_universal.bone_map.tres'),
    ITHAPPY_DIR: ('Skeleton/Skeleton3D', 'res://assets/characters/rigs/ithappy_creative.bone_map.tres'),
}


def main():
    people = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PEOPLE
    archives = {
        'modular': _one(people, 'drive-download-*.zip'),
        'universal': _one(people, 'Universal Base Characters*.zip'),
        'ithappy': _one(people, 'source.zip'),
    }
    report = {'written': 0, 'skipped_duplicates': []}
    _copy_sources(people)
    _build_modular(archives['modular'], report)
    _build_universal(archives['universal'], report)
    _build_ithappy(archives['ithappy'], report)
    print(json.dumps(report, indent=1))


def _one(folder, pattern):
    hits = sorted(glob.glob(os.path.join(folder, pattern)))
    if not hits:
        sys.exit('missing %s in %s' % (pattern, folder))
    return hits[0]


def _copy_sources(people):
    """Keeps the untouched downloads inside the project (git-ignored, never imported)."""
    os.makedirs(SOURCE_COPY, exist_ok=True)
    write_file(os.path.join(SOURCE_COPY, '.gdignore'), b'')
    write_file(os.path.join(SOURCE_COPY, 'README.txt'), (
        'Untouched copies of the downloaded character packs (from %s).\n'
        'Git-ignored and never imported by Godot (.gdignore). tools/import_character_assets.py\n'
        'builds the runtime models in assets/characters from them.\n' % people).encode())
    for path in sorted(glob.glob(os.path.join(people, '*'))):
        if os.path.isfile(path):
            target = os.path.join(SOURCE_COPY, os.path.basename(path))
            if not os.path.exists(target) or os.path.getsize(target) != os.path.getsize(path):
                shutil.copy2(path, target)


# --- Ultimate Modular Males -----------------------------------------------------------------------

def _build_modular(archive, report):
    seen = {}
    with zipfile.ZipFile(archive) as z:
        for outfit in MODULAR_OUTFITS:
            name = 'Individual Characters/glTF/%s.gltf' % outfit
            gltf = Gltf.from_bytes(z.read(name), name)
            mesh_nodes = [i for i, n in enumerate(gltf.doc['nodes']) if 'mesh' in n]
            others = [i for i, n in enumerate(gltf.doc['nodes']) if 'mesh' not in n]
            for index in mesh_nodes:
                node_name = gltf.doc['nodes'][index]['name']
                if node_name in MODULAR_SKIP:
                    continue
                part = {'pants': 'legs'}.get(node_name.split('_')[-1].lower(), node_name.split('_')[-1].lower())
                out_name = '%s_%s.glb' % (outfit.lower(), part)
                digest = gltf.mesh_digest(gltf.doc['nodes'][index]['mesh'])
                if digest in seen:
                    report['skipped_duplicates'].append('%s = %s' % (out_name, seen[digest]))
                    continue
                seen[digest] = out_name
                _write_model(MODULAR_DIR, out_name, gltf.subset(others + [index]), report)
                if part == 'head' and outfit in MODULAR_HATS:
                    hat_name, materials = MODULAR_HATS[outfit]
                    _write_model(MODULAR_DIR, hat_name + '.glb',
                                 gltf.subset(others + [index], keep_materials=materials), report)
            if outfit == MODULAR_ANIMATION_SOURCE:
                _write_model(MODULAR_DIR, 'animations.glb', gltf.subset(others, keep_animations=True), report)


# --- Universal Base Characters --------------------------------------------------------------------

def _build_universal(archive, report):
    with zipfile.ZipFile(archive) as z:
        names = set(z.namelist())
        written_textures = set()
        for folder in (UNIVERSAL_BODIES, UNIVERSAL_HAIR):
            prefix = UNIVERSAL_ROOT + folder
            for name in sorted(n for n in names if n.startswith(prefix) and n.endswith('.gltf')):
                def read(uri, base=prefix):
                    return z.read(base + uri)
                gltf = Gltf.from_bytes(z.read(name), name, read_file=read)
                external = {}
                for image_index, image in enumerate(gltf.doc.get('images', [])):
                    uri = UNIVERSAL_TEXTURE_ALIASES.get(image['uri'], image['uri'])
                    if prefix + uri not in names:
                        sys.exit('%s names a missing texture %s' % (name, image['uri']))
                    external[image_index] = 'textures/' + uri
                    if uri not in written_textures:
                        written_textures.add(uri)
                        _write_texture(UNIVERSAL_DIR, uri, z.read(prefix + uri), report)
                keep = list(range(len(gltf.doc['nodes'])))
                out_name = os.path.basename(name)[:-5].lower() + '.glb'
                _write_model(UNIVERSAL_DIR, out_name, gltf.subset(keep, external_images=external), report)
        for extra in UNIVERSAL_EXTRA_TEXTURES:
            _write_texture(UNIVERSAL_DIR, os.path.basename(extra), z.read(UNIVERSAL_ROOT + extra), report)


# --- Creative Characters FREE (ithappy) -----------------------------------------------------------

def _build_ithappy(archive, report):
    with zipfile.ZipFile(archive) as outer:
        inner = zipfile.ZipFile(io.BytesIO(outer.read('Separate_assets_glb.zip')))
    texture_written = False
    for name in sorted(n for n in inner.namelist() if n.endswith('.glb')):
        gltf = Gltf.from_bytes(inner.read(name), name)
        external = {}
        for image_index, image in enumerate(gltf.doc.get('images', [])):
            file_name = image.get('name', 'texture') + '.png'
            external[image_index] = 'textures/' + file_name
            if not texture_written:
                texture_written = True
                _write_texture(ITHAPPY_DIR, file_name, bytes(gltf.image_bytes(image_index)), report)
        keep = list(range(len(gltf.doc['nodes'])))
        out_name = os.path.basename(name)[:-4].lower().replace('-', '_') + '.glb'
        _write_model(ITHAPPY_DIR, out_name, gltf.subset(keep, external_images=external), report)


# --- output -----------------------------------------------------------------------------------------

def _write_model(pack_dir, file_name, gltf, report):
    path = os.path.join(OUT, pack_dir, file_name)
    if write_file(path, gltf.glb_bytes()):
        report['written'] += 1
    _write_import(pack_dir, path)


def _write_texture(pack_dir, file_name, data, report):
    if write_file(os.path.join(OUT, pack_dir, 'textures', file_name), data):
        report['written'] += 1


def _write_import(pack_dir, model_path):
    """Writes the import settings that rename the rig's bones to the humanoid profile.

    Rests are left as authored: CharacterRig retargets in model space at runtime, which copes
    with the packs' different hierarchies. An existing .import keeps its uid and other edits.
    """
    skeleton_path, bone_map = RIGS[pack_dir]
    import_path = model_path + '.import'
    options = {
        'retarget/bone_map': 'Resource("%s")' % bone_map,
        'retarget/bone_renamer/rename_bones': 'true',
        'retarget/bone_renamer/unique_node/make_unique': 'true',
        'retarget/bone_renamer/unique_node/skeleton_name': '"GeneralSkeleton"',
        'retarget/rest_fixer/apply_node_transforms': 'true',
        'retarget/rest_fixer/normalize_position_tracks': 'false',
        'retarget/rest_fixer/reset_all_bone_poses_after_import': 'true',
        'retarget/rest_fixer/retarget_method': '0',
        'retarget/rest_fixer/fix_silhouette/enable': 'false',
        'retarget/remove_tracks/except_bone_transform': 'false',
        'retarget/remove_tracks/unimportant_positions': 'false',
        'retarget/remove_tracks/unmapped_bones': 'false',
    }
    body = ',\n'.join('"%s": %s' % (key, value) for key, value in options.items())
    subresources = '_subresources={\n"nodes": {\n"PATH:%s": {\n%s\n}\n}\n}' % (skeleton_path, body)
    uid_line = ''
    if os.path.exists(import_path):
        with open(import_path, encoding='utf-8') as handle:
            for line in handle:
                if line.startswith('uid='):
                    uid_line = line.strip() + '\n'
    text = ('[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n%s\n'
            '[params]\n\n'
            'nodes/root_type=""\nnodes/root_name=""\nnodes/apply_root_scale=true\nnodes/root_scale=1.0\n'
            'nodes/import_as_skeleton_bones=false\nmeshes/ensure_tangents=true\nmeshes/generate_lods=true\n'
            'meshes/create_shadow_meshes=true\nmeshes/light_baking=1\nskins/use_named_skins=true\n'
            'animation/import=true\nanimation/fps=30\nanimation/trimming=false\n'
            'animation/remove_immutable_tracks=true\nanimation/import_rest_as_RESET=false\n'
            'import_script/path=""\n%s\n'
            'gltf/naming_version=2\ngltf/embedded_image_handling=1\n' % (uid_line, subresources))
    old = None
    if os.path.exists(import_path):
        with open(import_path, encoding='utf-8') as handle:
            old = handle.read()
    # Godot rewrites the file after importing (adds deps and defaults); only replace it when our
    # retarget settings are missing, so re-running the tool does not force a reimport.
    if old is None or 'retarget/bone_map' not in old or bone_map not in old:
        with open(import_path, 'w', encoding='utf-8', newline='\n') as handle:
            handle.write(text)


if __name__ == '__main__':
    main()
