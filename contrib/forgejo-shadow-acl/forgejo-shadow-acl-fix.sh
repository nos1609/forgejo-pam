#!/usr/bin/bash
# Reapply u:forgejo:r on /etc/shadow only when it is missing. shadow-utils
# replaces the file on every account change and the new inode has no ACL.
# Any write here is itself an /etc event, so a no-op run must not touch the file.
set -euo pipefail
if getfacl -cp /etc/shadow | grep -q '^user:forgejo:r'; then
    exit 0
fi
setfacl -m u:forgejo:r /etc/shadow
echo "<4>reapplied u:forgejo:r on /etc/shadow"
