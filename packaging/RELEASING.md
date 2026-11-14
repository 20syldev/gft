# Releasing gft

How the `.deb` of a release is built, signed and published, and what the maintainer does by hand.
Nothing in the pipeline publishes by itself: the workflow stops at a **draft** GitHub release that
the maintainer reviews, annotates and publishes.

## What the pipeline produces

- `.github/workflows/release.yml` runs on a push of a tag `X.Y.Z` (no `v` prefix). It checks that the
  tag equals `VERSION`, installs `lintian`, `minisign` and `nfpm`, builds the package, signs the
  checksums, verifies everything with `packaging/verify.sh` and creates the draft release.
- The files attached to the draft:
  - `gft_<version>_all.deb`: one package for every architecture, `Package: gft`, Debian version
    `<version>-1`. It installs `/usr/bin/gft` and `/usr/bin/gfv` (a symlink), the bash and zsh
    completions, the man page (`gft.1.gz`, `gfv.1.gz`), `/usr/share/doc/gft/copyright` (MIT) and
    `/usr/share/gft/install-method`;
  - `gft_<version>_checksums.txt`: the SHA-256 of the `.deb`, nothing else;
  - `gft_<version>_checksums.txt.minisig`: the minisign signature of that file. Its trusted comment
    holds the tab separated fields `project:gft`, `version`, `tag`, `channel:stable`, `timestamp`
    and `file`.
- `/usr/share/gft/install-method` has two lines. A packaged gft reads it and refuses `gft update`,
  `gft --upgrade` and `gft delete` (exit status 1, with the apt command to run instead):

  ```
  install_method=apt
  package=deb
  ```

  `package=deb` is the file attached to the GitHub release (the user is told to download the new
  file and run `sudo apt install ./gft_<version>_all.deb`), `package=apt` the file of the signed apt
  repository and `package=ppa` the Launchpad build (both: `sudo apt update && sudo apt upgrade gft`).
- The draft is created last, after `packaging/verify.sh dist` has passed. `verify.sh` checks the
  signature against the committed `packaging/minisign.pub`, so a secret key that does not belong to
  it stops the run before any release exists.

## The scripts

| Script                   | Role                                                                                    |
| ------------------------ | --------------------------------------------------------------------------------------- |
| `packaging/nfpm.yaml`    | the package: files, modes, symlinks, dependencies                                       |
| `packaging/build-deb.sh` | stages the man page and the marker, runs `nfpm`, then `lintian`; prints the `.deb` path |
| `packaging/verify.sh`    | signature, trusted comment, checksums, file list, marker, and a run of the extracted gfv |

`build-deb.sh [--kind deb|apt] [--out DIR] [--allow-dirty]` reads `VERSION`, refuses when it differs
from the `VERSION=` line of the `gft` script, and refuses a tree with uncommitted changes in the
files of the package (and, for `--kind apt`, a `HEAD` that is not the commit tagged with the
version). Every file gets the time `SOURCE_DATE_EPOCH`, or the commit time of `HEAD`, so the same
commit gives the same package. The two kinds differ only by the marker.

## Before the first release (once, in this order)

