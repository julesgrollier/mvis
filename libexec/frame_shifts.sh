#!/usr/bin/env bash
# ==============================================================================
# frame_shifts.sh - for every frame of a prepared trajectory: its time and by
#                   how much the preparation moved the coordinates
# ==============================================================================
#
# Part of mvis (called by "mvis prep" when there is something to draw at
# positions of the original trajectory, now: the cylinder). Needs bash, awk
# and GROMACS.
#
#   frame_shifts.sh -s TPR -f ORIGINAL -p PREPARED -natoms N [-skip N] -o OUT
#
# PREPARED was made from ORIGINAL by martini_conect.sh (frame k of PREPARED
# is frame k x skip of ORIGINAL). Making molecules whole moves atoms by
# whole box lengths only; centring moves all atoms of a frame by one and the
# same vector. So, up to whole box lengths,
#
#     position in PREPARED = position in ORIGINAL + shift(frame)
#
# and a point given in the coordinates of ORIGINAL (the cylinder centre
# mdrun printed) belongs, in PREPARED, at point + shift, or at any periodic
# image of that.
#
# The shift is measured, not derived from the options used: a few atoms
# spread over the system are followed in both trajectories. All of them
# must give the same shift (up to box lengths): if not, the two files are
# not the same frames and nothing is written.
#
# OUT, one line per frame of PREPARED, in nm:
#     time(ps)  shift x y z  box x y z
# The shift is given between 0 and the box length.
# ==============================================================================

set -o nounset -o pipefail

PROGRAM="$(basename "$0")"
TRACKED=5                   # atoms followed
TOLERANCE=0.05              # nm; .xtc files are rounded to 0.001-0.01 nm

die()
{
    echo "ERROR: $*" >&2
    exit 1
}

tpr=""
original=""
prepared=""
output=""
atoms=""
skip=1
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || die "$PROGRAM: $1 needs a value."
    case "$1" in
        -s)      tpr="$2" ;;
        -f)      original="$2" ;;
        -p)      prepared="$2" ;;
        -o)      output="$2" ;;
        -natoms) atoms="$2" ;;
        -skip)   skip="$2" ;;
        *)       die "$PROGRAM: unknown option: $1" ;;
    esac
    shift 2
done
for value in "$tpr" "$original" "$prepared" "$output" "$atoms"; do
    [ -n "$value" ] || die "$PROGRAM: -s, -f, -p, -natoms and -o are required."
done
for file in "$tpr" "$original" "$prepared"; do
    [ -f "$file" ] || die "File not found: $file"
done
[ "$atoms" -ge 1 ] 2> /dev/null || die "$PROGRAM: -natoms must be a number, got: $atoms"

if ! command -v gmx > /dev/null; then
    [ -n "${MVIS_GMX_SETUP:-}" ] \
        || die "No gmx on the PATH: load GROMACS first, or give the commands" \
               "that load it in MVIS_GMX_SETUP."
    set +u
    eval "$MVIS_GMX_SETUP" > /dev/null 2>&1     # (module messages not shown)
    set -u
    command -v gmx > /dev/null \
        || die "Still no gmx after running MVIS_GMX_SETUP: $MVIS_GMX_SETUP"
fi
export GMX_MAXBACKUP=-1

workDir=$(mktemp -d "$(dirname "$output")/.frame_shifts.XXXXXX") \
    || die "Cannot write into $(dirname "$output")"
trap 'rm -rf "$workDir"' EXIT

# The atoms followed: spread evenly over the atom numbers (different
# molecules, so that they are moved independently by -pbc whole / mol).
awk -v n="$atoms" -v k="$TRACKED" 'BEGIN {
    print "[ tracked ]"
    if (n < k) k = n
    for (i = 0; i < k; i++)
        print (k > 1) ? 1 + int(i * (n - 1) / (k - 1)) : 1
}' > "$workDir/tracked.ndx"

track()
{
    # Usage: track TRAJECTORY OUTPUT.gro [trjconv options]
    # The followed atoms of every frame, as a .gro file: it holds the time
    # in full (gmx traj rounds it to 6 digits) and the box.
    local trajectory="$1" out="$2"
    shift 2
    echo 0 | gmx trjconv -s "$tpr" -f "$trajectory" -n "$workDir/tracked.ndx" \
        -o "$out" -ndec 4 "$@" > "$workDir/gmx.out" 2>&1 && return
    cat "$workDir/gmx.out" >&2
    die "gmx trjconv failed on $trajectory (output above)."
}

track "$original" "$workDir/original.gro" -skip "$skip"
track "$prepared" "$workDir/prepared.gro"

