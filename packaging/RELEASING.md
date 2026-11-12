# Releasing gft

How the `.deb` of a release is built, signed and published, and what the maintainer does by hand.
Nothing in the pipeline publishes by itself: the workflow stops at a **draft** GitHub release that
the maintainer reviews, annotates and publishes.

## What the pipeline produces

- `.github/workflows/release.yml` runs on a push of a tag `X.Y.Z` (no `v` prefix), in the GitHub
  environment `release` (the maintainer approves each run). It checks the tag, installs `lintian`
  and `minisign`, installs a pinned `nfpm` (the download is checked against a SHA-256 written in the
  workflow), checks the signing setup, builds the package, signs the checksums, verifies everything
  and creates or updates the draft release.
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
- Safeguards of the workflow: the permissions are `contents: read`
  with `contents: write` in the one job, the secrets appear in the `env:` of the steps that need
  them only, the tag must match `X.Y.Z`, point at a commit of `master` and equal the `VERSION` file,
  the key file is written with `umask 077` and removed at the end (`if: always()`), and no value of
  the event is interpolated into a script. The draft is created last, after
  `packaging/verify.sh dist` has passed.
- A second run for the same tag reuses the draft, keeps its notes and replaces the files already
  attached (`gh release upload --clobber`). Once the release is published the workflow refuses to
  run for that tag.

## The scripts

| Script                   | Role                                                                                    |
| ------------------------ | --------------------------------------------------------------------------------------- |
| `packaging/nfpm.yaml`    | the package: files, modes, symlinks, dependencies                                       |
| `packaging/build-deb.sh` | stages the man page and the marker, runs `nfpm`, then `lintian`; prints the `.deb` path |
| `packaging/preflight.sh` | refuses a run without public key or secrets, dry signature included                     |
| `packaging/verify.sh`    | signature, trusted comment, checksums, file list, marker, and a run of the extracted gfv |

`build-deb.sh [--kind deb|apt] [--out DIR] [--allow-dirty]` reads `VERSION`, refuses when it differs
from the `VERSION=` line of the `gft` script, and refuses a tree with uncommitted changes in the
files of the package (and, for `--kind apt`, a `HEAD` that is not the commit tagged with the
version). Every file gets the time `SOURCE_DATE_EPOCH`, or the commit time of `HEAD`, so the same
commit gives the same package. The two kinds differ only by the marker.

## Before the first release (once, in this order)

1. **Install** `minisign` (0.10 or later), `lintian`, `nfpm` and the `gh` command line on the
   maintainer machine. For `nfpm`, download the release archive, check it against the
   `checksums.txt` of the same release and unpack it in a fresh folder:

   ```sh
   v=2.48.0
   d=$(mktemp -d)
   f=nfpm_${v}_Linux_x86_64.tar.gz
   curl -fsSL -o "$d/$f" "https://github.com/goreleaser/nfpm/releases/download/v$v/$f"
   curl -fsSL -o "$d/checksums.txt" "https://github.com/goreleaser/nfpm/releases/download/v$v/checksums.txt"
   (cd "$d" && grep " $f\$" checksums.txt | sha256sum --strict -c -)
   tar -xzf "$d/$f" -C "$d" nfpm     # then put $d on your PATH
   ```

2. **Create the signing key of gft**, by the maintainer only, never by CI and never on a shared
   machine. It is a key of its own, not the key of any other project. The secret key stays outside
   the repository, protected by a password kept in a password manager:

   ```sh
   minisign -G -p packaging/minisign.pub -s ~/.minisign/gft.key
   ```

3. **Commit the public key** `packaging/minisign.pub`. The workflow fails at the preflight step while
   this file is missing, and the same public key is what users check downloads with. The workflow
   also fails if the secret key does not belong to it.
