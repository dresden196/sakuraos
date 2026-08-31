#!/usr/bin/env bash
# Tell somebody the canary found something.
#
# Two channels on purpose. A push notification is how you find out tonight;
# a GitHub issue is where the answer goes once somebody has worked out which
# package it was. A dismissed notification is gone, and "it was mesa 25.2.2,
# Arch fixed it in -3" is exactly the thing you want to find again next time.
#
#   canary-notify.sh broke   "14 updates" "mesa, linux, nvidia"  /path/to/log
#   canary-notify.sh stalled "the base install failed"  ""       /path/to/log
#
# "broke" means an update broke the machine: working as designed, users are
# already protected by the advisory. "stalled" means the canary could not run
# at all, which is worse, because no advisory was published and silence looks
# exactly like success.
set -euo pipefail

KIND="${1:?broke|stalled}"
HEADLINE="${2:?}"
PACKAGES="${3:-}"
LOG="${4:-}"

# The ntfy topic is a shared secret: anyone who knows it can read and publish.
# Kept out of the repository for that reason.
TOPIC_FILE="${SAKURA_NTFY_TOPIC_FILE:-/etc/secrets/ntfy-canary}"
GH_TOKEN_FILE="${SAKURA_GH_TOKEN_FILE:-/etc/secrets/ghtoken}"
GH_REPO="${SAKURA_GH_REPO:-dresden196/sakuraos}"
STAMP="$(date -u +%Y-%m-%d)"

tail_of_log() {
    [[ -n "$LOG" && -f "$LOG" ]] || { echo "(no log)"; return; }
    tail -n 25 "$LOG"
}

# Never let a notification failure take down the caller. The canary's job is
# publishing the advisory; telling a human is important and strictly second,
# and a dead ntfy host must not turn a successful protective hold into a
# failed run.
notify_push() {
    [[ -r "$TOPIC_FILE" ]] || { echo "notify: no ntfy topic at $TOPIC_FILE, skipping" >&2; return 0; }
    local topic; topic="$(tr -d '[:space:]' < "$TOPIC_FILE")"
    [[ -n "$topic" ]] || return 0

    local title prio
    if [[ "$KIND" == "stalled" ]]; then
        title="SakuraOS canary could not run"; prio="urgent"
    else
        title="SakuraOS canary FAILED"; prio="high"
    fi

    curl -sS -m 20 \
        -H "Title: $title" \
        -H "Priority: $prio" \
        -H "Tags: warning" \
        -d "$HEADLINE
${PACKAGES:+held: $PACKAGES}" \
        "https://ntfy.sh/$topic" >/dev/null \
        || echo "notify: push failed" >&2
}

# One issue per failure, not one per night. A recurring failure comments on
# the open issue instead of opening a second one: an inbox with fourteen
# identical issues is an inbox nobody reads.
notify_issue() {
    [[ -r "$GH_TOKEN_FILE" ]] || { echo "notify: no GitHub token, skipping" >&2; return 0; }
    command -v gh >/dev/null || { echo "notify: gh not installed, skipping" >&2; return 0; }
    GH_TOKEN="$(tr -d '[:space:]' < "$GH_TOKEN_FILE")"; export GH_TOKEN

    local body
    body="$(printf '%s\n\n**Packages in the failed transaction**\n\n```\n%s\n```\n\n**Log tail**\n\n```\n%s\n```\n\n<sub>Opened by build/canary.sh. The advisory is published, so machines are already holding these. Working out which package is responsible is a bisect and is not automated.</sub>' \
        "$HEADLINE" "${PACKAGES:-none recorded}" "$(tail_of_log)")"

    local existing
    existing="$(gh issue list --repo "$GH_REPO" --label canary --state open \
                  --json number --jq '.[0].number' 2>/dev/null || true)"

    if [[ -n "$existing" && "$existing" != "null" ]]; then
        gh issue comment "$existing" --repo "$GH_REPO" --body "**$STAMP**

$body" >/dev/null \
            && echo "notify: commented on issue #$existing" \
            || echo "notify: could not comment on #$existing" >&2
        return 0
    fi

    gh label create canary --repo "$GH_REPO" --color d81b60 \
        --description "Raised by the update canary" >/dev/null 2>&1 || true
    gh issue create --repo "$GH_REPO" --label canary \
        --title "Canary failed $STAMP" --body "$body" >/dev/null \
        && echo "notify: opened an issue" \
        || echo "notify: could not open an issue" >&2
}

notify_push || true
notify_issue || true
