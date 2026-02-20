# Bash completion for gft
# Source this file or install to /usr/share/bash-completion/completions/gft

_gft() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    opts="--help --version --assets --detect --get --notes --json --quiet --no-color"

    case "$prev" in
        --get)
            # No completion for pattern argument
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
        return 0
    fi
}

complete -F _gft gft
complete -F _gft gfv
