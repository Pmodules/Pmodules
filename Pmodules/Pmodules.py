import os, re, subprocess

def module(*args):
        os.environ['PMODULES_MODULEFILES_DIR']='modulefiles'
        pm_home=os.environ['PMODULES_HOME']
        os.environ['PMODULES_DIR']=pm_home
        modulecmd=os.path.join(pm_home, 'bin', 'modulecmd')
        if type(args[0]) == type([]):
                args = args[0]
        else:
                cmd = [modulecmd, 'python'] + list(args)
                (output, error) = subprocess.Popen(cmd, stdout=subprocess.PIPE).communicate()
        exec(output)