4. **Create the GitHub environment `release`** and its two secrets. Environment secrets are readable
   by approved runs only. With the `gh` command line:

   ```sh
   gh api -X PUT repos/20syldev/gft/environments/release --input - <<EOF
   {"reviewers":[{"type":"User","id":$(gh api user --jq .id)}],
    "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
   EOF
   gh api -X POST repos/20syldev/gft/environments/release/deployment-branch-policies \
       -f name='[0-9]*.[0-9]*.[0-9]*' -f type=tag
   gh secret set MINISIGN_SECRET_KEY --env release --repo 20syldev/gft < ~/.minisign/gft.key
   gh secret set MINISIGN_PASSWORD --env release --repo 20syldev/gft     # asks for the password
   ```

   An environment that does not exist is created unprotected by the first run that names it, and a
   workflow cannot check the protections with its own token: do this step before the first tag.
5. **Optional hardening**: a tag ruleset on `[0-9]*.[0-9]*.[0-9]*` (only the maintainer may create or
   move such tags) and a signed-commits rule on `master`.
6. **Try the build without publishing** (next section).

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
   git tag -s 1.1.1 -m 1.1.1
   git push <remote> 1.1.1
   ```

3. Approve the run of the workflow `release` in the Actions tab. It must end green, including the
   step "Verify the signature, the checksums and the package".
4. Open the draft release `1.1.1`: it holds the `.deb`, the checksums file and its `.minisig`. Write
   the notes (in French), keep the title field empty, and **publish**. The workflow may be run again
   for the tag as long as the draft is not published: the notes are kept.
5. Check the published files from outside, with the committed public key:

   ```sh
   minisign -V -H -p packaging/minisign.pub -m gft_1.1.1_checksums.txt
   sha256sum --strict -c gft_1.1.1_checksums.txt
   ```

   `-H` makes minisign refuse a legacy signature that is not made on the hash of the file; the
   release signature is, so keep it. A user does the same with the public key of the repository at the tag, then installs with `sudo apt install ./gft_1.1.1_all.deb`.
6. Once the apt repository exists, publish the apt variant (next section). Publish the PPA source
   package (`packaging/ppa/`) when the PPA exists.

## The apt variant (planned apt repository)

The signed apt repository on dropr is planned and is not live yet: until it exists, ship only the
GitHub `.deb` and the PPA, and skip the steps below that mention it. Once it exists, it does not serve
the file of the GitHub release. It serves a build of the same commit with `package=apt` in the marker:

```sh
git checkout 1.1.1                      # the tagged commit, required by --kind apt
packaging/build-deb.sh --kind apt --out <folder>
packaging/verify.sh --unsigned --kind apt <folder>
```

Use the same `nfpm` version as the workflow (`NFPM_VERSION` in `release.yml`). The file then differs
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

## Updating what is pinned

- **nfpm**: set `NFPM_VERSION` and `NFPM_SHA256` in `release.yml` (the SHA-256 is the line of
  `nfpm_<version>_Linux_x86_64.tar.gz` in the `checksums.txt` of the nfpm release), and use a release
  that is more than two weeks old.
- **lintian**: the runner installs the current version of `ubuntu-24.04`. A new warning fails the
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
| `packaging/minisign.pub is missing`                      | step 3 of "Before the first release" was not done                                |
| `the secret ... is empty or missing`                     | the secret is not set in the environment `release`                               |
| `cannot sign with MINISIGN_PASSWORD`                     | the password does not open the key, or the secret is not a minisign secret key   |
| `is not the secret key of packaging/minisign.pub`        | the secret and the committed public key come from two different key pairs        |
| `is not an X.Y.Z tag`                                    | the tag has a `v` prefix, a suffix or a leading zero                             |
| `does not point at a commit of master`                   | the tag was made on another branch                                               |
| `the VERSION file does not say ...`                      | the tag and `VERSION` differ                                                     |
| `VERSION is ... but the VERSION= line of gft is ...`     | the two places of the version were not bumped together                           |
| `nfpm ... FAILED` (sha256sum)                            | the archive is not the pinned one: do not continue, find out why                 |
| a `lintian` error or warning                             | see the tag in the log; fix it, or justify an override                           |
| `unexpected trusted comment`                             | the tag or the version in the signature differ from the tag pushed               |
| `the release ... is already published`                   | the release exists: publish a new version instead of re-running                  |
| `uncommitted changes in the files of the package`        | local build: commit, or use `--allow-dirty` for a test only                      |