1. **Install** `minisign` (0.10 or later), `lintian`, `nfpm` and the `gh` command line on the
   maintainer machine (`nfpm`: https://nfpm.goreleaser.com/install/).

2. **Create the signing key of gft**, by the maintainer only, never by CI and never on a shared
   machine. It is a key of its own, not the key of any other project. The secret key stays outside
   the repository, protected by a password kept in a password manager:

   ```sh
   minisign -G -p packaging/minisign.pub -s ~/.minisign/gft.key
   ```

3. **Commit the public key** `packaging/minisign.pub`. The run fails at `verify.sh` while this file is
   missing, and the same public key is what users check downloads with.
4. **Add the two secrets** to the repository:

   ```sh
   gh secret set MINISIGN_SECRET_KEY --repo 20syldev/gft < ~/.minisign/gft.key
   gh secret set MINISIGN_PASSWORD --repo 20syldev/gft     # asks for the password
   ```

5. **Try the build without publishing** (next section).

## Try it without publishing

No key, no token, nothing uploaded. The build writes into `--out`; use a folder outside the
repository, or one that is not committed:

```sh
packaging/build-deb.sh --allow-dirty --out /tmp/gft-dist    # prints /tmp/gft-dist/gft_<version>_all.deb
packaging/verify.sh --unsigned /tmp/gft-dist
```

To test the signature as well, create a throwaway key (`minisign -G -p throw.pub -s throw.key`),
sign a checksums file the way the workflow does and run
`packaging/verify.sh --pubkey throw.pub <dist>`. Never commit such a key, and never use the real one
for a test.

## Each release

1. Make sure the commit to release is on `master`, and bump `VERSION` and the `VERSION=` line of the
   `gft` script together (`build-deb.sh` refuses the package when they differ).
2. Create the signed tag and push it. Nothing else is pushed by the pipeline:

   ```sh
   git tag -s 1.2.1 -m 1.2.1
   git push <remote> 1.2.1
   ```

3. Wait for the run of the workflow `Release` in the Actions tab. It must end green, including the
   step "Verify the package and the signature".
4. Open the draft release `1.2.1`: it holds the `.deb`, the checksums file and its `.minisig`. Write
   the notes, keep the title field empty, and **publish**. To run it again for the same tag, delete the
   draft first.
5. Check the published files from outside, with the committed public key:

   ```sh
   minisign -V -H -p packaging/minisign.pub -m gft_1.2.1_checksums.txt
   sha256sum --strict -c gft_1.2.1_checksums.txt
   ```

   `-H` makes minisign refuse a legacy signature that is not made on the hash of the file; the
   release signature is, so keep it. A user does the same with the public key of the repository at
   the tag, then installs with `sudo apt install ./gft_1.2.1_all.deb`.
6. Publish the PPA source packages (next section), and the apt variant once the apt repository
   exists.

## The PPA

`ppa:20syldev/gft` serves the same files as the GitHub `.deb`, except `install-method`
(`package=ppa`), as a source package that Launchpad builds for each series: `jammy` (22.04), `noble`
(24.04) and `resolute` (26.04). `packaging/ppa/build-source.sh` prepares and signs it, and never uploads.
It needs `devscripts`, `dpkg-dev`, `dput` and `gpg`, and the OpenPGP key that is registered on the
Launchpad account (its fingerprint goes in `SIGN_KEY`, never in the repository).

1. Do it after the tag is pushed and the GitHub release is published. A real build packages the tag
   only: `--ref` must name the commit of the tag, and `--dry-run` is the only way to try another ref.
2. Try the build without a key. It writes unsigned source packages outside the checkout, in a folder
   of its own so that the real build of step 3 finds it empty, and uploads nothing:

   ```sh
   packaging/ppa/build-source.sh --dry-run --out /tmp/gft-ppa-dry jammy noble resolute
   ```

3. Build the signed source packages, one per series. `gpg` asks for the passphrase of the key for each
   signature, unless `gpg-agent` still has it:

   ```sh
   SIGN_KEY=<fingerprint> packaging/ppa/build-source.sh jammy noble resolute
   ```

   The versions are `<version>-0ppa1~22.04.1`, `~24.04.1` and `~26.04.1`. The script makes
   `gft_<version>.orig.tar.gz` from the tag, reproducibly, and the three series share it.

4. Upload each `.changes` with the `dput` command the script prints at the end (`dput ppa:20syldev/gft
   <file>`). `dput` warns that the package includes an `.orig.tar.gz` although the Debian revision
   suggests it is not required: this is expected, every upload carries the same file, and Launchpad
   accepts it when the content is identical. Each upload answers with a mail (Accepted or Rejected),
   then one mail per build.
5. Check the packages on the "Packages" page of the PPA. `add-apt-repository ppa:20syldev/gft` fails
   with "This PPA does not support <series>" until the first source of that series is published, and
   `apt install gft` works once its build is done.

To publish the same upstream version again (a packaging fix, a series added later), raise the Debian
revision with `PPA_REV`. The new version supersedes the old one in its series:

```sh
PPA_REV=2 SIGN_KEY=<fingerprint> packaging/ppa/build-source.sh --out /tmp/gft-ppa2 noble
```

This gives `<version>-0ppa2~24.04.1`. The script never reuses a series folder of a previous run, so
give it a new `--out` or move the old folder away. The orig is made again from the tag and is
byte-identical to the one already uploaded, which Launchpad requires: a different
`gft_<version>.orig.tar.gz` for a version already uploaded is rejected for good, so a changed upstream
always means a new version and a new tag. `MESSAGE` sets the changelog line (default:
`New upstream release <version>.`).

## The apt variant (planned apt repository)

The signed apt repository is planned and is not live yet. dropr cannot serve the fixed apt paths, so
it will be hosted elsewhere. Until it exists, ship only the GitHub `.deb` and the PPA, and skip the
steps below that mention it. Once it exists, it does not serve the file of the GitHub release. It
serves a build of the same commit with `package=apt` in the marker:

```sh
git checkout 1.2.1                      # the tagged commit, required by --kind apt
packaging/build-deb.sh --kind apt --out <folder>
packaging/verify.sh --unsigned --kind apt <folder>
```

Use the same `nfpm` version as the workflow (the one in the URL of `release.yml`). The file then differs
from the GitHub one only by `/usr/share/gft/install-method` (and the `md5sums` line of that file), so
its SHA-256 is not the one in `gft_<version>_checksums.txt`. To show it, unpack both with
`dpkg-deb -R` into two fresh folders and compare them: only those two files differ.

What vouches for which file:

- the GitHub release: the minisign signature covers the checksums file, which covers the `package=deb`
  file only;
- the apt repository: its own signature (the repository key, managed with the maintainer's other
  distribution scripts) covers the `package=apt` file. The minisign key of gft plays no part there, and
  apt never reads `gft_<version>_checksums.txt`.

**Order of publication**: first the GitHub release (the signed reference, with the notes), then the
package on the CDN and the apt repository, then the PPA. The tag and the checksums must be checked
before a package reaches `apt upgrade`. Until the second step is done, `gft --check-update` already
announces the new version and apt users find nothing to upgrade: do the second step right after the
first.

## Tools of the run

- **nfpm**: the version is written in the URL of `release.yml`.
- **lintian**: the runner installs the current version of `ubuntu-latest`. A new warning fails the
  build before the draft exists, with no harm done; fix the cause, or justify a line in
  `packaging/deb/lintian-overrides` (today: `no-changelog`, because the changelog of gft is the list of
  GitHub releases).

## Rotating the key

Nothing in gft verifies a signature by itself: the key is for people who check a download. To change
it, create the new key, commit the new `packaging/minisign.pub`, replace the two secrets and announce
the change in the release notes. Files signed earlier still verify with the old public key, kept in the
git history.

## When something fails

| Symptom                                                  | Cause                                                                            |
| -------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `packaging/minisign.pub` missing, or a signature error   | step 3 of "Before the first release" was not done, or the secret key is another key |
| the step "Sign the checksums" fails                      | a secret is missing, or the password does not open the key                       |
| the step "Check the version" fails                       | the tag and `VERSION` differ                                                     |
| `VERSION is ... but the VERSION= line of gft is ...`     | the two places of the version were not bumped together                           |
| a `lintian` error or warning                             | see the tag in the log; fix it, or justify an override                           |
| `unexpected trusted comment`                             | the tag or the version in the signature differ from the tag pushed               |
| `release already exists` (gh)                            | the release or its draft exists: delete the draft, or publish a new version       |
| `uncommitted changes in the files of the package`        | local build: commit, or use `--allow-dirty` for a test only                      |
