#
# :FIXME:
# - add error handling
# - needs testing!
#
import subprocess, pathlib

def module(*args):
        dir=pathlib.Path(__file__).parent
        modulecmd=pathlib.PurePath.joinpath(dir, '..', 'bin', 'modulecmd').resolve()
        if type(args[0]) == type([]):
                cmd = [modulecmd, 'python'] + args[0]
        else:
                cmd = [modulecmd, 'python'] + list(args)
        (output, error) = subprocess.Popen(cmd, stdout=subprocess.PIPE).communicate()
        exec(output)
