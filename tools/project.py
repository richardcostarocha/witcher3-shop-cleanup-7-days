from pathlib import Path
import argparse, hashlib, json, re, shutil
ROOT=Path(__file__).resolve().parents[1]
def manifest(root):
    return {p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
def verify():
    project=json.loads((ROOT/'project.json').read_text('utf-8'))
    assert manifest(ROOT/'mods')==json.loads((ROOT/'manifest.json').read_text('utf-8')), 'Review edits, then run refresh-manifest.'
    content=ROOT/'mods'/project['mod_directory']/'content'
    info=json.loads((content/'info.json').read_text('utf-8-sig'))
    assert info['name']==project['mod_directory'] and info['version']==project['version'] and info['workshopId']==project['workshop_id']
    assert info['useLooseScripts'] and info['dependencies']==[]
    for p in content.rglob('*.ws'):
        text=re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'','',p.read_text('utf-8-sig'),flags=re.S)
        stack=[]
        for c in text:
            if c in '{([': stack.append(c)
            elif c in '})]': assert stack and stack.pop()=={'}':'{',')':'(',']':'['}[c],p
        assert not stack,p
    print(project['mod_directory'],project['version'],': release files verified')
    return project
def build(destination):
    project=verify();out=Path(destination).resolve() if destination else ROOT/'dist'/('v'+project['version'])
    assert out!=ROOT and not out.exists() and not out.is_relative_to(ROOT/'mods'),'Choose a new output directory outside mods/.'
    shutil.copytree(ROOT/'mods',out/'workshop/mods')
    fields={'appid':'292030','publishedfileid':str(project['workshop_id']),'contentfolder':str(out/'workshop'),'changenote':(ROOT/'CHANGELOG.md').read_text('utf-8')}
    def quote(value):return '"'+value.replace('\\','\\\\').replace('"','\\"')+'"'
    vdf='"workshopitem"\n{\n'+''.join('    '+quote(k)+' '+quote(v)+'\n' for k,v in fields.items())+'}\n'
    (out/'steam-upload.vdf').write_text(vdf,encoding='utf-8',newline='\n')
    print('Package prepared:',out,'; no installation or upload performed.')
if __name__=='__main__':
    parser=argparse.ArgumentParser(description='Verify/package this mod without installing or uploading it.')
    parser.add_argument('command',choices=['verify','build','refresh-manifest']);parser.add_argument('--out');args=parser.parse_args()
    if args.command=='verify':verify()
    elif args.command=='build':build(args.out)
    else:
        (ROOT/'manifest.json').write_text(json.dumps(manifest(ROOT/'mods'),indent=2)+'\n',encoding='utf-8',newline='\n')
        print('Manifest refreshed. Review the diff and run tests.')
