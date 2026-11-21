"""Builds the knife models, their Coat zone masks and their Coat kits from the knife pack.

Source (never modified):
  C:/GrevCo/knifes/low_poly_knife_collection.glb
      "Low Poly Knife Collection" by BUttERflY_Bee, CC BY 4.0
      https://sketchfab.com/3d-models/low-poly-knife-collection-000c0c7c9ee740a28469e3c393ae133d

The pack is one file holding seven knives, each one mesh with its own 2048 x 2048 textures and a
clean UV layout (no overlapping islands). For every knife this script writes:

  assets/weapons/<knife_id>/model.glb        the knife alone, in its own mesh space (blade toward
                                             -X), textures embedded. The butterfly knife is split
                                             into three nodes - blade, handle_a, handle_b - each
                                             handle node placed on its pivot pin, so turning a
                                             handle node about its Z axis swings it like the real
                                             thing (WeaponVisual.set_part_angle).
  assets/weapons/<knife_id>/zones/*.png      paint-zone masks (white = the zone), runtime data
                                             for Coat composition, like the guns' kit masks.
  authoring/coat_kits/<Kit>/                 the Coat kit for artists (not in builds):
      Coat_BaseColor.png   the factory finish, the canvas to paint on
      Coat_Template.png    transparent guide: each zone tinted, every UV island outlined
      Start_Here.png       the factory finish with the zones tinted and a legend
      Masks/*.png          the zone masks again, for selecting a zone in an editor
      Parts.txt, README.txt, Which_Model.txt

Zones come from the mesh itself: every knife separates into connected parts, and the pack's
metallic map tells steel from grip, so each triangle is given a zone by a small rule per knife
(ZONE_RULES). Masks are the zone's UV triangles rasterised at texture size, grown a few pixels
into empty texture space so filtering never shows a seam.

Needs Python 3 with numpy and Pillow. Run:  python tools/import_knife_assets.py
Re-running is safe and gives the same files.
"""
import hashlib
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SOURCE = 'C:/GrevCo/knifes/low_poly_knife_collection.glb'
SOURCE_SHA256 = 'a2871f58de31df56839cd94c8eda3d7d6d98c29536587f671e839ddadf1aec80'
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 2048
GROW = 6  # pixels a mask grows into empty texture space

# Zone colours for guides (also listed in each kit's Parts.txt).
ZONE_COLOURS = [(105, 201, 250), (255, 155, 110), (125, 215, 169), (201, 163, 248)]


def _blade_metal(split):
    return lambda part, comp, cx: comp['metal'] > 128 and cx < split


# knife_id: (source mesh name, kit folder, [zone names], zone rule)
# A rule gets (part name, component stats, triangle centroid x) and returns a zone index, or -1
# to leave the triangle out of every zone (it stays factory finish).
KNIVES = {
    'knf_bayonet': ('Bayonet_knife_Bayonet_Knife_0', 'Bayonet', ['01_blade', '02_grip', '03_guard_and_pommel'],
        lambda part, c, cx: 0 if c['metal'] > 128 else (2 if c['xmax'] <= 0.0 or c['xmin'] >= 2.5 else 1)),
    'knf_butterfly': ('Butterfly_knife_Butterfly_Knife_0', 'Butterfly', ['01_blade', '02_handles', '03_hardware'],
        lambda part, c, cx: (0 if c['metal'] > 128 else 2) if part == 'blade'
            else (2 if c['metal'] > 128 or c['tris'] < 300 else 1)),
    'knf_combat': ('Combat_knife_Combat_Knife_0', 'Combat', ['01_blade', '02_grip', '03_guard_and_pommel'],
        lambda part, c, cx: 0 if c['metal'] > 128 else (1 if c['rgb'][1] > c['rgb'][0] * 1.3 else 2)),
    'knf_karambit': ('Krambit_knife_Krambit_Knife_0', 'Karambit', ['01_blade', '02_handle', '03_finger_ring'],
        lambda part, c, cx: (0 if c['xmax'] < 0.0 else 2) if c['metal'] > 128 else 1),
    'knf_nomad': ('Nomad_knife_Nomad_Knife_0', 'Nomad', ['01_blade', '02_handle', '03_bolsters'],
        lambda part, c, cx: 0 if c['xmax'] < 0.0 else (1 if c['tris'] > 500 else 2)),
    'knf_skeleton': ('Skeleton_knife_Skeleton_Knife_0', 'Skeleton', ['01_blade', '02_cord_wrap', '03_frame'],
        lambda part, c, cx: (0 if cx < 1.0 else 2) if c['metal'] > 128 else 1),
    'knf_t_dagger': ('T-handle_dagger_T_handle_dagger_Knife_0', 'T-Dagger', ['01_blade', '02_handle'],
        lambda part, c, cx: 0 if c['metal'] > 128 else 1),
}

