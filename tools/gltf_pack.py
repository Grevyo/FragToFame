"""Small glTF 2.0 reader/writer used by the asset import tools (developer tools, never shipped).

It reads .gltf (external or data-URI buffers) and .glb files, can keep a subset of a file's nodes
(with the meshes, skins, materials, textures and animations they use) and writes a compact .glb
holding only the bytes that subset needs. Images can be embedded or left as external files, so
several models can share one texture file instead of each carrying its own copy.

Only what the character packs use is supported: no sparse accessors, no KHR extensions that
reference extra indices, and one output buffer.
"""
import base64
import copy
import hashlib
import json
import os
import struct

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


class Gltf:
    """A parsed glTF document with its buffers loaded into memory."""

    def __init__(self, document, buffers, base_dir=''):
        self.doc = document
        self.buffers = buffers
        self.base_dir = base_dir

    @staticmethod
    def from_bytes(data, name, base_dir='', read_file=None):
        """Parses .glb or .gltf bytes. read_file(relative_uri) supplies external buffers."""
        glb_bin = None
        if name.lower().endswith('.glb'):
            magic, _version, _length = struct.unpack_from('<III', data, 0)
            if magic != GLB_MAGIC:
                raise ValueError('%s is not a GLB file' % name)
            offset = 12
            document = None
            while offset < len(data):
                chunk_length, chunk_type = struct.unpack_from('<II', data, offset)
                chunk = data[offset + 8:offset + 8 + chunk_length]
                if chunk_type == CHUNK_JSON:
                    document = json.loads(chunk.decode('utf-8'))
                elif chunk_type == CHUNK_BIN:
                    glb_bin = bytes(chunk)
                offset += 8 + chunk_length
        else:
            document = json.loads(data.decode('utf-8'))
        buffers = []
        for buffer in document.get('buffers', []):
            uri = buffer.get('uri')
            if uri is None:
                buffers.append(glb_bin)
            elif uri.startswith('data:'):
                buffers.append(base64.b64decode(uri.split(',', 1)[1]))
            else:
                buffers.append(read_file(uri))
        return Gltf(document, buffers, base_dir)

    # --- reading -------------------------------------------------------------------------------

    def view_bytes(self, view_index):
        view = self.doc['bufferViews'][view_index]
        start = view.get('byteOffset', 0)
        return self.buffers[view['buffer']][start:start + view['byteLength']]

    def image_bytes(self, image_index, read_file=None):
        image = self.doc['images'][image_index]
        if 'bufferView' in image:
            return self.view_bytes(image['bufferView'])
        uri = image['uri']
        if uri.startswith('data:'):
            return base64.b64decode(uri.split(',', 1)[1])
        return read_file(uri)

    def node_index(self, name):
        for index, node in enumerate(self.doc['nodes']):
            if node.get('name') == name:
                return index
        raise KeyError(name)

    def mesh_digest(self, mesh_index):
        """A hash of a mesh's geometry and material names (finds identical parts in two files)."""
        digest = hashlib.sha256()
        mesh = self.doc['meshes'][mesh_index]
        for primitive in mesh['primitives']:
            for key in sorted(primitive['attributes']):
                digest.update(key.encode())
                digest.update(self._accessor_bytes(primitive['attributes'][key]))
            if 'indices' in primitive:
                digest.update(self._accessor_bytes(primitive['indices']))
            if 'material' in primitive:
                digest.update(json.dumps(self.doc['materials'][primitive['material']], sort_keys=True).encode())
        return digest.hexdigest()

    def _accessor_bytes(self, accessor_index):
        accessor = self.doc['accessors'][accessor_index]
        data = self.view_bytes(accessor['bufferView'])
        return bytes(data[accessor.get('byteOffset', 0):]) + json.dumps(
            {k: accessor[k] for k in ('componentType', 'count', 'type')}).encode()

    # --- subsetting ----------------------------------------------------------------------------

    def subset(self, keep_nodes, keep_animations=False, external_images=None, keep_materials=None):
        """Returns a new Gltf holding only [keep_nodes] (indices) and what they use.

        external_images maps an image index to the file name it should reference instead of
        embedding its bytes (the caller writes that file once, next to the models).
        keep_materials, when given, is a set of material names: mesh primitives drawn with any
        other material are left out (e.g. a hat split off a head that was modelled with it).
        """
        external_images = external_images or {}
        src = self.doc

        def kept_primitives(mesh):
            if keep_materials is None:
                return mesh['primitives']
            return [p for p in mesh['primitives']
                    if 'material' in p and src['materials'][p['material']].get('name') in keep_materials]
        keep = sorted(set(keep_nodes))
        node_map = {old: new for new, old in enumerate(keep)}
        out = {'asset': copy.deepcopy(src.get('asset', {'version': '2.0'}))}
        out['asset']['generator'] = 'F2F gltf_pack (from %s)' % src.get('asset', {}).get('generator', 'unknown')

        mesh_map, skin_map = {}, {}
        for old in keep:
            node = src['nodes'][old]
            if 'mesh' in node and node['mesh'] not in mesh_map:
                mesh_map[node['mesh']] = len(mesh_map)
            if 'skin' in node and node['skin'] not in skin_map:
                skin_map[node['skin']] = len(skin_map)
        # A skin is kept even when no kept mesh uses it if its joints are kept (animation files).
        for skin_index, skin in enumerate(src.get('skins', [])):
            if skin_index not in skin_map and all(j in node_map for j in skin['joints']):
                skin_map[skin_index] = len(skin_map)

        material_map = {}
        for old_mesh in mesh_map:
            for primitive in kept_primitives(src['meshes'][old_mesh]):
                if 'material' in primitive and primitive['material'] not in material_map:
                    material_map[primitive['material']] = len(material_map)
        texture_map = {}
        for old_material in material_map:
            for texture_index in _material_textures(src['materials'][old_material]):
                if texture_index not in texture_map:
                    texture_map[texture_index] = len(texture_map)
        image_map, sampler_map = {}, {}
        for old_texture in texture_map:
            texture = src['textures'][old_texture]
            if 'source' in texture and texture['source'] not in image_map:
                image_map[texture['source']] = len(image_map)
            if 'sampler' in texture and texture['sampler'] not in sampler_map:
                sampler_map[texture['sampler']] = len(sampler_map)

        writer = _BufferWriter(self)
        nodes = []
        for old in keep:
            node = copy.deepcopy(src['nodes'][old])
            node['children'] = [node_map[c] for c in node.get('children', []) if c in node_map]
            if not node['children']:
                del node['children']
            if 'mesh' in node:
                node['mesh'] = mesh_map[node['mesh']]
            if 'skin' in node:
                node['skin'] = skin_map[node['skin']]
            node.pop('camera', None)
            nodes.append(node)
        out['nodes'] = nodes
        scene = copy.deepcopy(src['scenes'][src.get('scene', 0)])
        scene['nodes'] = [node_map[n] for n in scene['nodes'] if n in node_map]
        # Children of a removed root become roots so nothing kept is orphaned.
        parents = {c for n in nodes for c in n.get('children', [])}
        for new_index in range(len(nodes)):
            if new_index not in parents and new_index not in scene['nodes']:
                scene['nodes'].append(new_index)
        out['scenes'] = [scene]
        out['scene'] = 0

        meshes = [None] * len(mesh_map)
        for old, new in mesh_map.items():
            mesh = copy.deepcopy(src['meshes'][old])
            mesh['primitives'] = copy.deepcopy(kept_primitives(src['meshes'][old]))
            for primitive in mesh['primitives']:
                primitive['attributes'] = {k: writer.accessor(v) for k, v in primitive['attributes'].items()}
                if 'indices' in primitive:
                    primitive['indices'] = writer.accessor(primitive['indices'])
                if 'material' in primitive:
                    primitive['material'] = material_map[primitive['material']]
                if 'targets' in primitive:
                    primitive['targets'] = [{k: writer.accessor(v) for k, v in t.items()} for t in primitive['targets']]
            meshes[new] = mesh
        if meshes:
            out['meshes'] = meshes
        skins = [None] * len(skin_map)
        for old, new in skin_map.items():
            skin = copy.deepcopy(src['skins'][old])
            skin['joints'] = [node_map[j] for j in skin['joints']]
            if 'skeleton' in skin:
                if skin['skeleton'] in node_map:
                    skin['skeleton'] = node_map[skin['skeleton']]
                else:
                    del skin['skeleton']
            if 'inverseBindMatrices' in skin:
                skin['inverseBindMatrices'] = writer.accessor(skin['inverseBindMatrices'])
            skins[new] = skin
        if skins:
            out['skins'] = skins
        materials = [None] * len(material_map)
        for old, new in material_map.items():
            material = copy.deepcopy(src['materials'][old])
            _remap_material_textures(material, texture_map)
            materials[new] = material
        if materials:
            out['materials'] = materials
        textures = [None] * len(texture_map)
        for old, new in texture_map.items():
            texture = copy.deepcopy(src['textures'][old])
            if 'source' in texture:
                texture['source'] = image_map[texture['source']]
            if 'sampler' in texture:
                texture['sampler'] = sampler_map[texture['sampler']]
            textures[new] = texture
        if textures:
            out['textures'] = textures
        samplers = [None] * len(sampler_map)
        for old, new in sampler_map.items():
            samplers[new] = copy.deepcopy(src['samplers'][old])
        if samplers:
            out['samplers'] = samplers
        images = [None] * len(image_map)
        for old, new in image_map.items():
            image = copy.deepcopy(src['images'][old])
            if old in external_images:
                image.pop('bufferView', None)
                image['uri'] = external_images[old]
                image['mimeType'] = 'image/png'
            elif 'bufferView' in image:
                image['bufferView'] = writer.raw_view(self.view_bytes(image['bufferView']))
            images[new] = image
        if images:
            out['images'] = images

        if keep_animations:
            animations = []
            for animation in src.get('animations', []):
                channels, samplers_out, sampler_remap = [], [], {}
                for channel in animation['channels']:
                    target = channel['target']
                    if target.get('node') not in node_map:
                        continue
                    if channel['sampler'] not in sampler_remap:
                        sampler = copy.deepcopy(animation['samplers'][channel['sampler']])
                        sampler['input'] = writer.accessor(sampler['input'])
                        sampler['output'] = writer.accessor(sampler['output'])
                        sampler_remap[channel['sampler']] = len(samplers_out)
                        samplers_out.append(sampler)
                    channel = copy.deepcopy(channel)
                    channel['sampler'] = sampler_remap[channel['sampler']]
                    channel['target']['node'] = node_map[target['node']]
                    channels.append(channel)
                if channels:
                    animations.append({'name': animation.get('name', ''), 'channels': channels, 'samplers': samplers_out})
            if animations:
                out['animations'] = animations

        out['accessors'] = writer.accessors
        out['bufferViews'] = writer.views
        data = bytes(writer.data)
        out['buffers'] = [{'byteLength': len(data)}]
        for key in ('extensionsUsed', 'extensionsRequired'):
            if key in src:
                out[key] = copy.deepcopy(src[key])
        return Gltf(out, [data])

    # --- writing -------------------------------------------------------------------------------

    def glb_bytes(self):
        document = json.dumps(self.doc, separators=(',', ':'), sort_keys=True).encode('utf-8')
        document += b' ' * ((4 - len(document) % 4) % 4)
        data = self.buffers[0] if self.buffers else b''
        data += b'\0' * ((4 - len(data) % 4) % 4)
        total = 12 + 8 + len(document) + (8 + len(data) if data else 0)
        out = struct.pack('<III', GLB_MAGIC, 2, total)
        out += struct.pack('<II', len(document), CHUNK_JSON) + document
        if data:
            out += struct.pack('<II', len(data), CHUNK_BIN) + data
        return out


