#!/usr/bin/env bash
# Generate the SakuraOS production signing key.
#
# RUN THIS YOURSELF, interactively. gpg will ask for the master passphrase and
# it must not pass through anybody else's shell history or tooling.
#
# What it makes, and why it is shaped this way (see keys/README.md):
#
#   master key   certify-only, passphrase-protected, no expiry. It signs
#                subkeys and nothing else, so it can stay off networked
#                machines. Its whole job is to be the thing users trust.
#   sign subkey  2 year expiry, NO passphrase, for the build box. Automated
#                builds cannot type a passphrase, and a subkey is the part you
#                are allowed to lose: revoke it with the master and issue
#                another without users having to trust a new key.
#   revocation   generated up front, because the day you need it is the day
#   certificate  the master is unavailable.
#
# Nothing here publishes anything. It leaves you files to move to removable
# media, and a build keyring holding only the subkey.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="${SAKURA_PROD_STAGE:-$REPO_ROOT/keys/prod-staging}"
BUILD_HOME="${SAKURA_PROD_GPGHOME:-$REPO_ROOT/keys/prod-gnupg}"
NAME="${SAKURA_PROD_NAME:-SakuraOS Signing Key}"
EMAIL="${SAKURA_PROD_EMAIL:-packages@sakuraos.org}"

if [[ -e "$BUILD_HOME" || -e "$STAGE" ]]; then
    echo "refusing to run: $BUILD_HOME or $STAGE already exists." >&2
    echo "A second production key is almost never what you want. Move the" >&2
    echo "existing one aside deliberately if you really mean to replace it." >&2
    exit 1
fi

if [[ ! -t 0 ]]; then
    echo "refusing to run without a terminal: gpg needs to ask you for the" >&2
    echo "master passphrase. Run this directly in your shell." >&2
    exit 1
fi

umask 077
mkdir -p "$STAGE" "$BUILD_HOME"
chmod 700 "$STAGE" "$BUILD_HOME"

echo "==> Generating the master key. gpg will ask for a passphrase."
echo "    Use something long, store it where you store the removable media,"
echo "    and do not store it in the same place as the master key itself."
echo
# Certify-only: no sign, no encrypt, no authenticate. quick-gen prompts for the
# passphrase, which is the one thing this script must not handle itself.
gpg --homedir "$BUILD_HOME" --quick-generate-key \
    "$NAME <$EMAIL>" rsa4096 cert never

FPR=$(gpg --homedir "$BUILD_HOME" --list-keys --with-colons "$EMAIL" \
      | awk -F: '/^fpr:/ {print $10; exit}')
[[ -n "$FPR" ]] || { echo "could not read the new key's fingerprint" >&2; exit 1; }
echo
echo "==> Master key $FPR"

echo "==> Adding the build signing subkey (2 years, no passphrase)."
# The master passphrase is needed once more here to certify the subkey.
gpg --homedir "$BUILD_HOME" --quick-add-key "$FPR" rsa4096 sign 2y

echo "==> Exporting the master copy before anything is stripped."
gpg --homedir "$BUILD_HOME" --armor --export "$FPR" > "$STAGE/sakura-public.asc"
# Everything, master included: this is the copy that goes to removable media.
gpg --homedir "$BUILD_HOME" --armor --export-secret-keys "$FPR" \
    > "$STAGE/sakura-master-SECRET.asc"
# Subkeys only: this is what a build box is allowed to hold.
gpg --homedir "$BUILD_HOME" --armor --export-secret-subkeys "$FPR" \
    > "$STAGE/sakura-subkeys-SECRET.asc"
# gpg writes a revocation certificate at key creation; keep a copy by fingerprint.
if [[ -f "$BUILD_HOME/openpgp-revocs.d/$FPR.rev" ]]; then
    cp "$BUILD_HOME/openpgp-revocs.d/$FPR.rev" "$STAGE/sakura-revocation.rev"
fi

echo
echo "==> Taking the passphrase off the build signing subkey."
echo "    gpg will ask for the passphrase you just chose, then for a new one."
echo "    Leave the new one EMPTY and confirm the warning: this subkey has to"
echo "    sign packages in an automated build, which cannot type anything, and"
echo "    it is the half you are allowed to lose -- revoke it with the master"
echo "    and issue another without users having to trust a new key."
echo
# --quick-add-key protects a new subkey with the master's passphrase, so without
# this the build keyring cannot sign unattended: makepkg --sign fails with
# "signing failed: No passphrase given" at the first package.
gpg --homedir "$BUILD_HOME" --passwd "$FPR" || {
    echo "could not clear the subkey passphrase; rerun:" >&2
    echo "    gpg --homedir $BUILD_HOME --passwd $FPR" >&2
    exit 1
}

echo "==> Removing the master secret from the build keyring."
# The point of the whole exercise. Delete the master's secret half locally and
# re-import only the subkeys, so this machine can sign packages and cannot
# certify anything or issue a new subkey.
gpg --homedir "$BUILD_HOME" --batch --yes --delete-secret-keys "$FPR"
gpg --homedir "$BUILD_HOME" --batch --import "$STAGE/sakura-subkeys-SECRET.asc"

echo
echo "==> Build keyring now holds:"
gpg --homedir "$BUILD_HOME" --list-secret-keys --keyid-format=long "$FPR"
echo "    A '#' after 'sec' means the master secret is absent, which is correct."
echo
echo "==> Files staged in $STAGE"
ls -l "$STAGE"
cat <<NOTE

Next, by hand, in this order:

  1. Copy $STAGE/sakura-master-SECRET.asc and
     sakura-revocation.rev onto removable media. Two copies, kept apart.
  2. Verify you can read them back from the media.
  3. Shred the staging copies:
         shred -u $STAGE/sakura-master-SECRET.asc
         shred -u $STAGE/sakura-subkeys-SECRET.asc
     (the subkey stays in $BUILD_HOME; the export is only a transport file)
  4. Tell me it is done, and I will point the build at this key and re-sign.

Until step 3, the master secret is sitting on a networked laptop, which is the
thing this design exists to avoid.
NOTE
