"""Trust instance public host keys from authenticated EC2 console output."""
import json
import os
from pathlib import Path
import re
import subprocess
import time

outputs = json.loads((Path(os.environ['RUNNER_TEMP']) / 'preview-outputs.json').read_text())
instance = outputs['instance_id']['value']
host = outputs['ansible_inventory']['value']['all']['hosts']['preview']['ansible_host']
deadline = time.monotonic() + 300
while True:
    result = subprocess.run(
        ['aws', 'ec2', 'get-console-output', '--instance-id', instance,
         '--latest', '--output', 'json'], check=True, capture_output=True, text=True)
    console = json.loads(result.stdout).get('Output') or ''
    # cloud-init publishes public keys inside this explicit block on Ubuntu.
    block = re.search(r'BEGIN SSH HOST KEY KEYS(.*?)END SSH HOST KEY KEYS', console, re.S)
    keys = re.findall(r'(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) ([A-Za-z0-9+/=]+)', block[1]) if block else []
    if keys:
        break
    if time.monotonic() >= deadline:
        raise SystemExit('No host public keys in EC2 console output; refusing unverified SSH.')
    time.sleep(10)

os.environ.update(
    PREVIEW_HOST=host,
    SECURITY_GROUP_ID='runtime-provisioned',
    SSH_PRIVATE_KEY=(Path(os.environ['RUNNER_TEMP']) / 'preview-key').read_text(),
    SSH_KNOWN_HOSTS='\n'.join(f'{host} {kind} {key}' for kind, key in keys),
)
exec(compile(Path('scripts/prepare-ci.py').read_text(), 'scripts/prepare-ci.py', 'exec'))
