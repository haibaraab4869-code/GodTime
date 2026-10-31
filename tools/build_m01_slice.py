"""Compile only the approved M01 v3.1 slice; preserve all other region records."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def compile_m01(database):
    result = copy.deepcopy(database)
    zone = result['regions']['M01']
    zone['layout_version'] = 7
    rects = [[128, 0, 512, 448], [864, 224, 576, 448],
             [1696, 0, 448, 448], [128, 672, 512, 448],
             [864, 672, 576, 448]]
    floors = [448, 512, 448, 960, 1024]
    for room, rect, floor in zip(zone['rooms'], rects, floors):
        room.update(rect=rect, floor_y=floor, shape=0)
    for item in zone['interactions']:
        room = zone['rooms'][item['room']]
        item['at'][1] = room['floor_y'] - 20
        if item['id'] == 'mythic_1':
            item['at'][1] = room['floor_y'] - 228
        if item['id'].startswith('niche_'):
            item['at'] = [room['rect'][0] + room['rect'][2] - 48, room['floor_y'] - 20]
    zone['bounds'] = [0, 0, 2432, 1344]
    zone['mythic']['controls'] = [[1728, 428]]
    zone['mythic']['stations'] = [next(p['at'] for p in zone['interactions'] if p['id'] == f'mythic_{i}') for i in range(3)]
    structure = zone['structure']
    structure.update(skeleton=['hall', 'shaft', 'loop', 'niche'], tiers=['D1', 'D4'],
                     max_drop=512, depth_cue='cable', landings_max=1,
                     entry_tier='D1', exit_tier='D4',
                     terrain='渡桥与闸底双环：64px台地，512px明示深井；西侧根索返程。',
                     signature='固定镜头 + 首个单向落差', spikes={'open': 1, 'nail': 0},
                     pogo_halls=[], pogo_objects=[{'at': [544, 368], 'style': 'bell'}],
                     hazards=[{'id': 'open_0', 'kind': 'open', 'rect': [440, 948, 48, 12], 'era': 'both', 'hall': -1}],
                     connections=[{'link': 0, 'tier': 'D1', 'landings': 0, 'return_assist': False},
                                  {'link': 1, 'tier': 'D4', 'landings': 1, 'return_assist': True},
                                  {'link': 2, 'tier': 'D1', 'landings': 0, 'return_assist': False},
                                  {'link': 3, 'tier': 'D4', 'landings': 1, 'return_assist': False},
                                  {'link': 4, 'tier': 'D1', 'landings': 0, 'return_assist': False}])
    structure.pop('camera_teach', None)
    return result


def main():
    path = ROOT / 'game/data/world_regions.json'
    original = json.loads(path.read_text(encoding='utf-8'))
    compiled = compile_m01(original)
    assert all(original['regions'][key] == compiled['regions'][key] for key in original['regions'] if key != 'M01')
    path.write_text(json.dumps(compiled, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('OK M01: 5 rooms; other 47 regions unchanged')


if __name__ == '__main__':
    main()
