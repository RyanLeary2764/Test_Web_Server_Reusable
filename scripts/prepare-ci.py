"""Create isolated CI connection files without logging credentials."""
import ipaddress
import json
import os
from pathlib import Path
import shutil
import sys

root = Path(os.environ["RUNNER_TEMP"]) / "preview-deploy"
if sys.argv[1:] == ["--cleanup"]:
    if root.exists():
        shutil.rmtree(root)
    sys.exit(0)

host = os.environ["PREVIEW_HOST"].strip()
ipaddress.IPv4Address(host)
for name in ("SSH_PRIVATE_KEY", "SSH_KNOWN_HOSTS", "SECURITY_GROUP_ID"):
    if not os.environ.get(name, "").strip():
        raise SystemExit(f"Missing required configuration: {name}")
root.mkdir(mode=0o700, parents=True, exist_ok=True)
for filename, variable in (("id_ed25519", "SSH_PRIVATE_KEY"), ("known_hosts", "SSH_KNOWN_HOSTS")):
    path = root / filename
    path.write_text(os.environ[variable].strip() + "\n")
    path.chmod(0o600)
(root / "inventory.json").write_text(json.dumps({"all": {"hosts": {"preview": {
    "ansible_host": host,
    "ansible_user": "ubuntu",
    "ansible_python_interpreter": "/usr/bin/python3",
}}}}))
(root / "vars.json").write_text(json.dumps({
    "nginx_image": os.environ["IMAGE_TAG"],
    "image_archive": str(Path("image/website-image.tar.gz").resolve()),
}))
