# SakuraOS's own system-wide defaults, searched after /etc/xdg.
#
# Files in /etc/xdg belong to whichever package ships them, and since KWin 6.8
# that includes kwinrulesrc: SakuraOS shipping its own there made pacman refuse
# every update on every machine. KConfig reads a file of the same name from
# every directory in XDG_CONFIG_DIRS and merges them, so a directory of our own
# adds SakuraOS's defaults without claiming anybody else's file. Last, so that
# /etc/xdg -- what an administrator edits -- still wins.
#
# Sourced by startplasma before KWin and the shell start, which is what makes
# it reach them.
case ":${XDG_CONFIG_DIRS:-/etc/xdg}:" in
    *:/usr/share/sakura/xdg:*) ;;
    *) export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}:/usr/share/sakura/xdg" ;;
esac
