"""Copies the weapon, Coat-kit and Magnet source assets into the project.

Sources (never modified):
  C:/GrevCo/Guns                       weapon models, Coat templates and simplified Coat kits
  C:/GrevCo/Magnets                    Magnet artwork (512 x 512 RGBA PNG, one Magnet per file)

Destinations inside the project:
  assets/weapons/<weapon_id>/model.glb     the model whose UVs match the weapon's Coat kit
  assets/weapons/<weapon_id>/zones/*.png   the kit's paint-zone masks (runtime data for Coats)
  assets/magnets/<magnet_id>.png           Magnet artwork
  authoring/coat_kits/<Kit>/...            the kits and templates for artists (not in builds;
                                           the folder has a .gdignore so Godot never imports it)

Run:  python tools/import_weapon_assets.py
Re-running is safe: files are only copied when missing or different.
"""
import filecmp
import os
import shutil
import sys

GUNS = 'C:/GrevCo/Guns'
MAGNETS = 'C:/GrevCo/Magnets'
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# weapon_id: (kit folder name, model path relative to GUNS) — the model named by each kit's
# Which_Model.txt, i.e. the one whose UV layout the kit's textures and masks were made for.
WEAPONS = {
    'wpn_ak47': ('AK-47', 'AK47.glb'),
    'wpn_m4a1': ('M4A1', 'Coats/Simplified_Coat_Kits/M4A1/M4A1_Independent_Paint.glb'),
    'wpn_desert_eagle': ('Desert-Eagle', 'Coats/Coat_Templates/Desert-Eagle/Coat_Ready.glb'),
    'wpn_g17': ('G17', 'Coats/Coat_Templates/G17/Coat_Ready.glb'),
    'wpn_m1911': ('M1911', 'Coats/Coat_Templates/M1911/Coat_Ready.glb'),
    'wpn_mk23': ('Mk23-SOCOM', 'Coats/Coat_Templates/Mk23-SOCOM/Coat_Ready.glb'),
    'wpn_l118a1': ('L118A1', 'Coats/Coat_Templates/L118A1/Coat_Ready.glb'),
    'wpn_m24': ('M24', 'Coats/Coat_Templates/M24/Coat_Ready.glb'),
    'wpn_sks': ('SKS', 'russian_sks.glb'),
    'wpn_m14_ebr': ('M14-EBR', 'Coats/Coat_Templates/M14-EBR/Coat_Ready.glb'),
}
SKIP_IN_AUTHORING = ('.glb',)  # Models live once, under assets/weapons.


def copy(source, target):
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.exists(target) and filecmp.cmp(source, target, shallow=False):
        return 0
    shutil.copyfile(source, target)
    return 1


def main():
    copied = 0
    for weapon_id, (kit, model) in WEAPONS.items():
        copied += copy(f'{GUNS}/{model}', f'{PROJECT}/assets/weapons/{weapon_id}/model.glb')
        masks = f'{GUNS}/Coats/Simplified_Coat_Kits/{kit}/Masks'
        for name in sorted(os.listdir(masks)):
            copied += copy(f'{masks}/{name}', f'{PROJECT}/assets/weapons/{weapon_id}/zones/{name.lower()}')
        for folder, label in (('Simplified_Coat_Kits', 'simplified'), ('Coat_Templates', 'full_template')):
            root = f'{GUNS}/Coats/{folder}/{kit}'
            for base, _dirs, files in os.walk(root):
                for name in files:
                    if name.lower().endswith(SKIP_IN_AUTHORING):
                        continue
                    relative = os.path.relpath(os.path.join(base, name), root)
                    copied += copy(os.path.join(base, name), f'{PROJECT}/authoring/coat_kits/{kit}/{label}/{relative}')
    for name, target in (('Simplified_Coat_Kits/READ_FIRST.txt', 'READ_FIRST_simplified.txt'),
                         ('Coat_Templates/START_HERE.txt', 'START_HERE_full_template.txt')):
        copied += copy(f'{GUNS}/Coats/{name}', f'{PROJECT}/authoring/coat_kits/{target}')
    open(f'{PROJECT}/authoring/.gdignore', 'a').close()
    magnets = 0
    for name in sorted(os.listdir(MAGNETS)):
        if name.lower().endswith('.png'):
            magnet_id = 'mag_' + name[:-4].replace('magnet-', '').replace('-', '_')
            copied += copy(f'{MAGNETS}/{name}', f'{PROJECT}/assets/magnets/{magnet_id}.png')
            magnets += 1
    print(f'{len(WEAPONS)} weapons, {magnets} magnets, {copied} file(s) copied or updated')
    return 0


if __name__ == '__main__':
    sys.exit(main())
