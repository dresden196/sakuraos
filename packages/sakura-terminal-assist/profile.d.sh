# Login shells. Interactive non-login shells -- a terminal window inside a
# desktop session -- are covered from /etc/bash.bashrc instead, because shell
# functions and traps are not inherited by child shells.
[ -r /usr/share/sakura/terminal-assist.sh ] && . /usr/share/sakura/terminal-assist.sh
