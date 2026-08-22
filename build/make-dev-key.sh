#!/usr/bin/env bash
# Generate the throwaway development signing key.
#
# This key exists so the packaging pipeline can be built and tested. It has no
# passphrase and lives on a developer machine, so nothing it signs may ever be
# published. See keys/README.md before generating a production key.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPGHOME="${SAKURA_GPGHOME:-$REPO_ROOT/keys/dev-gnupg}"
UID_STRING="SakuraOS Development Signing Key (NOT FOR PRODUCTION) <dev@sakuraos.invalid>"

if [[ -d "$GPGHOME" ]] && gpg --homedir "$GPGHOME" --list-secret-keys >/dev/null 2>&1; then
    echo "dev key already exists in $GPGHOME"
    gpg --homedir "$GPGHOME" --list-secret-keys --keyid-format=long
    exit 0
fi

mkdir -p "$GPGHOME"
chmod 700 "$GPGHOME"

# Isolated keyring: never touch the developer's personal ~/.gnupg.
gpg --homedir "$GPGHOME" --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: SakuraOS Development Signing Key (NOT FOR PRODUCTION)
Name-Email: dev@sakuraos.invalid
Expire-Date: 1y
%commit
EOF

# The keyring package ships these; pacman imports them to trust the repo.
KEYRING_DIR="$REPO_ROOT/packages/sakura-keyring"
gpg --homedir "$GPGHOME" --armor --export "$UID_STRING" > "$KEYRING_DIR/sakura.gpg"

# pacman-key --populate reads <keyring>-trusted to decide which keys become
# trusted, and at what level. 4 is "ultimate", which is what a distro's own
# signing key needs to be for its packages to verify without prompting.
gpg --homedir "$GPGHOME" --list-keys --with-colons "$UID_STRING" \
    | awk -F: '/^fpr:/ {print $10 ":4:"; exit}' > "$KEYRING_DIR/sakura-trusted"

# Present but empty: pacman-key expects the file to exist, and a real revoked
# key needs somewhere to go the day it matters.
: > "$KEYRING_DIR/sakura-revoked"

echo
gpg --homedir "$GPGHOME" --list-secret-keys --keyid-format=long
