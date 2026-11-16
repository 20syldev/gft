# gft - GitHub Fetch Tool

A lightweight command-line tool to fetch release information, list binary assets, and download from any GitHub project — without authentication.

## Installation

### Via curl (recommended)

```bash
curl -fsSL https://dropr.sylvain.sh/bash/gft@latest/install.sh | sh
```

### Via apt (Debian, Ubuntu)

From the [Launchpad PPA](https://launchpad.net/~20syldev/+archive/ubuntu/gft), for Ubuntu 22.04, 24.04 and 26.04 and their derivatives:

```bash
sudo add-apt-repository ppa:20syldev/gft
sudo apt install gft
```

It is then upgraded like any other package:

```bash
sudo apt update && sudo apt upgrade gft
```

On Debian, or without the PPA, use the `.deb` attached to a [GitHub release](https://github.com/20syldev/gft/releases/latest):

```bash
sudo apt install ./gft_<version>_all.deb
```

The package is named `gft` and is the same for every architecture. It installs `/usr/bin/gft`, the `gfv` alias, the bash and zsh completions and the man page. It depends on `curl` and on `mawk` or `gawk`, and recommends `git` (for `gft stash`), `unzip` (for `.zip` installs) and `gh`; `xdg-utils` is only suggested (for `--open`).

Each release ships `gft_<version>_checksums.txt` (the SHA-256 of the `.deb`) and its minisign signature `gft_<version>_checksums.txt.minisig`. To verify a download, put the three files in one folder, fetch the public key of this repository at the release tag and check:

```bash
curl -fsSLO https://raw.githubusercontent.com/20syldev/gft/<version>/packaging/minisign.pub
minisign -V -H -p minisign.pub -m gft_<version>_checksums.txt
sha256sum --strict -c gft_<version>_checksums.txt
```

`-H` makes minisign refuse a legacy signature that is not made on the hash of the file; the release signature is, so keep it.

A gft installed by apt is managed by apt:

- `gft update`, `gft --upgrade`, `gft delete` and `gft uninstall` change nothing: they print the apt command to run instead (`sudo apt update && sudo apt upgrade gft`, or `sudo apt remove gft`) and exit with status 1. For the `.deb` of a GitHub release, the upgrade hint is to download the new `.deb` from the releases page and run `sudo apt install ./gft_<version>_all.deb`.
- `gft --check-update` still works and shows that same hint instead of `gft --upgrade`.
- Do not mix `curl | sh` and apt: `install.sh`, `update.sh` and `delete.sh` refuse to run while the `gft` package is installed, and print the apt command.

The package marks itself with `/usr/share/gft/install-method`, which gft reads next to the real script (`../share/gft/install-method`). Installs made with `install.sh` or by hand have no such file and keep their usual `gft update` and `gft delete`.

### Manual installation

```bash
# Download and run the installer
./install.sh

# Or manually:
cp gft /usr/local/bin/
chmod +x /usr/local/bin/gft
```

## Usage

### Basic syntax

```bash
gft [options] [--] <user/repo> [tag]
```

Options may come before or after the repository. Everything after `--` is a repository or a tag, never an option or a command.

### Quick examples

```bash
# Get latest release info
gft cli/cli

# Get a specific version
gft nodejs/node v22.0.0

# List all releases
gft cli/cli --releases

# List all binary assets
gft cli/cli --assets

# Auto-detect the right binary for your OS
gft cli/cli --detect

# Download a specific asset (--get takes a case-insensitive grep pattern)
gft cli/cli --get "linux-amd64.deb"

# Download the asset with exactly this file name (no pattern, no menu)
gft cli/cli --asset=gh_2.104.0_linux_amd64.tar.gz

# Download and verify checksum
gft cli/cli --get "linux-amd64.deb" --checksum

# Download, extract and install binary to PATH
gft cli/cli --install

# Install into ~/.local/bin, whatever is writable
gft cli/cli --install --user

# Choose where downloads and the installed binary go
gft cli/cli --get linux-amd64.tar.gz --dir ~/Downloads
gft junegunn/fzf --install --dir ~/.local/bin

# Get just the version number (for scripts)
VERSION=$(gft nodejs/node -q)

# Show release notes
gft cli/cli --notes

# JSON output (see "JSON output" below)
gft cli/cli --json
gft cli/cli --releases --json

# A repository or tag that looks like an option or a command
gft -- update/x

# Compare two releases
gft cli/cli v2.40.0..v2.50.0

# One entry per line for programs (see "Scripting")
gft --releases --plain -- cli/cli
gft --assets --detect --plain -- cli/cli

# Include pre-releases when resolving latest
gft cli/cli --pre

# Open release page in browser
gft cli/cli --open
```

### Self-management

```bash
# Upgrade gft to the latest version
gft update

# Uninstall gft
gft delete

# Check if a newer version is available
gft --check-update
```

`gft --check-update` compares versions numerically: an older gft reports an update, an equal one is up to date, and a newer one (a development build) says it is newer than the latest release and is never downgraded by `gft update`. When gft is installed by apt, `gft update` and `gft delete` only print the apt command to use (see "Via apt").

### Stash management

```bash
# List stashes in the current repo
gft stash list

# Show the diff of stash 1
gft stash show 1

# Drop stash 0 (with confirmation)
gft stash drop 0

# Delete all stashes without confirmation
gft stash clean -y
```

## Alias

`gfv` is available as an alias for `gft`.

## Features

- Automatic latest release detection
- Binary asset listing (`--assets`)
- Platform auto-detection (`--detect`) — finds the right binary for your OS/arch
- Direct asset download by pattern (`--get`)
- Checksum verification after download (`--checksum`)
- Binary install to PATH (`--install`)
- Single destination folder for downloads and installs (`--dir`)
- Download by exact file name (`--asset=NAME`), never over an existing file unless `--force`
- Install for the current user only (`--install --user`)
- Line-oriented output for programs (`--plain`), with fixed exit codes
- Release notes display (`--notes`)
- Stable JSON output for scripting (`--json`), same keys with or without `gh`
- Quiet mode — just the version string (`-q`)
- Version comparison (`v1.0..v2.0`)
- All releases listing (`--releases`)
- Pre-release support (`--pre`)
- Open release page in browser (`--open`)
- Source archive download (`--source zip|tar`)
- Response cache with configurable TTL (`GFT_CACHE_TTL`)
- Self-update (`gft update`) and uninstall (`gft delete`), left to apt when installed as a package
- Git stash management (`gft stash list|show|drop|clean`)
- Works without GitHub authentication
- Follows renamed or transferred repositories and reports their new name
- Release data read through the `gh` CLI when it is installed and logged in, with the same JSON either way
- Loading spinner on network operations (`GFT_NO_SPINNER` to disable)
- Respects `NO_COLOR` convention and pipe detection
- Automatic ASCII fallback on non-UTF-8 terminals (`GFT_ASCII` to force)
- Debian package (`.deb`) with signed checksums
- Bash and Zsh completion
- Manpage (`man gft`)

## How it works

gft scrapes GitHub release pages directly, so it:

- Requires **no authentication** (no token setup)
- Has **no API rate limit** issues without `gh` (it reads web pages, not the API)
- Works on any machine with `curl` and `bash`

When `gh` CLI is installed and authenticated, gft reads release data from the GitHub API through it. The JSON output has the same keys either way.

## Commands

Commands are only recognised as the first argument: `gft user/update` or `gft cli/cli stash` never runs a command.

| Command              | Description                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------- |
| `gft update`         | Upgrade gft to the latest version (prints the apt command instead when installed by apt) |
| `gft delete`         | Uninstall gft, alias: `uninstall` (prints the apt command instead when installed by apt) |
| `gft stash [action]` | Manage git stashes (list, show, drop, clean)                                             |

## Options

| Option                 | Description                                                                                                     |
| ---------------------- | --------------------------------------------------------------------------------------------------------------- |
| `--`                   | End of options: what follows is a repo or tag                                                                   |
| `-h, --help`           | Show help                                                                                                       |
| `-v, --version`        | Show version                                                                                                    |
| `--check-update`       | Check if a newer version of gft is available (older, up to date or newer than the latest release)               |
| `--upgrade`            | Upgrade gft to the latest version (same as `gft update`)                                                        |
| `--releases, --list`   | List all available releases                                                                                     |
| `--assets`             | List release binary assets                                                                                      |
| `--detect`             | Auto-detect OS/arch, highlight matching assets                                                                  |
| `--get <pattern>`      | Download the asset matching a basic regular expression (`grep -i`); several matches ask which one               |
| `--asset <name>`       | Download the asset with exactly this file name, or install it with `--install`                                  |
| `--checksum, --verify` | Verify the SHA-256 (or SHA-512) of a download from the release checksum file; fails when it cannot              |
| `--install`            | Download, extract and install binary to PATH                                                                    |
| `--user`               | With `--install`: install to `~/.local/bin` (never `/usr/local/bin`)                                            |
| `--force`              | Replace an existing file; downloads refuse to otherwise                                                         |
| `--plain`              | With `--releases` or `--assets`: one entry per line, nothing else                                               |
| `--dir <folder>`       | Write `--get`/`--asset`/`--source` files, the interactive (z)ip/(t)ar download and the `--install` binary there |
| `--notes`              | Show release notes                                                                                              |
| `--json`               | Output as JSON                                                                                                  |
| `-q, --quiet`          | Output version tag only                                                                                         |
| `--pre, --prerelease`  | Include pre-releases when resolving latest (with `--releases --plain`: list them)                               |
| `--source zip\|tar`    | Download source archive non-interactively                                                                       |
| `--open`               | Open release page in browser                                                                                    |
| `--no-color`           | Disable colored output                                                                                          |
| `--no-cache`           | Bypass response cache                                                                                           |
| `--clear-cache`        | Clear all cached responses                                                                                      |

`--dir`, `--source` and `--asset` also take the form `--option=value`, and `--pre`, `--no-cache` and `--checksum` (alias `--verify`) take `=true|false` (also `1`, `0`, `yes`, `no`, `on`, `off`, in any case). The last occurrence on the line wins, and an invalid value is a usage error (exit status 2). `--dir=~` and `--dir=~/folder` expand the tilde themselves. `--dir` still needs an existing, writable folder.

## Scripting

### Exit status

| Status | Meaning                                                                                                                                                                        |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0      | Success, including a list that is empty                                                                                                                                        |
| 1      | An error: repository or release not found, network error, a file that exists, a failed download or checksum                                                                    |
| 2      | A usage error: an invalid option value or combination, an `--asset` that is not a plain file name or that names several assets, several matches for `--get` without a terminal |

The separate forms of options that were already there keep the status 1 for their own usage errors (`--source rar`, a missing `--dir`, an unknown option). Their new `=` forms (`--source=rar`, `--dir=`) are usage errors with status 2, like an invalid boolean.

### `--plain`

`gft --releases --plain [--pre[=BOOL]] -- user/repo` and `gft --assets --plain [--detect] [--pre[=BOOL]] -- user/repo [tag]` print one entry per line on standard output and nothing else: no title, no tip, no spinner, no colour. Messages and errors go to standard error. The standard input is never read.

```
$ gft --releases --plain -- cli/cli
v2.104.0	2026-11-12
v2.103.3	2026-10-26

$ gft --assets --detect --plain -- cli/cli
gh_2.104.0_linux_amd64.tar.gz	recommended
gh_2.104.0_checksums.txt
gh_2.104.0_linux_386.deb
```

- `--releases --plain`: the first page of releases (ten at most), newest first, as `tag<TAB>YYYY-MM-DD`, with ` prerelease` after the date for a pre-release (`tag<TAB>YYYY-MM-DD prerelease`). A line never holds more than one tab. Pre-releases only appear with `--pre`.
- `--assets --plain`: the file names of the assets, decoded and without duplicates. With `--detect` the assets that fit this system come first, with `recommended` in a second column (packages, checksums and signatures are never recommended, as `--install` never picks them).
- The words `recommended` and `prerelease` are fixed: they are not translated and not affected by the locale.
- Names that cannot be told apart from a plain file name or tag are dropped: empty lines, control and invisible characters (including bidirectional marks and zero-width characters), bytes that are not valid UTF-8, tabs in a name, duplicates, tags with `..`, the tags `latest`, `main` and `master`, and for assets any name with a slash, a backslash or a leading dot. At most 200 lines are printed. A `%` that is not part of an escape stays as it is.
- It reads public pages only (never `gh` and never the API): nothing is listed for a private repository.
- The whole run, every request included, has one time limit of 8 seconds (`GFT_PLAIN_TIMEOUT`, whole seconds from 1 to 9999). If the time runs out while a long list is being read, the list is cut short and a message goes to standard error.
- A tag given to `--assets --plain` may be the decoded one that `--releases --plain` printed (`v1#x`, `astro@7`): gft encodes it for the request.
- Exit status: 0 with an empty output when there is nothing to list, 1 for a network error or a repository that does not exist, 2 for a usage error. `--plain` goes with `--releases` or `--assets` (`--detect` counts) and with no other mode (`--json`, `-q`, `--get`, `--install`…); options that do not apply to a list (`--force`, `--dir`, `--checksum`) are accepted and ignored.

### Downloads

- `--asset=NAME` matches the file name exactly, after URL decoding: no pattern, no substring, no menu. A name that is not a plain file name (a slash, a backslash, a leading dot, a control character) is refused. It works alone (download) and with `--install`. Without a match the status is 1, and when two assets decode to the same name gft stops with status 2 instead of choosing one.
- `--get` is unchanged: its argument is a basic regular expression for `grep -i`, so `.` matches any character. When several assets match and there is no terminal, gft lists them on standard error and exits with status 2 instead of waiting for an answer.
- A download never replaces an existing file (`--get`, `--asset`, `--source`): pass `--force`. `--install` still replaces the installed binary, which is how an update works: the new binary is written next to it and renamed over it, so a read-only or running binary and a symlink are replaced and never written through. A failed or interrupted download leaves nothing behind, and an HTTP error page is never saved as the file.
- `--source` names the file after the tag, made harmless: a slash or any character outside letters, digits and `._@+-` becomes `_`, and leading dots are removed.
- `--install` without `--asset` or `--get` only picks a `.tar.gz`, `.tgz`, `.zip` or a plain binary: never a package (`.deb`, `.rpm`, `.apk`, `.pkg`, `.msi`, `.dmg`, `.snap`…), a checksum, signature or SBOM file, or an archive that gft cannot extract (`.tar.xz`, `.7z`…). Name such a file with `--asset` to install it anyway.
- `--install --user` installs into `~/.local/bin`, created if needed. Without it gft keeps its order: `/usr/local/bin` when writable, else `~/.local/bin`, else `~/bin`. `--user` and `--dir` cannot be combined.

### Checksums

`--checksum` checks the download against a checksum file of the same release, and fails (non-zero status) whenever it cannot: no checksum file, the file missing from the list, no hash found, a hash that is neither SHA-256 nor SHA-512, no `sha256sum` or `shasum` (`sha512sum` for SHA-512), or the checksum file not downloadable. The download is checked before it is moved into place: on a mismatch, or any other failure, it is removed and a file that was there before (with `--force`) is kept. `--checksum` does not go with `--source` (a source archive has no checksum file): that is a usage error, status 2. The names in the list are compared exactly (a leading `*` is ignored), and a file that holds a single hash counts only for the file it is named after (`app.tar.gz.sha256`). This proves that the download is intact, not that it is authentic: the list comes from the same release.

### Other

- `-q` on a repository without any release prints `No release found` on standard error and exits with status 1, instead of printing `main`.
- `gft user/repo v1..v2` compares the decoded tags, so scoped tags such as `astro@7.0.0` are found.
- `--clear-cache` removes the cache entries only (the files that gft wrote), not the other files of the folder.
- `--` ends the options: a tag such as `--upgrade` or `update` is then a tag. `update`, `delete`, `uninstall` and `stash` are commands only as the first argument.

## JSON output

`gft <user/repo> [tag] --json` prints one object, with the same keys whether the data comes from the GitHub API (`gh` logged in) or from the web pages. The output is compact on a single line (no spaces, e.g. `"published_at":"..."`) when stdout is not a terminal, and indented on a terminal.

```json
{
    "schema": 1,
    "repository": "cli/cli",
    "tag": "v2.104.0",
    "name": "GitHub CLI 2.104.0",
    "published_at": "2026-11-12T19:03:51Z",
    "prerelease": false,
    "release_url": "https://github.com/cli/cli/releases/tag/v2.104.0",
    "repo_url": "https://github.com/cli/cli",
    "zip_url": "https://github.com/cli/cli/archive/refs/tags/v2.104.0.zip",
    "tarball_url": "https://github.com/cli/cli/archive/refs/tags/v2.104.0.tar.gz",
    "source": "api",
    "assets": [
        {
            "name": "gh_2.104.0_checksums.txt",
            "url": "https://github.com/cli/cli/releases/download/v2.104.0/gh_2.104.0_checksums.txt",
            "digest": "sha256:180df77fb931591d5d65e33f02a76c9ade314d1c335569af73cc6c8fcb365d2c"
        }
    ]
}
```

| Key                                                 | Type           | Notes                                                                      |
| --------------------------------------------------- | -------------- | -------------------------------------------------------------------------- |
| `schema`                                            | integer        | `1`; raised only on an incompatible change                                 |
| `repository`                                        | string         | As given, or its current name if it was renamed or transferred             |
| `tag`                                               | string         | Release tag                                                                |
| `name`                                              | string         | Release title, or the tag when the release has none                        |
| `published_at`                                      | string \| null | Publication date, ISO 8601 UTC                                             |
| `prerelease`                                        | boolean        |                                                                            |
| `release_url`, `repo_url`, `zip_url`, `tarball_url` | string         |                                                                            |
| `source`                                            | string         | `"api"` (through `gh`) or `"web"` (GitHub pages)                           |
| `assets`                                            | array          | Sorted by name: `name`, `url` (strings), `digest` (`"sha256:..."` or null) |

When the release cannot be found, nothing is printed on stdout, the error goes to stderr and the exit status is 1.

`gft <user/repo> --releases --json` prints an array of the first ten releases, newest first, each with `tag`, `name`, `published_at` and `prerelease` (typed as above), or `[]` when there is none.

## Environment variables

| Variable            | Description                                                                                                                        |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `NO_COLOR`          | Set to any value to disable colors                                                                                                 |
| `GITHUB_TOKEN`      | Read by `gh` (when installed) to authenticate; gft itself does not use it                                                          |
| `GFT_CACHE_TTL`     | Cache TTL in seconds (default: 300)                                                                                                |
| `GFT_CACHE_DIR`     | Folder of the response cache (default: `~/.config/gft/cache`); `--clear-cache` only removes the cache entries (`https_*`) it holds |
| `GFT_PLAIN_TIMEOUT` | Time limit of `--plain` in seconds, for the whole run: 1 to 9999 (default: 8)                                                      |
| `GFT_NO_SPINNER`    | Set to any value to disable the loading spinner                                                                                    |
| `GFT_ASCII`         | Set to any value to force ASCII-only symbols                                                                                       |

## Output example

```
→ Looking up user/repo (latest)...

✓ Latest release: vX.Y.Z

- Repository:  user/repo
- Tag:         vX.Y.Z

> Links
  ├─ Repository:   https://github.com/user/repo
  ├─ Releases:     https://github.com/user/repo/releases
  └─ This release: https://github.com/user/repo/releases/tag/vX.Y.Z

> Source Archives
  ├─ ZIP:    https://github.com/user/repo/archive/refs/tags/vX.Y.Z.zip
  └─ TAR.GZ: https://github.com/user/repo/archive/refs/tags/vX.Y.Z.tar.gz

> Quick Commands
  ├─ curl -LO "https://github.com/user/repo/archive/refs/tags/vX.Y.Z.zip"
  ├─ curl -LO "https://github.com/user/repo/archive/refs/tags/vX.Y.Z.tar.gz"
  └─ git clone --depth 1 --branch vX.Y.Z https://github.com/user/repo.git

→ Download? (z)ip, (t)ar.gz, (n)o [n]:
```

## Why gft over gh cli?

|                         | gft                  | gh cli                            |
| ----------------------- | -------------------- | --------------------------------- |
| Authentication required | No                   | Yes                               |
| Setup needed            | None                 | `gh auth login`                   |
| Binary asset listing    | `--assets` (no auth) | `gh release view` (auth required) |
| Platform auto-detect    | `--detect`           | Not available                     |
| Pattern download        | `--get pattern`      | Manual URL                        |
| Dependencies            | curl, bash           | Go binary (~50MB)                 |
| Size                    | ~15KB                | ~50MB                             |

## Prerequisites

- `curl` (for HTTP requests)
- `bash` (>= 4.0)
- Internet connection
- `mawk` or `gawk`, and GNU `grep` (present on Debian and Ubuntu; the apt package depends on `curl` and `mawk | gawk`)
- Optional: `gh` CLI, logged in, to read release data from the API (`--json`, `--releases --json`, `--notes`)

## Troubleshooting

### Repository not found or private

- Check the spelling of username and repository
- Make sure the repository is public: private repositories are not supported, even with `gh`

### No release found

- The repository may not have any releases
- Visit `https://github.com/username/repository/releases` to verify

### Download error

- Check your internet connection
- The specified tag may not exist

## Known limitations

- Public repositories only: gft checks that the repository exists anonymously on github.com, so private repositories are rejected even when `gh` is logged in.
- Without `--pre`, resolving the latest release cuts a tag containing a `/` at the slash. Give the tag explicitly (`gft owner/repo vscope/1.2.3`).
- With `--pre`, `-q` prints the tag as GitHub encodes it in the page (`core%4013.4.0`); `--json` decodes it (`core@13.4.0`).
- `--releases` and `--releases --json` only cover the first page of releases (about ten).

## Development

`tests/gft.sh` runs gft against a fake `curl` and pages built on the spot: no network, no access to your `~/.config/gft`. `tests/gft.sh NAME` runs the checks whose name contains NAME, and `GFT_TESTS_CLEAN=1` removes the work folder at the end. The comparison with the previous release needs the tag `1.2.2` (`GFT_TESTS_SKIP_OLD=1` skips it). Run the tests before tagging a release.

The fake `curl` (`tests/fakecurl`) reads `$FAKE_DIR/map`, one line per URL: `URL<TAB>STATUS<TAB>FILE[<TAB>EFFECTIVE_URL]`. `FILE` is relative to `$FAKE_DIR` (`-` for an empty body) and an unlisted URL answers 404. Every call is logged in `$FAKE_DIR/calls`, and `$FAKE_SLEEP` seconds of delay per call are cut short by `--max-time` like the real thing (exit status 28).
