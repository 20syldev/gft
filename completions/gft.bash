# Bash completion for gft
# Source this file or install to /usr/share/bash-completion/completions/gft

_gft() {
    local cur prev opts cmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    opts="--help --version --check-update --upgrade --assets --detect --get --install --releases --list --notes --json --quiet --pre --prerelease --source --checksum --verify --open --dir --no-color --no-cache --clear-cache --"
    cmds="update delete uninstall stash"

    # After "--" every word is a repository or tag.
    local i
    for (( i = 1; i < COMP_CWORD; i++ )); do
        [[ "${COMP_WORDS[i]}" == "--" ]] && return 0
    done

    case "$prev" in
        --dir)
            COMPREPLY=($(compgen -d -- "$cur"))
            return 0
            ;;
        --get)
            # No completion for pattern argument
            return 0
            ;;
        --source)
            COMPREPLY=($(compgen -W "zip tar" -- "$cur"))
            return 0
            ;;
    esac

    # Commands are only recognised as the first argument.
    if [[ ${COMP_CWORD} -eq 2 ]] && [[ "${COMP_WORDS[1]}" == stash ]]; then
        COMPREPLY=($(compgen -W "list ls show diff drop rm clean clear" -- "$cur"))
        return 0
    fi

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
        return 0
    fi

    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
        return 0
    fi
}

complete -F _gft gft
complete -F _gft gfv
