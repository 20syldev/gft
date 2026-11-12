# gft - GitHub Fetch Tool

A lightweight command-line tool to fetch release information, list binary assets, and download from any GitHub project — without authentication.

## Installation

### Via curl (recommended)

```bash
curl -fsSL https://cdn.sylvain.sh/bash/gft@latest/install.sh | sh
```

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

# Download a specific asset
gft cli/cli --get "linux-amd64.deb"

# Download and verify checksum
gft cli/cli --get "linux-amd64.deb" --checksum

# Download, extract and install binary to PATH
gft cli/cli --install

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
- Release notes display (`--notes`)
- Stable JSON output for scripting (`--json`), same keys with or without `gh`
- Quiet mode — just the version string (`-q`)
- Version comparison (`v1.0..v2.0`)
- All releases listing (`--releases`)
- Pre-release support (`--pre`)
- Open release page in browser (`--open`)
- Source archive download (`--source zip|tar`)
- Response cache with configurable TTL (`GFT_CACHE_TTL`)
- Self-update (`gft update`) and uninstall (`gft delete`)
- Git stash management (`gft stash list|show|drop|clean`)
- Works without GitHub authentication
- Release data read through the `gh` CLI when it is installed and logged in, with the same JSON either way
- Loading spinner on network operations (`GFT_NO_SPINNER` to disable)
- Respects `NO_COLOR` convention and pipe detection
- Automatic ASCII fallback on non-UTF-8 terminals (`GFT_ASCII` to force)
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

| Command                  | Description                          |
| ------------------------ | ------------------------------------ |
| `gft update`             | Upgrade gft to the latest version    |
| `gft delete`             | Uninstall gft (alias: `uninstall`)   |
| `gft stash [action]`     | Manage git stashes (list, show, drop, clean) |

## Options

| Option                  | Description                                    |
| ----------------------- | ---------------------------------------------- |
| `--`                    | End of options: what follows is a repo or tag  |
| `-h, --help`            | Show help                                      |
| `-v, --version`         | Show version                                   |
| `--check-update`        | Check if a newer version of gft is available   |
| `--upgrade`             | Upgrade gft to the latest version              |
| `--releases, --list`    | List all available releases                    |
| `--assets`              | List release binary assets                     |
| `--detect`              | Auto-detect OS/arch, highlight matching assets |
| `--get <pattern>`       | Download asset matching pattern                |
| `--checksum, --verify`  | Verify SHA256 checksum after `--get`           |
| `--install`             | Download, extract and install binary to PATH   |
| `--dir <folder>`        | Write `--get`/`--source` files, the interactive (z)ip/(t)ar download and the `--install` binary there |
| `--notes`               | Show release notes                             |
| `--json`                | Output as JSON                                 |
| `-q, --quiet`           | Output version tag only                        |
| `--pre, --prerelease`   | Include pre-releases when resolving latest     |
| `--source zip\|tar`     | Download source archive non-interactively      |
| `--open`                | Open release page in browser                   |
| `--no-color`            | Disable colored output                         |
| `--no-cache`            | Bypass response cache                          |
| `--clear-cache`         | Clear all cached responses                     |

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

| Key            | Type            | Notes                                                    |
| -------------- | --------------- | -------------------------------------------------------- |
| `schema`       | integer         | `1`; raised only on an incompatible change               |
| `repository`   | string          | As given on the command line                             |
| `tag`          | string          | Release tag                                              |
| `name`         | string          | Release title, or the tag when the release has none      |
| `published_at` | string \| null  | Publication date, ISO 8601 UTC                           |
| `prerelease`   | boolean         |                                                          |
| `release_url`, `repo_url`, `zip_url`, `tarball_url` | string |                                   |
| `source`       | string          | `"api"` (through `gh`) or `"web"` (GitHub pages)         |
| `assets`       | array           | Sorted by name: `name`, `url` (strings), `digest` (`"sha256:..."` or null) |

When the release cannot be found, nothing is printed on stdout, the error goes to stderr and the exit status is 1.

`gft <user/repo> --releases --json` prints an array of the first ten releases, newest first, each with `tag`, `name`, `published_at` and `prerelease` (typed as above), or `[]` when there is none.

## Environment variables

| Variable         | Description                                           |
| ---------------- | ----------------------------------------------------- |
| `NO_COLOR`       | Set to any value to disable colors                    |
| `GITHUB_TOKEN`   | Read by `gh` (when installed) to authenticate; gft itself does not use it |
| `GFT_CACHE_TTL`  | Cache TTL in seconds (default: 300)                   |
| `GFT_NO_SPINNER` | Set to any value to disable the loading spinner       |
| `GFT_ASCII`      | Set to any value to force ASCII-only symbols          |

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
- Optional: `gh` CLI, logged in, to read release data from the API (`--json`, `--releases --json`, `--notes`)

## Troubleshooting

### Repository not found

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
