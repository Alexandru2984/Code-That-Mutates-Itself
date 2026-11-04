#!/usr/bin/env python3
"""Install only the selected crypt remote and its Drive dependency as a root credential.

No credential values are printed. The existing provider OAuth grant is unchanged.
"""
import argparse, configparser, os, pathlib, tempfile

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-config', required=True)
parser.add_argument('--output',default='/etc/evolving-minds/backup-rclone.conf')
args=parser.parse_args()
if os.geteuid()!=0:parser.error('Run as root to protect the backup credential')
source=configparser.ConfigParser(interpolation=None)
if not source.read(args.source_config):parser.error('Source configuration unavailable')
name='gdrive-vps-crypt'
if name not in source or source[name].get('type')!='crypt':parser.error('Expected the configured crypt remote')
if source[name].getboolean('no_data_encryption',fallback=False):parser.error('Remote must encrypt file contents')
if not source[name].get('password'):parser.error('Crypt encryption key is missing')
base=source[name].get('remote','').split(':',1)[0]
if base not in source or source[base].get('type')!='drive':parser.error('Crypt remote must use the existing Drive backend')
subset=configparser.ConfigParser(interpolation=None)
for section in [base,name]:subset[section]=dict(source[section])
path=pathlib.Path(args.output)
fd,tmp=tempfile.mkstemp(prefix='.offsite-credential-',dir=path.parent)
try:
    os.fchmod(fd,0o600)
    with os.fdopen(fd,'w') as handle:
        subset.write(handle);handle.flush();os.fsync(handle.fileno())
    os.replace(tmp,path)
except BaseException:
    if os.path.exists(tmp):os.unlink(tmp)
    raise
print('Installed a private two-section crypt/Drive credential; no other remotes copied.')