awk -v tolerance="$TOLERANCE" -v originalName="$original" -v preparedName="$prepared" '
    function fail(text) {
        print "ERROR: " text > "/dev/stderr"
        failed = 1
        exit 1
    }
    function wrap(value, size) {      # into 0 <= value < length
        value -= size * int(value / size)
        if (value < 0) value += size
        if (value >= size) value = 0
        return value
    }
    function nearest(value, size) {   # value minus whole box lengths, nearest 0
        return value - size * int(value / size + (value >= 0 ? 0.5 : -0.5))
    }
    # One frame of a .gro file: title, number of atoms, atoms, box.
    # Returns 0 at the end of the file. Fills time, n, pos[k,d], box[d].
    function read_frame(file,    line, k, parts, count) {
        if ((getline line < file) <= 0) return 0
        if (!match(line, /t= *[-0-9.eE+]+/)) fail("no time in " file ": " line)
        time = substr(line, RSTART + 2, RLENGTH - 2) + 0
        getline line < file
        n = line + 0
        for (k = 1; k <= n; k++) {
            getline line < file
            # after the 20 columns of names and numbers: 3 x %9.4f (-ndec 4)
            pos[k, 1] = substr(line, 21, 9) + 0
            pos[k, 2] = substr(line, 30, 9) + 0
            pos[k, 3] = substr(line, 39, 9) + 0
        }
        getline line < file
        count = split(line, parts, " ")
        for (k = 4; k <= count; k++)
            if (parts[k] + 0 != 0)
                fail("the box is not rectangular: the shift of the frames is not worked out for such boxes.")
        if (count < 3) fail("no box in " file)
        box[1] = parts[1] + 0; box[2] = parts[2] + 0; box[3] = parts[3] + 0
        return 1
    }
    BEGIN {
        frames = 0
        worst = 0
        while (read_frame(ARGV[2])) {
            preparedTime = time
            for (d = 1; d <= 3; d++) preparedBox[d] = box[d]
            for (k = 1; k <= n; k++)
                for (d = 1; d <= 3; d++) preparedPos[k, d] = pos[k, d]
            preparedN = n
            if (!read_frame(ARGV[1]))
                fail(preparedName " has more frames than " originalName " (with -skip): prepared from another file?")
            if (time != preparedTime)
                fail("frame " frames ": time " preparedTime " ps in " preparedName ", " time " ps in " originalName ": not the same frames.")
            if (n != preparedN) fail("frame " frames ": different numbers of atoms.")
            for (d = 1; d <= 3; d++) {
                if (box[d] <= 0) fail("frame " frames ": no box.")
                difference = box[d] - preparedBox[d]
                if (difference > 0.002 || difference < -0.002)
                    fail("frame " frames ": the boxes differ: not the same frames.")
                # Shift seen by each atom, brought next to that of the first
                # (they may differ by whole box lengths), then averaged.
                first = preparedPos[1, d] - pos[1, d]
                sum = 0
                for (k = 1; k <= n; k++) {
                    apart = nearest(preparedPos[k, d] - pos[k, d] - first, box[d])
                    if (apart > worst) worst = apart
                    if (-apart > worst) worst = -apart
                    if (apart > tolerance || apart < -tolerance)
                        fail("frame " frames " (" time " ps): the atoms followed are not all moved by the same vector (" apart " nm apart): " preparedName " is not " originalName " made whole / centred.")
                    sum += first + apart
                }
                shift[d] = wrap(sum / n, box[d])
            }
            printf "%.3f %.4f %.4f %.4f %.4f %.4f %.4f\n", time,
                   shift[1], shift[2], shift[3], box[1], box[2], box[3]
            frames++
        }
        if (frames == 0) fail("no frame read from " preparedName)
        printf "%d frames, %d atoms followed, their shifts agree within %.3f nm\n",
               frames, n, worst > "/dev/stderr"
    }
' "$workDir/original.gro" "$workDir/prepared.gro" > "$workDir/shifts.dat" \
    || die "The shift of the frames could not be worked out: nothing written."

{
    cat <<EOF
# Written by mvis prep. One line per frame of $(basename "$prepared"):
# its time, and the shift: position here = position in the original
# trajectory ($(basename "$original")) + shift, up to whole box lengths.
# Measured on $TRACKED atoms followed in both files.
# Columns: time (ps), shift x y z (nm), box x y z (nm)
EOF
    cat "$workDir/shifts.dat"
} > "$workDir/out.dat"
mv "$workDir/out.dat" "$output" || die "Cannot write $output"