class _BufferWriter:
    """Copies the accessors a subset uses into one new buffer (one view per accessor)."""

    def __init__(self, source):
        self.source = source
        self.data = bytearray()
        self.views = []
        self.accessors = []
        self._accessor_map = {}

    def _align(self):
        while len(self.data) % 4:
            self.data.append(0)

    def raw_view(self, data, stride=None, target=None):
        self._align()
        view = {'buffer': 0, 'byteOffset': len(self.data), 'byteLength': len(data)}
        if stride:
            view['byteStride'] = stride
        if target:
            view['target'] = target
        self.data.extend(data)
        self.views.append(view)
        return len(self.views) - 1

    def accessor(self, old_index):
        if old_index in self._accessor_map:
            return self._accessor_map[old_index]
        accessor = copy.deepcopy(self.source.doc['accessors'][old_index])
        if 'sparse' in accessor:
            raise ValueError('sparse accessors are not supported')
        view = self.source.doc['bufferViews'][accessor['bufferView']]
        element = _COMPONENT_SIZE[accessor['componentType']] * _TYPE_COUNT[accessor['type']]
        stride = view.get('byteStride', 0) or element
        start = accessor.get('byteOffset', 0)
        length = stride * (accessor['count'] - 1) + element
        chunk = self.source.view_bytes(accessor['bufferView'])[start:start + length]
        accessor['bufferView'] = self.raw_view(chunk, view.get('byteStride'), view.get('target'))
        accessor['byteOffset'] = 0
        self.accessors.append(accessor)
        self._accessor_map[old_index] = len(self.accessors) - 1
        return self._accessor_map[old_index]


_COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
_TYPE_COUNT = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT2': 4, 'MAT3': 9, 'MAT4': 16}


def _texture_refs(material):
    """Yields every texture-info dictionary in a material."""
    pbr = material.get('pbrMetallicRoughness', {})
    for key in ('baseColorTexture', 'metallicRoughnessTexture'):
        if key in pbr:
            yield pbr[key]
    for key in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
        if key in material:
            yield material[key]


def _material_textures(material):
    return [ref['index'] for ref in _texture_refs(material)]


def _remap_material_textures(material, texture_map):
    for ref in _texture_refs(material):
        ref['index'] = texture_map[ref['index']]


def write_file(path, data):
    """Writes bytes only when they differ, so re-running a tool does not trigger reimports."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        with open(path, 'rb') as handle:
            if handle.read() == data:
                return False
    with open(path, 'wb') as handle:
        handle.write(data)
    return True
