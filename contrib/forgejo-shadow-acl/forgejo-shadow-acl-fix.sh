#!/usr/bin/bash
# Reapply u:forgejo:r on /etc/shadow only when forgejo cannot read it. shadow-utils
# replaces the file on every account change and the new inode has no ACL; chmod
# can also narrow the ACL mask and leave the entry without effective read.
# Any write here is itself an /etc event, so a no-op run must not touch the file.
set -euo pipefail
if getfacl -cpe /etc/shadow | grep -qE '^user:forgejo:r[-w][-x][[:space:]]+#effective:r'; then
    exit 0
fi
# Without -n, setfacl recalculates the mask, which restores effective read.
setfacl -m u:forgejo:r /etc/shadow
echo "<4>reapplied u:forgejo:r on /etc/shadow"