COMP = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


class Glb:
    def __init__(self, data):
        offset = 12
        chunks = []
        while offset < len(data):
            length, _kind = struct.unpack_from('<II', data, offset)
            chunks.append(data[offset + 8:offset + 8 + length])
            offset += 8 + length
        self.json = json.loads(chunks[0])
        self.bin = chunks[1]

    def view(self, index):
        view = self.json['bufferViews'][index]
        start = view.get('byteOffset', 0)
        return self.bin[start:start + view['byteLength']]

    def accessor(self, index):
        acc = self.json['accessors'][index]
        view = self.json['bufferViews'][acc['bufferView']]
        dtype = np.dtype(COMP[acc['componentType']])
        width = WIDTH[acc['type']]
        start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
        stride = view.get('byteStride', dtype.itemsize * width)
        rows = [np.frombuffer(self.bin, dtype=dtype, count=width, offset=start + i * stride) for i in range(acc['count'])]
        return np.array(rows, dtype=dtype).reshape(acc['count'], width)

    def image(self, texture_index):
        source = self.json['textures'][texture_index]['source']
        return self.view(self.json['images'][source]['bufferView'])


def components(positions, triangles):
    """Connected parts: triangles sharing a vertex position belong together."""
    first = {}
    rep = np.array([first.setdefault(tuple(np.round(v, 4)), i) for i, v in enumerate(positions)])
    parent = list(range(len(positions)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for tri in triangles:
        a = find(rep[tri[0]])
        for k in tri[1:]:
            b = find(rep[k])
            if a != b:
                parent[b] = a
    return np.array([find(rep[tri[0]]) for tri in triangles])


def butterfly_parts(positions, triangles, roots, comp):
    """Splits the butterfly knife into blade and two handles; returns (part per triangle, pivots)."""
    big = sorted({r for r in comp if comp[r]['tris'] >= 500}, key=lambda r: -comp[r]['ymax'])
    handle_a = [r for r in big if comp[r]['tris'] == comp[big[0]]['tris']]
    handle_b = [r for r in big if r not in handle_a]
    blade = [r for r in comp if comp[r]['metal'] > 128 and comp[r]['xmax'] < 1.0 and comp[r]['tris'] > 200]
    groups = {'blade': blade, 'handle_a': handle_a, 'handle_b': handle_b}
    points = {name: np.concatenate([comp[r]['points'] for r in rs]) for name, rs in groups.items()}
    owner = {}
    for name, rs in groups.items():
        for r in rs:
            owner[r] = name
    pins = {}
    for r in comp:
        if r in owner:
            continue
        pts = comp[r]['points']
        nearest = min(points, key=lambda name: np.min(np.linalg.norm(points[name][:, None, :] - pts[None, :, :], axis=2)))
        owner[r] = nearest
        # The pivot bushings: small steel rings on a handle, near the blade's tang.
        if comp[r]['metal'] > 128 and nearest != 'blade' and comp[r]['xmax'] < 0.0:
            pins.setdefault(nearest, []).append(pts)
    pivots = {}
    for name, sets in pins.items():
        centre = np.concatenate(sets).mean(0)
        pivots[name] = np.array([centre[0], centre[1], 0.0], dtype=np.float32)
    parts = np.array([owner[r] for r in roots])
    return parts, pivots


def tangent_frame(glb, primitive, key):
    attrs = primitive['attributes']
    return glb.accessor(attrs[key]).astype(np.float32) if key in attrs else None


class GlbWriter:
    def __init__(self):
        self.bin = bytearray()
        self.views = []
        self.accessors = []

    def _view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        view = {'buffer': 0, 'byteOffset': len(self.bin), 'byteLength': len(data)}
        if target:
            view['target'] = target
        self.bin.extend(data)
        self.views.append(view)
        return len(self.views) - 1

    def accessor(self, array, kind, component, target, bounds=False):
        view = self._view(array.tobytes(), target)
        acc = {'bufferView': view, 'componentType': component, 'count': len(array), 'type': kind}
        if bounds:
            acc['min'] = [float(v) for v in array.min(0)]
            acc['max'] = [float(v) for v in array.max(0)]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def image(self, png):
        return self._view(png)

    def finish(self, document):
        document['bufferViews'] = self.views
        document['accessors'] = self.accessors
        while len(self.bin) % 4:
            self.bin.append(0)
        document['buffers'] = [{'byteLength': len(self.bin)}]
        text = json.dumps(document, separators=(',', ':')).encode()
        text += b' ' * ((4 - len(text) % 4) % 4)
        total = 12 + 8 + len(text) + 8 + len(self.bin)
        return (struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(text), 0x4E4F534A) + text
                + struct.pack('<II', len(self.bin), 0x004E4942) + bytes(self.bin))


def write_model(glb, primitive, material, parts, part_names, pivots, path):
    attrs = primitive['attributes']
    positions = glb.accessor(attrs['POSITION']).astype(np.float32)
    normals = glb.accessor(attrs['NORMAL']).astype(np.float32)
    uvs = glb.accessor(attrs['TEXCOORD_0']).astype(np.float32)
    tangents = tangent_frame(glb, primitive, 'TANGENT')
    triangles = glb.accessor(primitive['indices']).reshape(-1, 3)
    writer = GlbWriter()
    images, textures = [], []
    new_material = {'name': material['name'], 'doubleSided': True, 'pbrMetallicRoughness': {}}
    for slot, ref in (('baseColorTexture', material['pbrMetallicRoughness'].get('baseColorTexture')),
                      ('metallicRoughnessTexture', material['pbrMetallicRoughness'].get('metallicRoughnessTexture')),
                      ('normalTexture', material.get('normalTexture'))):
        if ref is None:
            continue
        images.append({'bufferView': writer.image(glb.image(ref['index'])), 'mimeType': 'image/png',
                       'name': '%s_%s' % (material['name'], slot.replace('Texture', ''))})
        textures.append({'source': len(images) - 1, 'sampler': 0})
        if slot == 'normalTexture':
            new_material['normalTexture'] = {'index': len(textures) - 1}
        else:
            new_material['pbrMetallicRoughness'][slot] = {'index': len(textures) - 1}
    meshes, nodes = [], []
    for name in part_names:
        picked = triangles[parts == name]
        used, remap = np.unique(picked.ravel(), return_inverse=True)
        offset = pivots.get(name, np.zeros(3, np.float32))
        attributes = {
            'POSITION': writer.accessor(positions[used] - offset, 'VEC3', 5126, 34962, bounds=True),
            'NORMAL': writer.accessor(normals[used], 'VEC3', 5126, 34962),
            'TEXCOORD_0': writer.accessor(uvs[used], 'VEC2', 5126, 34962),
        }
        if tangents is not None:
            attributes['TANGENT'] = writer.accessor(tangents[used], 'VEC4', 5126, 34962)
        indices = writer.accessor(remap.astype(np.uint32), 'SCALAR', 5125, 34963)
        meshes.append({'name': name, 'primitives': [{'attributes': attributes, 'indices': indices, 'material': 0}]})
        node = {'name': name, 'mesh': len(meshes) - 1}
        if name in pivots:
            node['translation'] = [float(v) for v in offset]
        nodes.append(node)
    document = {
        'asset': {'version': '2.0', 'generator': 'F2F tools/import_knife_assets.py',
                  'extras': glb.json['asset'].get('extras', {})},
        'scene': 0,
        'scenes': [{'nodes': [len(nodes)]}],
        'nodes': nodes + [{'name': 'Knife', 'children': list(range(len(nodes)))}],
        'meshes': meshes,
        'materials': [new_material],
        'textures': textures,
        'images': images,
        'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
    }
    data = writer.finish(document)
    return save_bytes(path, data)


def save_bytes(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path) and open(path, 'rb').read() == data:
        return 0
    with open(path, 'wb') as handle:
        handle.write(data)
    return 1


def save_image(path, image):
    buffer = io.BytesIO()
    image.save(buffer, format='PNG', optimize=True)
    return save_bytes(path, buffer.getvalue())


def zone_masks(uvs, triangles, zones, count):
    """One L-mode mask per zone, grown into empty texture space only. Zones never share a pixel:
    where two zones meet inside one UV island, the edge pixels go to the lower-numbered zone."""
    raw = []
    claimed = np.zeros((SIZE, SIZE), bool)
    for zone in range(count):
        layer = Image.new('L', (SIZE, SIZE), 0)
        draw = ImageDraw.Draw(layer)
        for tri in triangles[zones == zone]:
            draw.polygon([(float(uvs[k][0]) * SIZE, float(uvs[k][1]) * SIZE) for k in tri], fill=255)
        mask = np.array(layer)
        mask[claimed] = 0
        claimed |= mask > 0
        raw.append(mask)
    covered = np.zeros((SIZE, SIZE), bool)
    for mask in raw:
        covered |= mask > 0
    grown = []
    taken = covered.copy()
    for mask in raw:
        wide = np.array(Image.fromarray(mask).filter(ImageFilter.MaxFilter(GROW * 2 + 1)))
        extra = (wide > 0) & ~taken
        taken |= extra
        grown.append(np.where((mask > 0) | extra, 255, 0).astype(np.uint8))
    return grown, raw


def wire(uvs, triangles, colour):
    layer = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for tri in triangles:
        pts = [(float(uvs[k][0]) * SIZE, float(uvs[k][1]) * SIZE) for k in tri]
        draw.line(pts + [pts[0]], fill=colour, width=1)
    return layer


def write_kit(knife_id, kit, zone_names, base_png, uvs, triangles, zones, masks, raw, model_path):
    root = f'{PROJECT}/authoring/coat_kits/{kit}'
    copied = save_bytes(f'{root}/Coat_BaseColor.png', base_png)
    base = Image.open(io.BytesIO(base_png)).convert('RGBA')
    template = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    preview = base.copy()
    for index, mask in enumerate(raw):
        colour = ZONE_COLOURS[index % len(ZONE_COLOURS)]
        tint = Image.new('RGBA', (SIZE, SIZE), colour + (255,))
        template.paste(Image.new('RGBA', (SIZE, SIZE), colour + (110,)), (0, 0), Image.fromarray(mask))
        preview = Image.composite(Image.blend(preview, tint, 0.45), preview, Image.fromarray(mask))
        copied += save_image(f'{root}/Masks/{zone_names[index]}.png', Image.fromarray(masks[index]))
    outline = wire(uvs, triangles, (20, 20, 20, 220))
    template = Image.alpha_composite(template, outline)
    copied += save_image(f'{root}/Coat_Template.png', template)
    preview = Image.alpha_composite(preview, wire(uvs, triangles, (255, 255, 255, 90)))
    strip = 60 + 40 * len(zone_names)
    sheet = Image.new('RGBA', (SIZE, SIZE + strip), (16, 16, 16, 255))
    sheet.paste(preview, (0, strip))
    draw = ImageDraw.Draw(sheet)
    draw.text((16, 12), f'{kit} Coat kit - {SIZE} x {SIZE}. Tinted areas take paint; everything else stays factory.',
              fill=(255, 255, 255, 255), font_size=24)
    for index, name in enumerate(zone_names):
        y = 48 + 40 * index
        draw.rectangle((16, y, 48, y + 28), fill=ZONE_COLOURS[index % len(ZONE_COLOURS)] + (255,))
        draw.text((60, y), f'Zone {index + 1}: {readable(name)}  (Masks/{name}.png)', fill=(255, 255, 255, 255), font_size=24)
    preview = sheet
    copied += save_image(f'{root}/Start_Here.png', preview.convert('RGB'))
    parts = [f'{kit} Coat kit | {SIZE} x {SIZE}', '']
    for index, name in enumerate(zone_names):
        r, g, b = ZONE_COLOURS[index % len(ZONE_COLOURS)]
        share = 100.0 * (raw[index] > 0).sum() / (SIZE * SIZE)
        parts.append(f'Zone {index + 1}: {readable(name)} | guide colour RGB ({r}, {g}, {b}) | {share:.1f}% of the texture')
    copied += save_bytes(f'{root}/Parts.txt', ('\n'.join(parts) + '\n').encode())
    readme = f"""FRAG TO FAME | {kit.upper()} KNIFE COAT KIT

1. Open Start_Here.png to see which part of the knife each zone covers (the texture is below
   the legend).
2. Open Coat_BaseColor.png (the factory finish) and add Coat_Template.png above it at 100%.
   The template tints each zone and outlines every UV island.
3. Paint on a new layer. To keep paint inside a zone, load the zone's mask from Masks/ as a
   selection (white = the zone). Areas outside every zone stay factory finish in the game.
4. Hide the template and export a {SIZE} x {SIZE} PNG. Import it in the Armoury with the
   {kit} knife selected.

The UV layout is the knife pack's own: each island is one face of one part, with no overlaps,
so artwork never repeats on another face. Islands are not joined across edges; for designs that
wrap round the blade, check your art on the knife in the Armoury preview.
"""
    copied += save_bytes(f'{root}/README.txt', readme.encode())
    digest = hashlib.sha256(open(model_path, 'rb').read()).hexdigest()
    which = f"""This kit fits the game model:
assets/weapons/{knife_id}/model.glb  (made by tools/import_knife_assets.py)

SHA-256: {digest}
Texture size: {SIZE} x {SIZE}
"""
    copied += save_bytes(f'{root}/Which_Model.txt', which.encode())
    return copied


def readable(zone_name):
    return zone_name[3:].replace('_', ' ').capitalize()


def main():
    data = open(SOURCE, 'rb').read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != SOURCE_SHA256:
        print(f'{SOURCE} is not the expected knife pack (SHA-256 {digest}); zone rules were written for {SOURCE_SHA256}.')
        return 1
    glb = Glb(data)
    meshes = {mesh['name']: mesh for mesh in glb.json['meshes']}
    copied = 0
    for knife_id, (mesh_name, kit, zone_names, rule) in KNIVES.items():
        primitive = meshes[mesh_name]['primitives'][0]
        material = glb.json['materials'][primitive['material']]
        positions = glb.accessor(primitive['attributes']['POSITION']).astype(np.float64)
        uvs = glb.accessor(primitive['attributes']['TEXCOORD_0']).astype(np.float64)
        triangles = glb.accessor(primitive['indices']).reshape(-1, 3)
        base_png = glb.image(material['pbrMetallicRoughness']['baseColorTexture']['index'])
        base = np.array(Image.open(io.BytesIO(base_png)).convert('RGB')).astype(float)
        mr = np.array(Image.open(io.BytesIO(glb.image(material['pbrMetallicRoughness']['metallicRoughnessTexture']['index'])))
                      .convert('RGB')).astype(float)
        centre_uv = uvs[triangles].mean(1)
        px = np.clip((centre_uv[:, 0] * SIZE).astype(int), 0, SIZE - 1)
        py = np.clip((centre_uv[:, 1] * SIZE).astype(int), 0, SIZE - 1)
        roots = components(positions, triangles)
        comp = {}
        for r in set(roots.tolist()):
            picked = roots == r
            pts = positions[triangles[picked].ravel()]
            comp[r] = {'tris': int(picked.sum()), 'xmin': pts[:, 0].min(), 'xmax': pts[:, 0].max(),
                       'ymax': pts[:, 1].max(), 'metal': mr[py[picked], px[picked], 2].mean(),
                       'rgb': base[py[picked], px[picked]].mean(0), 'points': np.unique(pts, axis=0)}
        if knife_id == 'knf_butterfly':
            parts, pivots = butterfly_parts(positions, triangles, roots, comp)
            part_names = ['blade', 'handle_a', 'handle_b']
        else:
            parts, pivots = np.array(['knife'] * len(triangles)), {}
            part_names = ['knife']
        centre_x = positions[triangles].mean(1)[:, 0]
        zones = np.array([rule(parts[i], comp[roots[i]], centre_x[i]) for i in range(len(triangles))])
        model_path = f'{PROJECT}/assets/weapons/{knife_id}/model.glb'
        copied += write_model(glb, primitive, material, parts, part_names, pivots, model_path)
        masks, raw = zone_masks(uvs, triangles, zones, len(zone_names))
        for index, name in enumerate(zone_names):
            copied += save_image(f'{PROJECT}/assets/weapons/{knife_id}/zones/{name}.png', Image.fromarray(masks[index]))
        copied += write_kit(knife_id, kit, zone_names, base_png, uvs, triangles, zones, masks, raw, model_path)
        counts = ', '.join(f'{name} {int((zones == i).sum())}' for i, name in enumerate(zone_names))
        extra = '  pivots ' + ', '.join(f'{k} {np.round(v, 3).tolist()}' for k, v in pivots.items()) if pivots else ''
        print(f'{knife_id}: {len(triangles)} triangles ({counts}){extra}')
    open(f'{PROJECT}/authoring/.gdignore', 'a').close()
    print(f'{len(KNIVES)} knives, {copied} file(s) written or updated')
    return 0


if __name__ == '__main__':
    sys.exit(main())
