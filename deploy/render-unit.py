#!/usr/bin/env python3
"""Render this installation's systemd units without loading runtime secrets."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
for name in ['template', 'output', 'repo-root', 'app-dir', 'env-file', 'user', 'group']:
    parser.add_argument('--' + name, required=True)
parser.add_argument('--backup-dir', default='/srv/backups/evolving-minds')
args = parser.parse_args()
for name in ['user', 'group']:
    if not re.fullmatch(r'[a-z_][a-z0-9_-]*', getattr(args, name)):
        parser.error('Invalid service identity')
values = {
    'REPO_ROOT': args.repo_root, 'APP_DIR': args.app_dir, 'ENV_FILE': args.env_file,
    'ENV_DIR': str(Path(args.env_file).parent), 'RUN_USER': args.user,
    'RUN_GROUP': args.group, 'BACKUP_DIR': args.backup_dir,
}
for value in values.values():
    if any(char in value for char in ['\n', '\r', '"', '%']):
        parser.error('Unsupported character in unit value')
text = Path(args.template).read_text()
for key, value in values.items():
    text = text.replace('@' + key + '@', value)
if re.search(r'@[A-Z_]+@', text):
    parser.error('Unresolved unit placeholder')
Path(args.output).write_text(text)
