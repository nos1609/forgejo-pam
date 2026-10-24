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
# %postun of an erase may remove the ACL and then the marker between the marker
# check above and setfacl. It removes the marker right after the ACL, so check
# again after a pause and undo this run's change if the package no longer owns
# the ACL. rpm's transaction lock is not used: without a terminal rpm does not
# wait for it and a concurrent dnf transaction would fail.
sleep 5
if [ ! -e /var/lib/rpm-state/forgejo/shadow-acl-owned ]; then
    setfacl -x u:forgejo /etc/shadow 2>/dev/null || :
    echo "<4>forgejo package removed during this run; u:forgejo removed from /etc/shadow again"
    exit 0
fi
echo "<4>reapplied u:forgejo:r on /etc/shadow"
