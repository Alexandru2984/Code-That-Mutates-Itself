#!/usr/bin/env python3
"""Fetch and verify the latest encrypted backup into a NEW local snapshot file.

Does not stop services or overwrite production data. Run as the offsite service UID.
"""
import argparse, gzip, hashlib, json, os, pathlib, re, subprocess, tempfile

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config',default='/var/lib/evolving-minds-offsite/rclone.conf')
parser.add_argument('--output',required=True)
args=parser.parse_args()
output=pathlib.Path(args.output)
if output.exists() or output.is_symlink():parser.error('Output must be a new file; no existing snapshot is overwritten')
config=pathlib.Path(args.config)
remote='gdrive-vps-crypt:apps/elixir.micutu.com'

def fetch(name,target):
    command=['/usr/bin/rclone','--config',str(config),'--log-level','ERROR',
             '--log-file',str(config.parent/'recovery-rclone.log'),'--max-transfer','8Mi',
             '--cutoff-mode','hard','--contimeout','10s','--timeout','30s',
             'copyto',remote+'/'+name,str(target)]
    try:subprocess.run(command,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=90)
    except (subprocess.SubprocessError,OSError):raise SystemExit('Encrypted backup fetch failed; inspect the private recovery log')

with tempfile.TemporaryDirectory(prefix='.recovery-',dir=output.parent) as temporary:
    directory=pathlib.Path(temporary)
    fetch('latest.json',directory/'latest.json')
    if (directory/'latest.json').stat().st_size>4096:raise SystemExit('Invalid manifest size')
    manifest=json.loads((directory/'latest.json').read_text())
    name=manifest.get('archive','');digest=manifest.get('sha256','');size=manifest.get('bytes',0)
    if (manifest.get('version')!=1 or not isinstance(name,str) or
        not re.fullmatch(r'world-\d{4}-\d{2}-\d{2}T\d{6}(?:\.\d+)?Z\.snapshot\.gz',name) or
        not isinstance(digest,str) or not re.fullmatch(r'[a-f0-9]{64}',digest) or
        not isinstance(size,int) or not 0<size<=8_000_000):raise SystemExit('Invalid backup manifest')
    fetch(name,directory/'world.snapshot.gz')
    binary=(directory/'world.snapshot.gz').read_bytes()
    if len(binary)!=size or hashlib.sha256(binary).hexdigest()!=digest:raise SystemExit('Remote backup checksum mismatch')
    with gzip.open(directory/'world.snapshot.gz','rb') as handle:raw=handle.read(4_000_001)
    if not raw or len(raw)>4_000_000:raise SystemExit('Unexpected decompressed snapshot size')
    with open(os.open(output,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'wb') as handle:
        handle.write(raw);handle.flush();os.fsync(handle.fileno())
    print(json.dumps({'download_verified':True,'archive':name,'snapshot_bytes':len(raw)}))
