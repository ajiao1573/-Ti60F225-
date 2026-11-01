"""Build common anti-alias, reflected filters and guarded motion-aware voting."""
from pathlib import Path
import os,sys,runpy,shutil,tempfile
home=Path(os.environ.get('EFINITY_HOME',r'C:\Efinity\2026.1'))
# Tcl source paths must use forward slashes on Windows.
os.environ['EFINITY_HOME']=home.as_posix()
flow=sys.argv[1] if len(sys.argv)>1 else 'compile'
if flow not in ('compile','map','interface','pnr','pgm'):raise SystemExit('Unsupported flow')
os.environ.setdefault('PYTHONUTF8','1')
os.environ.setdefault('EFINITY_USER_DIR_INI',str(Path(os.environ['LOCALAPPDATA'])/'efinity/user_dir.ini'))
for var,folder in [('EFXPT_HOME','pt'),('EFXPGM_HOME','pgm'),('EFXIPM_HOME','ipm')]:
 os.environ[var]=Path(os.environ.get(var,str(home/folder))).as_posix()
handles=[os.add_dll_directory(str(home/d)) for d in ('bin','lib')]
project=Path.cwd()
# Interface Designer changes into its database and may create caches.
# Use a project-local runtime so the SDK installation stays read-only.
pt=project/'work/pt_runtime'
if not (pt/'.ready').exists():
 for folder in ('bin','db','pin_icon','sim_models'):
  shutil.copytree(home/'pt'/folder,pt/folder,dirs_exist_ok=True)
 (pt/'.ready').write_text(home.as_posix(),encoding='utf-8')
os.environ['EFXPT_HOME']=pt.as_posix()
staged=not str(project).isascii()
if staged:
 # Efinity's Windows reports mix UTF-8 and GBK for Chinese project paths.
 # Build an identical source snapshot at an ASCII temporary path, then
 # return all reports and bitstreams to the user's actual project.
 stage_base=Path.home()/'Documents'/'Codex'/'work'
 stage_base.mkdir(parents=True,exist_ok=True)
 build=Path(tempfile.mkdtemp(prefix='ti60_split_',dir=stage_base))
 if not str(build).isascii():raise RuntimeError('Efinity requires an ASCII TEMP directory')
 for directory in ('src','ip'):
  shutil.copytree(project/directory,build/directory)
 for source in project.iterdir():
  if source.is_file() and source.suffix.lower() in ('.v','.vh','.sv','.xml','.sdc','.json'):
   shutil.copy2(source,build/source.name)
 os.chdir(build)
 print('Building an unchanged source snapshot at an ASCII temporary path',flush=True)
sys.path.insert(0,str(home/'scripts'))
sys.argv=[str(home/'scripts/efx_run.py'),'Ti60_Demo.xml','--flow',flow,
          '--output_dir','output','--work_dir','work']
try:
 runpy.run_path(sys.argv[0],run_name='__main__')
finally:
 if staged:
  os.chdir(project)
  for directory in ('output','work'):
   if (build/directory).exists():shutil.copytree(build/directory,project/directory,dirs_exist_ok=True)
