# SakuraOS Terminal Assist -- interactive shell layer.
#
# This is the friendly half. It catches things the pacman hooks cannot see,
# because by the time pacman runs, the original command line is gone: a bare
# `pacman -Sy foo` looks identical to a correct one from inside a hook.
#
# Everything here is pure shell pattern matching with no subprocess, because
# it runs before every interactive command. Spawning a helper here would add
# latency to every prompt, and a safety feature people turn off is worth zero.

# Sourced from both /etc/profile.d (login shells) and /etc/bash.bashrc
# (interactive non-login shells, which is what a terminal window in a desktop
# session actually is). A login shell hits both, so guard against loading the
# hooks twice and stacking two DEBUG traps.
[ -n "${SAKURA_ASSIST_LOADED:-}" ] && return 0
SAKURA_ASSIST_LOADED=1

[ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ] || return 0
# Only interactive shells: scripts and system units must not be second-guessed
# by a warning nobody is there to read. __sakura_force_interactive exists so
# the matcher can be exercised by tests, which do not run on a terminal.
case $- in
    *i*) ;;
    *) [ -n "${__sakura_force_interactive:-}" ] || return 0 ;;
esac

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
        sudo*yay*|sudo*paru*|sudo*pikaur*|sudo*trizen*|sudo*makepkg*)
            sakura_assist_warn \
                "This builds an AUR package as root." \
                "Files in the build end up owned by root, and the helper will refuse or misbehave later. Run it as yourself; it asks for a password when it needs one."
            return 1 ;;
        *btrfs*subvolume*delete*@*)
            sakura_assist_warn \
                "This deletes a BTRFS subvolume that the system is built on." \
                "@ is the running system and @home is your files. Removing either takes the restore points with it, so there would be nothing left to go back to."
            return 1 ;;
        *--overwrite*\**)
            sakura_assist_warn \
                "This lets one package overwrite files belonging to another." \
                "Ownership records end up wrong and the damage surfaces on a later update."
            return 1 ;;
        "rm -rf /"|"rm -fr /"|"sudo rm -rf /"|"sudo rm -fr /"|\
        "rm -rf /"[!a-zA-Z0-9._-]*|"sudo rm -rf /"[!a-zA-Z0-9._-]*|\
        *"; rm -rf /"*|*"&& rm -rf /"*|*"no-preserve-root"*)
            sakura_assist_warn \
                "This deletes the entire filesystem." \
                "There is no undo for this beyond restoring from a snapshot."
            return 1 ;;
        *"mkfs"*"/dev/"*)
            sakura_assist_warn \
                "This formats a disk, erasing everything on it." \
                "Check the device name carefully -- confusing sda with sdb is the usual accident."
            return 1 ;;
        *"dd "*"of=/dev/sd"[a-z]*|*"dd "*"of=/dev/nvme"*|*"dd "*"of=/dev/vd"[a-z]*|*"dd "*"of=/dev/hd"[a-z]*)
            sakura_assist_warn \
                "This writes directly to a disk device." \
                "If that is your system disk, it will not survive it."
            return 1 ;;
        *"chmod"*777*" /"|*"chmod"*777*" /usr"*|*"chmod"*777*" /etc"*)
            sakura_assist_warn \
                "This makes system files world-writable." \
                "sudo and ssh refuse to work afterwards, and the only fix is a reinstall."
            return 1 ;;
        *"chmod"*000*" /"|*"chmod"*000*" /usr"*|*"chmod"*000*" /etc"*|*"chmod 0 /"*)
            sakura_assist_warn \
                "This removes every permission from the system." \
                "Nothing can be read or run afterwards, including the tools to undo it."
            return 1 ;;
        *"chmod"*"+s"*"/bin/"*|*"chmod"*"+s"*"/usr/bin/"*)
            sakura_assist_warn \
                "This gives programs the power to run as root." \
                "Any one of them can then be used to take over the machine."
            return 1 ;;
        *"chmod"*"-x"*"/bin/bash"*|*"chmod"*"-x"*"/bin/sh"*|*"chmod"*"-x"*"/lib"*"/ld-"*)
            sakura_assist_warn \
                "This makes the shell or the program loader unrunnable." \
                "Nothing on the system starts after that, including a recovery shell."
            return 1 ;;
        # Not "rm -rf /" -- this is the one that empties every job silently and
        # has no confirmation of its own. -e is the flag people mean.
        *"crontab -r"*|*"crontab"*" -r "*)
            sakura_assist_warn \
                "This deletes all of your scheduled jobs at once." \
                "There is no confirmation and no undo. 'crontab -e' is the one that edits them."
            return 1 ;;
        # A literal shape. Nothing legitimate looks like this, so it cannot
        # fire on anything else.
        *":(){"*":|:&"*"};:"*|*":(){:|:&};:"*)
            sakura_assist_warn \
                "This is a fork bomb." \
                "It makes copies of itself until nothing else can run and the machine has to be reset."
            return 1 ;;
        *"blkdiscard"*"/dev/"*)
            sakura_assist_warn \
                "This tells the drive to discard everything on it." \
                "It is immediate, it is done by the drive itself, and no recovery tool can undo it."
            return 1 ;;
        *">"*"/dev/sd"[a-z]|*">"*"/dev/nvme"*|*">"*"/dev/vd"[a-z])
            sakura_assist_warn \
                "This writes over a disk directly." \
                "Whatever is on that disk -- partitions and all -- is gone as soon as it starts."
            return 1 ;;
        *"chown"*" -R "*" /"|*"chown"*" -R "*" /usr"*|*"chown"*" -R "*" /etc"*)
            sakura_assist_warn \
                "This changes the owner of system files." \
                "sudo stops working, because it refuses to run when it is not owned by root."
            return 1 ;;
        *"hdparm"*"--fwdownload"*)
            sakura_assist_warn \
                "This writes new firmware onto the drive." \
                "The wrong file, or an interruption, leaves a drive that no longer works at all."
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
    # The override as the message tells people to write it: in front of the
    # command, or after sudo or env. An assignment in front of a command is
    # not a shell variable when this runs -- it exists only for the command
    # that follows -- so checking the variable alone refused the message's own
    # advice a second time, and the only thing that worked was an export
    # nobody was told about. Only as the leading word, so an override written
    # further along a line cannot wave through whatever else is on it.
    case "$cmd" in
        SAKURA_ASSIST_OVERRIDE=*|"sudo SAKURA_ASSIST_OVERRIDE="*|"env SAKURA_ASSIST_OVERRIDE="*)
            return 0 ;;
    esac

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

