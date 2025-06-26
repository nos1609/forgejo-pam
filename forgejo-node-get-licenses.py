#!/usr/bin/python3

import json
import sys

from license_expression import get_spdx_licensing

module_licenses = set()
license_subst = {
    key.lower(): value
    for key, value in (
        ("BSD 2-Clause", "BSD-2-Clause"),
        ("Python-2.0", "PSF-2.0"),
    )
}

for package_lock_json in sys.argv[1:]:
    with open(package_lock_json, "r") as fp:
        package_lock = json.load(fp)
        for pkgmeta in package_lock.get("packages", {}).values():
            module_license = pkgmeta.get("license")
            if module_license:
                module_licenses.add(license_subst.get(module_license.lower(), module_license))

combined_license = " AND ".join(module_licenses)

print(get_spdx_licensing().parse(combined_license))
