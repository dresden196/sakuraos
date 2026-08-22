# SakuraOS Terminal Assist -- interactive shell layer.
#
# This is the friendly half. It catches things the pacman hooks cannot see,
# because by the time pacman runs, the original command line is gone: a bare
# `pacman -Sy foo` looks identical to a correct one from inside a hook.
#
# Everything here is pure shell pattern matching with no subprocess, because
# it runs before every interactive command. Spawning a helper here would add
# latency to every prompt, and a safety feature people turn off is worth zero.

[ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ] || return 0
case $- in *i*) ;; *) return 0 ;; esac

sakura_assist_mode() {
    # Cheap inline parse; this file is small and read rarely enough that the
    # cost is invisible next to shell startup.
    local line section=""
    while IFS= read -r line; do
        case "$line" in
            \#*|"") continue ;;
            \[*\]) section="${line#[}"; section="${section%]}" ;;
            Mode=*) [ "$section" = "TerminalAssist" ] && { echo "${line#Mode=}"; return; } ;;
        esac
    done < /etc/sakura/sakura.conf 2>/dev/null
    echo block
}

SAKURA_ASSIST_MODE="$(sakura_assist_mode)"
[ "$SAKURA_ASSIST_MODE" = "off" ] && return 0

sakura_assist_warn() {
    printf '\n  \033[1;35mSakura Terminal Assist\033[0m\n\n' >&2
    printf '    %s\n\n' "$1" >&2
    printf '    %s\n\n' "$2" >&2
}

# Returns 0 when the command should be allowed to proceed.
sakura_assist_check() {
    local cmd="$1"

    case "$cmd" in
        # -Sy without -u is the single most common way an Arch system breaks.
        # It refreshes the package list without upgrading, so the next install
        # links new libraries against an old system.
        *pacman*-Sy[!u]*|*pacman*-Sy|*pacman*" -Sy "*)
            case "$cmd" in
                *-Syu*|*-Suy*) ;;
                *)
                    sakura_assist_warn \
                        "This refreshes the package list without upgrading the system." \
                        "That mismatch is the most common way an Arch install breaks. Use -Syu instead."
                    return 1 ;;
            esac ;;
    esac

    case "$cmd" in
        *pacman*-Rdd*|*pacman*--nodeps*--nodeps*)
            sakura_assist_warn \
                "This removes a package while ignoring what depends on it." \
                "Whatever needed it will stop working, usually not immediately."
            return 1 ;;
        *--overwrite*\**)
            sakura_assist_warn \
                "This lets one package overwrite files belonging to another." \
                "Ownership records end up wrong and the damage surfaces on a later update."
            return 1 ;;
        *"rm -rf /"|*"rm -rf /"[!a-zA-Z0-9._-]*|*"rm -fr /"|*"rm -rf --no-preserve-root"*)
            sakura_assist_warn \
                "This deletes the entire filesystem." \
                "There is no undo for this beyond restoring from a snapshot."
            return 1 ;;
        *"mkfs"*"/dev/"*)
            sakura_assist_warn \
                "This formats a disk, erasing everything on it." \
                "Check the device name carefully -- confusing sda with sdb is the usual accident."
            return 1 ;;
        *"dd "*"of=/dev/"[sn]*)
            sakura_assist_warn \
                "This writes directly to a disk device." \
                "If that is your system disk, it will not survive it."
            return 1 ;;
        *"chmod"*" -R "*777*" /"|*"chmod -R 777 /"*)
            sakura_assist_warn \
                "This makes the whole system world-writable." \
                "sudo and ssh refuse to work afterwards, and the only fix is a reinstall."
            return 1 ;;
        *curl*"|"*"sh"|*curl*"|"*bash*|*wget*"|"*"sh"|*wget*"|"*bash*)
            sakura_assist_warn \
                "This runs a script straight off the internet as a command." \
                "You cannot see what it does before it does it. Download it and read it first."
            return 1 ;;
    esac

    return 0
}

sakura_assist_preexec() {
    local cmd="$1"
    [ -n "$cmd" ] || return 0
    [ -n "${SAKURA_ASSIST_OVERRIDE:-}" ] && return 0

    if ! sakura_assist_check "$cmd"; then
        if [ "$SAKURA_ASSIST_MODE" = "warn" ]; then
            printf '    Continuing anyway (Terminal Assist is set to warn).\n\n' >&2
            return 0
        fi
        printf '    Run it again with SAKURA_ASSIST_OVERRIDE=1 if you meant it.\n\n' >&2
        return 1
    fi
    return 0
}

if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null
    sakura_assist_zsh_preexec() {
        sakura_assist_preexec "$1" || { kill -INT $$ 2>/dev/null; }
    }
    add-zsh-hook preexec sakura_assist_zsh_preexec 2>/dev/null
fi
