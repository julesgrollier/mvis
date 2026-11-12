#!/usr/bin/env bash
# ==============================================================================
# install.sh - finish the installation of mvis on this computer
# ==============================================================================
#
#   bash install.sh [-local] [-bin FOLDER] [-glass]
#
# Run it once from the unpacked folder (and again after moving the folder).
# It does three things, and says what it did:
#   1. puts the command "mvis" in a folder of your PATH (a link to bin/mvis)
#   2. writes the settings file "config" if there is none (VMD path if VMD
#      is found; an existing file is never changed)
#   3. with -glass: installs MartiniGlass in its own Python environment
#      (folder venv), for "mvis prep -glass"
#
# Where things go:
#   default   settings in ~/.config/mvis, MartiniGlass in ~/.local/share/mvis,
#             the link in ~/bin or ~/.local/bin
#   -local    NOTHING in the home folder: settings and MartiniGlass in the
#             folder NAME_settings next to the installation folder NAME
#             (kept by "mvis update"), the link in the first folder of the
#             PATH outside the home folder that you can write to
#   -bin FOLDER   the folder for the link, whatever the mode
#
# Nothing else is installed: mvis itself needs only bash, and VMD (to view)
# or GROMACS (to prepare).
# ==============================================================================

set -o nounset -o pipefail

MARTINIGLASS_VERSION="1.1.3"        # the version mvis was tested with

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

die() { echo "ERROR: $*" >&2; exit 1; }

binDir=""
glass=no
local=no
while [ $# -gt 0 ]; do
    case "$1" in
        -h|-help|--help) sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -bin|--bin)      [ $# -ge 2 ] || die "-bin needs a folder."; binDir="$2"; shift ;;
        -glass|--glass)  glass=yes ;;
        -local|--local)  local=yes ;;
        *)               die "unknown option: $1 (try -h)" ;;
    esac
    shift
done

# A NAME_settings folder that is already there keeps being used (bin/mvis
# looks for it first).
[ -d "${ROOT}_settings" ] && local=yes
if [ "$local" = yes ]; then
    CONFIG="${ROOT}_settings/config"
    DATA_DIR="${ROOT}_settings"
else
    CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/mvis/config"
    DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mvis"
fi

echo "mvis $(cat "$ROOT/VERSION") in $ROOT"
[ "$local" = yes ] && echo "local installation: nothing is written in $HOME"
chmod +x "$ROOT/bin/mvis" "$ROOT/libexec/martini_conect.sh"

# ---- 1. the command ----------------------------------------------------------

on_path() { case ":$PATH:" in *":$1:"*) return 0 ;; esac; return 1; }

if [ -z "$binDir" ] && [ "$local" = yes ]; then
    oldIFS="$IFS"; IFS=":"
    for candidate in $PATH; do
        case "$candidate" in "$HOME"|"$HOME"/*|"") continue ;; esac
        if [ -d "$candidate" ] && [ -w "$candidate" ]; then
            binDir="$candidate"
            break
        fi
    done
    IFS="$oldIFS"
    [ -n "$binDir" ] || die "No folder of your PATH outside $HOME can be written to:" \
                            "give one with -bin FOLDER."
fi
if [ -z "$binDir" ]; then
    for candidate in "$HOME/bin" "$HOME/.local/bin"; do
        if [ -d "$candidate" ] && on_path "$candidate"; then
            binDir="$candidate"
            break
        fi
    done
    [ -n "$binDir" ] || binDir="$HOME/.local/bin"
fi
mkdir -p "$binDir" || die "Cannot create $binDir"
link="$binDir/mvis"
if [ -e "$link" ] && [ ! -L "$link" ]; then
    die "$link exists and is not a link: remove it, or choose another folder with -bin."
fi
ln -sfn "$ROOT/bin/mvis" "$link" || die "Cannot write $link"
echo "1. command:  $link -> $ROOT/bin/mvis"
if ! on_path "$binDir"; then
    echo "   $binDir is not in your PATH. Add this line to ~/.zshrc (macOS) or"
    echo "   ~/.bashrc, then open a new terminal:"
    echo "     export PATH=\"$binDir:\$PATH\""
fi

# ---- 2. the settings file ----------------------------------------------------

vmd=""
if command -v vmd > /dev/null; then
    vmd="$(command -v vmd)"
else
    for candidate in /Applications/VMD*.app/Contents/MacOS/startup.command \
                     "$HOME"/Applications/VMD*.app/Contents/MacOS/startup.command; do
        [ -x "$candidate" ] && vmd="$candidate"
    done
fi

if [ -f "$CONFIG" ]; then
    echo "2. settings: $CONFIG exists, not changed"
else
    mkdir -p "$(dirname "$CONFIG")" || die "Cannot create $(dirname "$CONFIG")"
    cat > "$CONFIG" <<CONFIG_END
# Settings of mvis on this computer (read by bash: NAME="value", no spaces
# around =). Lines starting with # are not used: the default applies.
# Show the settings in use: mvis config

# The VMD program. Empty: "vmd" of the PATH, else /Applications/VMD*.app.
VMD="$vmd"

# Commands that load GROMACS when "gmx" is not already available
# (only needed for "mvis prep", i.e. on the cluster). Example:
#GMX_SETUP="source /path/to/env.bash; module add gromacs"

# The martiniglass program (only for "mvis prep -glass"). Empty: looked for
# in the PATH, then in $DATA_DIR/venv.
#MARTINIGLASS=""

# Style used when -style is not given: default, tails, heads or figure.
#STYLE="default"
CONFIG_END
    echo "2. settings: $CONFIG written"
fi
if [ -n "$vmd" ]; then
    echo "   VMD found: $vmd"
else
    echo "   VMD not found (fine on a cluster). On a computer where you view:"
    echo "   write its path in $CONFIG, e.g."
    echo "     VMD=\"/Applications/VMD 1.9.4a57-arm64-Rev12.app/Contents/MacOS/startup.command\""
fi
if command -v gmx > /dev/null; then
    echo "   GROMACS found: $(command -v gmx)"
else
    echo "   GROMACS (gmx) not available now (fine on a laptop). For mvis prep:"
    echo "   load it before, or set GMX_SETUP in $CONFIG"
fi

# ---- 3. MartiniGlass (optional) ----------------------------------------------

if [ "$glass" = yes ]; then
    command -v python3 > /dev/null || die "python3 is needed for MartiniGlass."
    python3 -m venv "$DATA_DIR/venv" || die "Could not create $DATA_DIR/venv"
    "$DATA_DIR/venv/bin/pip" install --quiet --no-cache-dir "martiniglass==$MARTINIGLASS_VERSION" \
        || die "Could not install MartiniGlass (network?)."
    echo "3. MartiniGlass $MARTINIGLASS_VERSION: $DATA_DIR/venv/bin/martiniglass"
else
    echo "3. MartiniGlass: not installed (optional; bash install.sh -glass)"
fi

echo "Done. Try: mvis -h"
