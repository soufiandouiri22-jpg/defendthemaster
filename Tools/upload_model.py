#!/usr/bin/env python3
"""Uploads one 3D model (a pack's weapon as GLB or FBX) to Roblox as a Model asset and prints its asset id. Insert it
in Studio (search_asset scope "user", insert_asset) to read the MeshId and TextureID of its MeshParts.

    python3 Tools/upload_model.py <file.glb|.gltf|.fbx> "<display name>"

Uses the Open Cloud API key in the macOS Keychain as Tools/hero_sounds.py does; the key is never printed or written
anywhere.
"""

import json
import sys
import time
import uuid
from pathlib import Path

from hero_sounds import CREATOR_USER_ID, api_key, request

TYPES = {".glb": "model/gltf-binary", ".gltf": "model/gltf+json", ".fbx": "model/fbx"}


def upload(path, name):
    key = api_key()
    meta = {
        "assetType": "Model",
        "displayName": name,
        "description": "Defend The Master",
        "creationContext": {"creator": {"userId": CREATOR_USER_ID}},
    }
    boundary = uuid.uuid4().hex
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n{json.dumps(meta)}\r\n"
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{path.name}\"\r\n"
        f"Content-Type: {TYPES[path.suffix.lower()]}\r\n\r\n"
    ).encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    operation = request(
        "https://apis.roblox.com/assets/v1/assets", key, body, f"multipart/form-data; boundary={boundary}"
    )
    for _ in range(90):
        status = request(f"https://apis.roblox.com/assets/v1/{operation['path']}", key)
        if status.get("done"):
            break
        time.sleep(2)
    else:
        sys.exit(f"The upload did not finish: {operation['path']}")
    if "response" not in status:
        sys.exit(f"The upload failed: {json.dumps(status)[:500]}")
    moderation = status["response"].get("moderationResult", {}).get("moderationState", "?")
    print(f"{status['response']['assetId']} ({moderation})")
    return status["response"]["assetId"]


if __name__ == "__main__":
    if len(sys.argv) != 3 or Path(sys.argv[1]).suffix.lower() not in TYPES:
        sys.exit(__doc__)
    upload(Path(sys.argv[1]), sys.argv[2])
