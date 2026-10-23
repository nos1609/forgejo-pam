#!/usr/bin/bash
# Reapply u:forgejo:r on /etc/shadow only when forgejo cannot read it. shadow-utils
# replaces the file on every account change and the new inode has no ACL; chmod
# can also narrow the ACL mask and leave the entry without effective read.
# Any write here is itself an /etc event, so a no-op run must not touch the file.
set -euo pipefail
acl=$(getfacl -cpe /etc/shadow)
if grep -qE '^user:forgejo:r[-w][-x][[:space:]]+#effective:r' <<<"$acl"; then
    exit 0
fi
# setfacl recalculates the mask, which would also return read to any other entry
# the mask hides now. Refuse instead of widening access to password hashes.
if grep -E '^(user:[^:]+|group:[^:]*):r[-w][-x][[:space:]]+#effective:-' <<<"$acl" |
    grep -qv '^user:forgejo:'; then
    echo "<3>refusing: the ACL mask on /etc/shadow hides read for another entry; restore u:forgejo:r manually"
    exit 1
fi
setfacl -m u:forgejo:r /etc/shadow
echo "<4>reapplied u:forgejo:r on /etc/shadow"
