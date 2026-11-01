"""Build an isolated Efinity project with explicit absolute source paths."""
from pathlib import Path
import xml.etree.ElementTree as ET
import sys
import hashlib
import json

root = Path(__file__).resolve().parents[1]
ns = 'http://www.efinixinc.com/enf_proj'
ET.register_namespace('efx', ns)
ET.register_namespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance')
tree = ET.parse(root/'Ti60_Demo.xml')
design = tree.find(f'{{{ns}}}design_info')
include_params=[e for e in tree.iter() if e.tag==f'{{{ns}}}param' and e.get('name')=='include']
if not any(e.get('value')=='src' for e in include_params):
    parent=next(parent for parent in tree.iter() if include_params[0] in list(parent))
    ET.SubElement(parent,f'{{{ns}}}param',name='include',value='src',value_type='e_string')
existing = {e.get('name') for e in design.findall(f'{{{ns}}}design_file')}
for source in sorted((root/'src/bean').glob('*.v')):
    name = source.relative_to(root).as_posix()
    if name not in existing:
        ET.SubElement(design, f'{{{ns}}}design_file', name=name, version='default', library='default')
# Efinity's project schema requires every design_file before top_vhdl_arch.
files = list(design.findall(f'{{{ns}}}design_file'))
for element in files:
    design.remove(element)
for index, element in enumerate(files, 1):
    design.insert(index, element)
if '--sync-source-list-only' in sys.argv:
    ET.indent(tree, space='    ')
    tree.write(root/'Ti60_Demo.xml',encoding='utf-8',xml_declaration=True)
    print('Updated canonical project source list for GUI builds.')
    raise SystemExit(0)
for element in tree.iter():
    tag = element.tag.rsplit('}', 1)[-1]
    attr = None
    # Keep SDC relative to the build working directory: the Windows Efinity
    # Tcl loader does not accept a drive-letter filename in this option.
    if tag in ('design_file','default_peri_file','peri_file'):
        attr = 'name'
    elif tag == 'ip':
        attr = 'path'
    elif tag == 'param' and element.get('name') == 'include':
        attr = 'value'
    if attr and element.get(attr):
        element.set(attr, (root/element.get(attr)).resolve().as_posix())
destination = root/'build/bean_project/Ti60_Demo.xml'
destination.parent.mkdir(parents=True, exist_ok=True)
ET.indent(tree, space='    ')
tree.write(destination, encoding='utf-8', xml_declaration=True)
inputs=[Path(e.get('name')) for e in design.findall(f'{{{ns}}}design_file')]
inputs += list((root/'src').rglob('*.v'))+list((root/'src').rglob('*.vh'))
inputs += list((root/'ip').glob('*/settings.json'))
inputs += [root/'Ti60_Demo.xml',root/'Ti60_Demo.peri.xml',root/'Ti60_Demo.pt.sdc']
hashes={str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
(destination.parent/'input_sha256.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
print('Prepared isolated project snapshot with all bean source files.')
