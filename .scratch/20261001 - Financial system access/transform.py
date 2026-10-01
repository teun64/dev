"""
Administration (Subscription25__Administration__c) access: edit only via ps_miFinancialSystem_Admin.

usage: python3 transform.py <org>   (expects <org>/unpackaged/unpackaged/... from a metadata retrieve
                                     and fields_<org>.json from an EntityParticle query)
- ps_miSubscription25_User: Read + View All on the object, READ on every permissionable field.
- ps_Subscription25View, ps_miAPIPlatformIntegration, profile miDataAdministrator:
  object loses Create/Edit/Delete/Modify All (Read / View All kept), every Administration field read-only.
- writes ps_miFinancialSystem_Admin (Read/Edit/View All, edit on all editable fields) next to them.
Only Administration entries are touched; everything else in the files stays as retrieved.
"""
import json
import os
import sys
import xml.etree.ElementTree as ET

NS = 'http://soap.sforce.com/2006/04/metadata'
ET.register_namespace('', NS)
OBJ = 'Subscription25__Administration__c'
q = lambda tag: '{%s}%s' % (NS, tag)

org = sys.argv[1]
base = os.path.join(os.path.dirname(os.path.abspath(__file__)), org, 'unpackaged', 'unpackaged')
raw = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fields_%s.json' % org)).read()
particles = json.loads(raw[raw.index('{'):])['result']['records']
fields = sorted((p for p in particles if p['IsPermissionable']), key=lambda p: p['QualifiedApiName'])


def text(el, tag):
    c = el.find(q(tag))
    return c.text if c is not None else None


def set_child(el, tag, value):
    c = el.find(q(tag))
    if c is None:
        c = ET.SubElement(el, q(tag))
    c.text = value


def make_read_only(root):
    changes = 0
    for op in root.findall(q('objectPermissions')):
        if text(op, 'object') == OBJ:
            for tag in ('allowCreate', 'allowEdit', 'allowDelete', 'modifyAllRecords'):
                if text(op, tag) == 'true':
                    set_child(op, tag, 'false')
                    changes += 1
    for fp in root.findall(q('fieldPermissions')):
        if (text(fp, 'field') or '').startswith(OBJ + '.') and text(fp, 'editable') == 'true':
            set_child(fp, 'editable', 'false')
            changes += 1
    return changes


def grant_full_read(root):
    added = 0
    present = {text(fp, 'field') for fp in root.findall(q('fieldPermissions'))}
    for p in fields:
        name = OBJ + '.' + p['QualifiedApiName']
        if name in present:
            for fp in root.findall(q('fieldPermissions')):
                if text(fp, 'field') == name:
                    set_child(fp, 'readable', 'true')
            continue
        fp = ET.Element(q('fieldPermissions'))
        ET.SubElement(fp, q('editable')).text = 'false'
        ET.SubElement(fp, q('field')).text = name
        ET.SubElement(fp, q('readable')).text = 'true'
        # keep the schema order: insert directly after the last existing fieldPermissions
        children = list(root)
        last = max([i for i, c in enumerate(children) if c.tag == q('fieldPermissions')] or [-1])
        root.insert(last + 1, fp)
        added += 1
    for op in root.findall(q('objectPermissions')):
        if text(op, 'object') == OBJ:
            set_child(op, 'allowRead', 'true')
            set_child(op, 'viewAllRecords', 'true')
    return added


def write(tree, path):
    tree.write(path, xml_declaration=True, encoding='UTF-8')


for name, kind in (('ps_miSubscription25_User', 'permissionsets/%s.permissionset'),
                   ('ps_Subscription25View', 'permissionsets/%s.permissionset'),
                   ('ps_miAPIPlatformIntegration', 'permissionsets/%s.permissionset'),
                   ('miDataAdministrator', 'profiles/%s.profile')):
    path = os.path.join(base, kind % name)
    tree = ET.parse(path)
    root = tree.getroot()
    changed = make_read_only(root)
    added = grant_full_read(root) if name == 'ps_miSubscription25_User' else 0
    write(tree, path)
    print('%-30s %3d edit rights removed, %3d read fields added' % (name, changed, added))

# new permission set
ps = ET.Element(q('PermissionSet'))
ET.SubElement(ps, q('description')).text = (
    'Edit Subscription25 Administrations (financial system connection, rate-limit and document/payment settings). '
    'Other users have read access via ps_miSubscription25_User.')
for p in fields:
    fp = ET.SubElement(ps, q('fieldPermissions'))
    ET.SubElement(fp, q('editable')).text = 'true' if (p['IsUpdatable'] and not p['IsCalculated']) else 'false'
    ET.SubElement(fp, q('field')).text = OBJ + '.' + p['QualifiedApiName']
    ET.SubElement(fp, q('readable')).text = 'true'
ET.SubElement(ps, q('hasActivationRequired')).text = 'false'
ET.SubElement(ps, q('label')).text = 'miFinancialSystem_Admin (ps)'
op = ET.SubElement(ps, q('objectPermissions'))
for tag, val in (('allowCreate', 'false'), ('allowDelete', 'false'), ('allowEdit', 'true'), ('allowRead', 'true'),
                 ('modifyAllRecords', 'false'), ('object', OBJ), ('viewAllRecords', 'true')):
    ET.SubElement(op, q(tag)).text = val
os.makedirs(os.path.join(base, 'permissionsets'), exist_ok=True)
write(ET.ElementTree(ps), os.path.join(base, 'permissionsets', 'ps_miFinancialSystem_Admin.permissionset'))
print('ps_miFinancialSystem_Admin             %3d fields (%d editable)' % (
    len(fields), sum(1 for p in fields if p['IsUpdatable'] and not p['IsCalculated'])))
