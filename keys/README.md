# Signing keys

## Development key

`dev-gnupg/` holds a throwaway signing key used to build and test the package
pipeline. It has **no passphrase**, it lives on a developer laptop, and it is
gitignored. Nothing it signs should ever reach a user.

Regenerate it any time with `build/make-dev-key.sh`.

## Production key

Does not exist yet, deliberately.

The production key signs every package every SakuraOS user installs. Compromise
of that key is not "rebuild the repo" — it is every existing install trusting
attacker packages, with no revocation path that reaches machines already
installed. Decide custody before generating it, not after:

- Offline master key, on removable media, never on a networked machine.
- Separate signing subkey for the build box, rotatable without reissuing the
  master.
- The master's revocation certificate stored somewhere other than the master.
- More than one person able to reach it, or the distro dies with the laptop.

`build/build-packages.sh` takes the key via `SAKURA_GPGHOME` and `SAKURA_SIGNER`,
so moving to a real key is a change of environment, not a change of pipeline.
