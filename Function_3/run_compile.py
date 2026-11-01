import os,sys,runpy
home='C:/Efinity'
os.environ['EFINITY_HOME']=home
os.environ['EFXPT_HOME']=os.path.abspath('pt_runtime').replace(chr(92),'/')
os.environ['EFXPGM_HOME']=home+'/pgm'
os.environ['EFXIPM_HOME']=home+'/ipm'
os.environ['EFINITY_USER_DIR_INI']=os.path.join(os.environ['LOCALAPPDATA'],'efinity','user_dir.ini').replace(chr(92),'/')
os.environ['QT_PLUGIN_PATH']=home+'/python311'
handles=[os.add_dll_directory(home+'/'+p) for p in ('bin','lib')]
sys.path.insert(0,home+'/scripts')
sys.argv=[home+'/scripts/efx_run.py','Ti60_Demo.xml','--flow','compile','--output_dir','combined_output','--work_dir','combined_work']
runpy.run_path(sys.argv[0],run_name='__main__')
