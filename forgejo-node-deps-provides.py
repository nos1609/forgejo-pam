#!/usr/bin/python3

import json
import sys

node_modules = set()

for package_lock_json in sys.argv[1:]:
    with open(package_lock_json, "r") as fp:
        package_lock = json.load(fp)
        for pkgpath, pkgmeta in package_lock.get("packages", {}).items():
            if "node_modules/" not in pkgpath:
                continue
            _, modpath = pkgpath.rsplit("node_modules/", 1)
            modversion = pkgmeta["version"].replace("-", "_")
            modid = modpath.lstrip("@").rstrip("/").replace("/", "-")
            node_modules.add((modid, modversion))

for modid, modversion in sorted(node_modules):
    print(f"bundled(nodejs-{modid}) = {modversion}")
