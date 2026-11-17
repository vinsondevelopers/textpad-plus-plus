#!/bin/sh
# Creates the update signing key once (ECDSA P-256), outside the project. Keep it safe and backed up:
# installed copies of Textpad++ only accept updates signed with it. Usage: update_key.sh <key.pem>
set -eu
KEY="$1"
if [ ! -f "$KEY" ]; then
  umask 077
  /usr/bin/openssl ecparam -name prime256v1 -genkey -noout -out "$KEY"
  chmod 600 "$KEY"
  echo "  KEY  created $KEY — BACK IT UP: without it you cannot publish updates to installed copies"
fi
