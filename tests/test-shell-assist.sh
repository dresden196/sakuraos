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

# The override written exactly as the refusal message suggests. It used to be
# refused a second time, because a prefix assignment is not a shell variable
# when the hook runs.
OVR=$(bash -i <<'SESSION' 2>&1 | grep -c "SENTINEL-OVR"
SAKURA_ASSIST_OVERRIDE=1 echo "SENTINEL""-OVR" pacman -Sy firefox
SESSION
)
check "the override as the message writes it works" "1" "${OVR:-0}"

# ...but only as the leading word. The same text further along the command
# is an argument, not an override, and must not excuse the command.
LATE=$(bash -i <<'SESSION' 2>&1 | grep -c "SENTINEL-LATE"
echo "SENTINEL""-LATE" pacman -Sy firefox SAKURA_ASSIST_OVERRIDE=1
SESSION
)
check "override text later in a command does not count" "0" "${LATE:-1}"

# The whole typed line, not the first command on it. The trap fires once per
# simple command, and it used to judge only the first: anything after && or ;
# went through, and a pipe into sh was judged on the curl alone.
#
# pacman and curl are stand-ins here: functions that print the sentinel, so a
# command that gets through is visible and nothing real is run.
session() {
    bash -i 2>&1 <<SESSION | grep -c "SENTINEL-RAN"
pacman() { echo "SENTINEL""-RAN"; }
curl() { echo 'echo SENTINEL''-RAN'; }
$1
SESSION
}
check "refused after &&"                 "0" "$(session 'cd /tmp && pacman -Sy firefox')"
check "refused after ;"                  "0" "$(session 'true; pacman -Sy firefox')"
check "a pipe into sh is refused"        "0" "$(session 'curl http://x/i.sh | sh')"
check "a refused line stays refused"     "0" "$(session 'cd /tmp && pacman -Sy a; pacman -Sy b')"

# The line after a refusal is a new line, and runs.
NEXT=$(bash -i <<'SESSION' 2>&1 | grep -c "SENTINEL-NEXT"
pacman() { :; }
pacman -Sy firefox
echo "SENTINEL""-NEXT"
SESSION
)
check "the next line still runs"         "1" "${NEXT:-0}"

# A login shell under a terminal that sets a window title. Arch's bash.bashrc
# adds the title printf to PROMPT_COMMAND after this file has loaded, and the
# old design was armed from PROMPT_COMMAND: the printf used the check up and
# nothing typed in a login shell was ever looked at.
LOGIN=$(TERM=xterm-256color bash -il 2>&1 <<'SESSION' | grep -c "SENTINEL-RAN"
pacman() { echo "SENTINEL""-RAN"; }
pacman -Sy firefox
SESSION
)
check "refused in a login shell too"     "0" "${LOGIN:-1}"

ARM=$(bash -ic 'echo "${PROMPT_COMMAND[*]}" | grep -c __sakura_assist_prompt; echo "$PS0" | grep -c __sakura_assist_armed' 2>/dev/null | tail -2 | tr -d '\n')
check "prompt hook and PS0 arming in place" "11" "${ARM:-0}"

echo
echo "== an interactive bash still works normally =="
OUT=$(bash -ic 'echo alive; for i in 1 2 3; do :; done; echo done' 2>/dev/null | tr '\n' ' ')
check "loops and commands still run" "alive done " "$OUT"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