elif [ -n "${BASH_VERSION:-}" ]; then
    # bash has no preexec, so this is built from the DEBUG trap. Two details
    # matter and both are easy to get wrong:
    #
    # extdebug is what gives the trap any power at all -- without it a
    # non-zero return is ignored and the command runs anyway, which would
    # make every warning here purely decorative.
    #
    # The DEBUG trap fires for every command, including each one inside a
    # function, a loop, or a pipeline. Checking all of them would be slow and
    # would warn repeatedly about a single typed line. The armed flag, reset
    # from PROMPT_COMMAND, limits this to the first command after each prompt
    # -- which is the line the user actually typed.
    __sakura_assist_armed=0
    __sakura_assist_arm() {
        # extdebug must NOT be set here at startup: bash documents that
        # enabling it "at shell invocation, or in a shell startup file" makes
        # it try to run the bashdb debugger profile. That fails on a system
        # without bashdb, prints a warning, and bash then turns extdebug back
        # off -- leaving a DEBUG trap that can warn but cannot actually stop
        # anything. Setting it from the first prompt, after startup has
        # finished, avoids the debugger path entirely.
        if [ -z "${__sakura_assist_ready:-}" ]; then
            shopt -s extdebug
            __sakura_assist_ready=1
        fi
        __sakura_assist_armed=1
    }

    # bash 5.1+ allows PROMPT_COMMAND to be an array; appending to it as a
    # string in that case silently does nothing.
    if [ "$(declare -p PROMPT_COMMAND 2>/dev/null | cut -c1-10)" = "declare -a" ]; then
        PROMPT_COMMAND+=(__sakura_assist_arm)
    else
        PROMPT_COMMAND="__sakura_assist_arm${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
    fi

    __sakura_assist_debug() {
        [ "$__sakura_assist_armed" = 1 ] || return 0
        # Tab completion runs commands through the same trap.
        [ -n "${COMP_LINE:-}" ] && return 0
        __sakura_assist_armed=0
        sakura_assist_preexec "$BASH_COMMAND"
    }
    trap '__sakura_assist_debug' DEBUG
fi
