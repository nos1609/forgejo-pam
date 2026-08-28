#!/bin/bash
set -euo pipefail

# Generate secrets for Forgejo

SOURCE=/etc/forgejo/conf/app.ini.tmpl
TARGET=/etc/forgejo/conf/app.ini

if [ ! -f "${TARGET}" ]; then
    umask 077
    INTERNAL_TOKEN="$(forgejo generate secret INTERNAL_TOKEN)"
    JWT_SECRET="$(forgejo generate secret JWT_SECRET)"
    LFS_JWT_SECRET="$(forgejo generate secret LFS_JWT_SECRET)"
    SECRET_KEY="$(forgejo generate secret SECRET_KEY)"
    sed \
        -e "s/@INTERNAL_TOKEN@/${INTERNAL_TOKEN}/g" \
        -e "s/@JWT_SECRET@/${JWT_SECRET}/g" \
        -e "s/@LFS_JWT_SECRET@/${LFS_JWT_SECRET}/g" \
        -e "s/@SECRET_KEY@/${SECRET_KEY}/g" \
        < "${SOURCE}" > "${TARGET}"
    chgrp forgejo "${TARGET}"
    chmod 640 "${TARGET}"
fi
