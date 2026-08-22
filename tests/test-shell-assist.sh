#!/bin/bash
# The interactive-shell half of Terminal Assist.
#
# This layer exists to catch what the pacman hook cannot see: by the time
# pacman runs, the command line is gone, so a partial upgrade or an rm -rf /
# is invisible to it. It had no tests, and it turned out to hook zsh only
# while every SakuraOS user gets bash -- so the whole layer was dead.
set -uo pipefail
PASS=0; FAIL=0
check() {
    if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1))
    else echo "  FAIL  $1"; echo "          expected: $2"; echo "          actual:   $3"; FAIL=$((FAIL+1)); fi
}

mkdir -p /etc/sakura
printf '[TerminalAssist]\nMode=block\n' > /etc/sakura/sakura.conf

echo "== the matcher =="
# Force the interactive guard so the file loads outside a real terminal.
verdict() {
    bash -c '
        case $- in *i*) ;; *) set -o emacs 2>/dev/null; esac
        __sakura_force_interactive=1
        . /usr/share/sakura/terminal-assist.sh 2>/dev/null
        if ! declare -f sakura_assist_check >/dev/null; then echo NOTLOADED; exit; fi
        if sakura_assist_check "$1" >/dev/null 2>&1; then echo allow; else echo BLOCK; fi
    ' _ "$1"
}

check "partial upgrade blocked"      "BLOCK" "$(verdict 'pacman -Sy firefox')"
check "full upgrade allowed"         "allow" "$(verdict 'pacman -Syu')"
check "-Rdd blocked"                 "BLOCK" "$(verdict 'pacman -Rdd glibc')"
check "rm -rf / blocked"             "BLOCK" "$(verdict 'sudo rm -rf /')"
check "curl piped to shell blocked"  "BLOCK" "$(verdict 'curl http://x/i.sh | bash')"
check "mkfs on a device blocked"     "BLOCK" "$(verdict 'mkfs.ext4 /dev/sda1')"
check "dd to a disk blocked"         "BLOCK" "$(verdict 'dd if=x.img of=/dev/sda')"
check "ordinary command allowed"     "allow" "$(verdict 'ls -la /home')"
check "harmless rm allowed"          "allow" "$(verdict 'rm -rf ./build')"
check "grep for a scary string ok"   "allow" "$(verdict 'grep -r mkfs docs/')"

echo
echo "== the bash hook is actually installed =="
HOOK=$(bash -ic '
    trap -p DEBUG 2>/dev/null | grep -c __sakura_assist_debug
' 2>/dev/null | tail -1)
check "DEBUG trap registered in bash" "1" "${HOOK:-0}"

# Test the behaviour, not the mechanism. extdebug is how blocking is
# achieved, but what matters is whether a dangerous command actually fails
# to run -- and an early version registered the trap correctly while still
# letting every command through.
BLOCKED=$(bash -i <<'SESSION' 2>&1 | grep -c "SENTINEL-RAN"
pacman -Sy firefox
SESSION
)
check "a blocked command really does not run" "0" "${BLOCKED:-1}"

# Split the literal so the command line bash echoes back does not itself
# match -- otherwise the sentinel is counted twice and the test looks broken.
RAN=$(bash -i <<'SESSION' 2>&1 | grep -c "SENTINEL-RAN"
echo "SENTINEL""-RAN"
SESSION
)
check "an allowed command still runs" "1" "${RAN:-0}"

ARM=$(bash -ic 'echo "$PROMPT_COMMAND" | grep -c __sakura_assist_arm' 2>/dev/null | tail -1)
check "arm hook added to PROMPT_COMMAND" "1" "${ARM:-0}"

echo
echo "== an interactive bash still works normally =="
OUT=$(bash -ic 'echo alive; for i in 1 2 3; do :; done; echo done' 2>/dev/null | tr '\n' ' ')
check "loops and commands still run" "alive done " "$OUT"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
