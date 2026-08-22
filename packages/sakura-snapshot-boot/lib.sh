# Shared snapshot logic for SakuraOS.
#
# Sourced both by tools on a running system and by the recovery initramfs, so
# it must stay POSIX sh and use only busybox-grade utilities. No xmllint, no
# bash arrays, no snapper -- snapper is not present in an initramfs.

# Where snapper keeps its snapshots, relative to the btrfs top-level.
SAKURA_SNAPSHOT_SUBVOL="${SAKURA_SNAPSHOT_SUBVOL:-@snapshots}"
# The subvolume that is the live root. Rollback replaces what this *is*, rather
# than pointing the kernel at a different subvolume -- which is what lets the
# kernel command line stay constant, embedded, and signed.
SAKURA_ROOT_SUBVOL="${SAKURA_ROOT_SUBVOL:-@}"

# Pull one element's text out of a snapper info.xml. Snapper writes these one
# tag per line, so a line-oriented parser is sufficient and avoids depending on
# an XML parser in early boot.
sakura_xml_field() {
    sed -n "s|.*<$2>\(.*\)</$2>.*|\1|p" "$1" 2>/dev/null | head -1
}

# List snapshots as tab-separated: number, type, date, description.
# Sorted newest first, which is the order a person wants to see them in.
#
# $1 - path to the mounted @snapshots subvolume
sakura_list_snapshots() {
    _root="$1"
    [ -d "$_root" ] || return 0

    for _dir in "$_root"/*; do
        [ -d "$_dir" ] || continue
        _num="${_dir##*/}"
        # Snapper names snapshot directories by number; skip anything else so a
        # stray directory cannot produce a bogus menu entry.
        case "$_num" in
            ''|*[!0-9]*) continue ;;
        esac
        # A snapshot with no subvolume is a half-deleted one. Offering it would
        # produce a rollback that silently restores nothing.
        [ -d "$_dir/snapshot" ] || continue

        _info="$_dir/info.xml"
        _type=$(sakura_xml_field "$_info" type)
        _date=$(sakura_xml_field "$_info" date)
        _desc=$(sakura_xml_field "$_info" description)

        printf '%s\t%s\t%s\t%s\n' \
            "$_num" "${_type:-unknown}" "${_date:-unknown}" "${_desc:-no description}"
    done | sort -rn
}

# Human-facing one-liner for a snapshot, used by both the recovery menu and
# the update manager so the two never disagree about what a snapshot is called.
sakura_describe_snapshot() {
    printf '%s  %s' "$2" "$4"
}
