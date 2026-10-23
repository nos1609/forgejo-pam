#!/usr/bin/bash
# Reapply u:forgejo:r on /etc/shadow when the entry is not exactly r-- with
# effective r--. shadow-utils replaces the file on every account change and the
# new inode has no ACL; chmod can also narrow the ACL mask.
# Any write here is itself an /etc event, so a no-op run must not touch the file.
set -euo pipefail
# ConditionPathExists= is checked before the 3 s pause; %postun may remove the
# package, its ACL and this marker meanwhile. Check again so the ACL stays gone.
[ -e /var/lib/rpm-state/forgejo/shadow-acl-owned ] || exit 0
acl=$(getfacl -cpe /etc/shadow)
if grep -qE '^user:forgejo:r--[[:space:]]+#effective:r--$' <<<"$acl"; then
    exit 0
fi
# setfacl recalculates the mask from all group-class entries, which would return
# every right the mask hides now (read or write) to the other entries. Refuse
# instead of widening access to password hashes.
if awk '$1 ~ /^(user:[^:]+|group:[^:]*):/ && $1 !~ /^user:forgejo:/ && $2 ~ /^#effective:/ {
        n = split($1, entry, ":"); eff = substr($2, 12)
        if (entry[n] != eff) hidden = 1
    } END { exit !hidden }' <<<"$acl"; then
    echo "<3>refusing: the ACL mask on /etc/shadow hides a right of another entry; restore u:forgejo:r manually"
    exit 1
fi
setfacl -m u:forgejo:r /etc/shadow
echo "<4>reapplied u:forgejo:r on /etc/shadow"
