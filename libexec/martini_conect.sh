#!/usr/bin/env bash
# ==============================================================================
# martini_conect.sh - structure with CONECT records (bonds) and a matching
#                     trajectory, for viewing a Martini system (VMD, PyMOL)
# ==============================================================================
#
# Part of mvis (called by "mvis prep"); also usable alone, by hand or from
# a script (see "From a script" in the help: -h). Needs only bash, awk and
# GROMACS: no other file of the package, no other repository.
# The input files are never changed: every result is a new file.
# The index file must hold the group System and the centre group (-cg).
# ==============================================================================

set -o nounset -o pipefail

PROGRAM="$(basename "$0")"

usage()
{
    cat <<EOF
Usage: $PROGRAM -s TPR [-c STRUCTURE] [-f TRAJECTORY] [OPTIONS]

Writes a .pdb with CONECT records (the bonds of the .tpr) and without the
ENDMDL line, and/or a trajectory to load on top of it, e.g.

  $PROGRAM -s 03_equilibrate.tpr -c 03_equilibrate.pdb -f 03_equilibrate.xtc
  vmd 03_equilibrate_conect.pdb 03_equilibrate_conect.xtc

Give -c, -f or both. The input files are never changed.

Input:
  -s FILE     run input file (.tpr): bonds and molecules        (required)
  -c FILE     structure (.pdb or .gro)
  -f FILE     trajectory (.xtc or .trr)
  -n FILE     index file                           (default: index.ndx)

Output (default: next to the input, its name + _conect):
  -oc FILE    structure with CONECT records (.pdb)   (NAME_conect.pdb)
  -o FILE     trajectory                             (NAME_conect.xtc)

How far the coordinates are changed (each level includes the ones before):
  -pbc none   Coordinates as in the input. The structure only gets its
              CONECT records and loses ENDMDL. A trajectory has nothing to
              gain here: -f is not allowed.
  -pbc whole  Molecules broken over the box edges are made whole
              (trjconv -pbc whole). Nothing is moved or centred.
  -pbc mol    (default, the full process) Then the centre group is put in
              the middle of the box and every molecule back into the box
              as a whole (trjconv -pbc mol -center -ur compact).
  Use none or whole when a later script moves or cuts the structure
  itself, or when positions must stay comparable with the raw files
  (mol shifts everything by the centring).

  -cg GROUP   index group centred by -pbc mol        (default: Lipids)
  -skip N     trajectory: keep every N-th frame only      (default: 1)

Other:
  -y, -yes    do not ask for confirmation (see below)
  -h, -help, --help   this help

All options can also be written with two dashes (--pbc whole).

GROMACS:
  The gmx found on the PATH is used. If there is none, the commands in
  the environment variable MVIS_GMX_SETUP are run first to load it, e.g.
    export MVIS_GMX_SETUP='source /path/to/env.bash; module add gromacs'
  ("mvis prep" sets it from GMX_SETUP of the mvis config file).

Confirmation:
  Asked before overwriting a file and before writing into store
  (simulation data belongs in scratch). -yes answers yes to both.
  Without a terminal (called from a script, a SLURM job) nothing can be
  asked: the script then stops with an error unless -yes is given.

From a script:
  bash $PROGRAM -yes -s STEP.tpr -c STEP.pdb -f STEP.xtc || die "..."
  - the paths of the written files are printed to standard output, one per
    line (structure first); all messages go to standard error
  - a gmx already loaded by the caller is used as it is
  - chain and segment names of a .pdb input are kept (GROMACS drops them)
  - the output files appear only when complete; nothing else is left
    behind (work files are in a hidden folder, removed at the end)
  - exit status: 0 done, 1 failed or refused, 192 wrong command line
EOF
}

die()
{
    echo "ERROR: $*" >&2
    exit 1
}

usage_error()
{
    echo "ERROR: $*" >&2
    echo "Try: $PROGRAM -h" >&2
    exit 192
}


# ---- command line ------------------------------------------------------------

tpr=""
structure=""
trajectory=""
index="index.ndx"
structureOut=""
trajectoryOut=""
pbc="mol"
centerGroup="Lipids"
skip=1
assumeYes=no

while [ $# -gt 0 ]; do
    option="$1"
    case "$option" in
        --?*) option="${option#-}" ;;       # --option is the same as -option
    esac
    case "$option" in
        -h|-help)
            usage
            exit 0
            ;;
        -y|-yes)
            assumeYes=yes
            shift
            continue
            ;;
        -s|-c|-f|-n|-oc|-o|-pbc|-cg|-skip)
            [ $# -ge 2 ] || usage_error "$1 needs a value."
            ;;
        *)
            usage_error "unknown option: $1"
            ;;
    esac
    case "$option" in
        -s)   tpr="$2" ;;
        -c)   structure="$2" ;;
        -f)   trajectory="$2" ;;
        -n)   index="$2" ;;
        -oc)  structureOut="$2" ;;
        -o)   trajectoryOut="$2" ;;
        -pbc) pbc="$2" ;;
        -cg)  centerGroup="$2" ;;
        -skip) skip="$2" ;;
    esac
    shift 2
done

[ -n "$tpr" ] || usage_error "no run input file: -s FILE.tpr"
[ -n "$structure$trajectory" ] \
    || usage_error "nothing to do: give a structure (-c), a trajectory (-f)" \
                   "or both."
case "$pbc" in
    none|whole|mol) ;;
    *) usage_error "-pbc must be none, whole or mol, got: $pbc" ;;
esac
case "$skip" in
    ""|*[!0-9]*|0*) usage_error "-skip must be a whole number from 1, got: $skip" ;;
esac
if [ -n "$trajectory" ] && [ "$pbc" = none ]; then
    usage_error "-pbc none leaves a trajectory as it is: use $trajectory" \
                "itself, or -pbc whole."
fi
[ -z "$structureOut" ] || [ -n "$structure" ] \
    || usage_error "-oc without a structure (-c)."
[ -z "$trajectoryOut" ] || [ -n "$trajectory" ] \
    || usage_error "-o without a trajectory (-f)."

inputs=( "$tpr" "$index" ${structure:+"$structure"} ${trajectory:+"$trajectory"} )
for file in "${inputs[@]}"; do
    [ -f "$file" ] || die "File not found: $file"
done
case "$structure" in
    ""|*.pdb|*.gro) ;;
    *) die "The structure (-c) must be a .pdb or .gro file: $structure" ;;
esac
case "$trajectory" in
    ""|*.xtc|*.trr) ;;
    *) die "The trajectory (-f) must be a .xtc or .trr file: $trajectory" ;;
esac

if [ -n "$structure" ] && [ -z "$structureOut" ]; then
    structureOut="${structure%.*}_conect.pdb"
fi
if [ -n "$trajectory" ] && [ -z "$trajectoryOut" ]; then
    trajectoryOut="${trajectory%.*}_conect.${trajectory##*.}"
fi
case "$structureOut" in
    ""|*.pdb) ;;
    *) die "CONECT records need a .pdb file: -oc $structureOut" ;;
esac
case "$trajectoryOut" in
    ""|*.xtc|*.trr) ;;
    *) die "The trajectory output (-o) must be .xtc or .trr: $trajectoryOut" ;;
esac

if [ "$pbc" = mol ]; then
    grep -q "^\[ $centerGroup \]$" "$index" \
        || die "No group $centerGroup in $index to centre on: choose one" \
               "with -cg, or use -pbc whole."
fi


# ---- safety: overwriting, writing into store ---------------------------------

confirm()
{
    # Usage: confirm QUESTION
    [ "$assumeYes" = yes ] && return
    [ -t 0 ] || die "$1 Nobody to ask (no terminal): add -yes to allow it."
    local answer
    read -r -p "$1 Continue? [y/N] " answer
    case "$answer" in
        y|Y|yes|Yes) ;;
        *) die "Stopped, nothing written." ;;
    esac
}

outputs=( ${structureOut:+"$structureOut"} ${trajectoryOut:+"$trajectoryOut"} )
for output in "${outputs[@]}"; do
    [ -d "$(dirname "$output")" ] \
        || die "No such folder for the output: $(dirname "$output")"
    for input in "${inputs[@]}"; do
        [ "$(realpath "$output")" != "$(realpath "$input")" ] \
            || die "$output is an input file: it would be overwritten."
    done
    case "$(realpath "$output")" in
        */store/*) confirm "$(realpath "$output") is in store, not in scratch." ;;
    esac
    [ ! -e "$output" ] || confirm "$output exists and would be overwritten."
done


# ---- GROMACS ----------------------------------------------------------------

if ! command -v gmx > /dev/null; then
    [ -n "${MVIS_GMX_SETUP:-}" ] \
        || die "No gmx on the PATH: load GROMACS first, or give the commands" \
               "that load it in MVIS_GMX_SETUP (see -h)."
    # Site scripts are usually not written for "set -u": paused.
    set +u
    eval "$MVIS_GMX_SETUP" > /dev/null 2>&1     # (module messages not shown)
    set -u
    command -v gmx > /dev/null \
        || die "Still no gmx after running MVIS_GMX_SETUP: $MVIS_GMX_SETUP"
fi
# No #file.1# backups: all GROMACS output goes to a fresh work folder.
export GMX_MAXBACKUP=-1


# ---- work folder -------------------------------------------------------------
#
# Hidden, next to the output (the intermediate trajectory can be large: not
# in /tmp), removed when the script ends, also on an error.

workDir=$(mktemp -d "$(dirname "${trajectoryOut:-$structureOut}")/.martini_conect.XXXXXX") \
    || die "Cannot write into $(dirname "${trajectoryOut:-$structureOut}")"
trap 'rm -rf "$workDir"' EXIT

run_trjconv()
{
    # Usage: run_trjconv "GROUP [GROUP]" trjconv OPTIONS...
    # The groups answer the questions of trjconv (centre group if -center,
    # then output group). Its screen output is shown only if it fails.
    local groups="$1"
    shift
    printf '%s\n' $groups | gmx trjconv -s "$tpr" -n "$index" "$@" \
        > "$workDir/gmx.out" 2>&1 && return
    cat "$workDir/gmx.out" >&2
    die "gmx trjconv failed (output above)."
}

restore_pdb_labels()
{
    # Usage: restore_pdb_labels REFERENCE.pdb TARGET.pdb OUTPUT.pdb
    # Copy chain ID and SEGID from REFERENCE onto TARGET by atom order:
    # GROMACS does not keep them.
    awk '
        FNR == NR {
            if ($0 ~ /^ATOM/ || $0 ~ /^HETATM/) {
                nref++
                chain[nref] = substr($0,22,1)
                segid[nref] = substr($0,73,4)
            }
            next
        }

        /^ATOM/ || /^HETATM/ {
            ntarget++
            if (!(ntarget in chain)) {
                printf "ERROR: target contains more atoms than reference\n" > "/dev/stderr"
                exit 47
            }
            line = $0
            while (length(line) < 76)
                line = line " "
            line = substr(line,1,21) chain[ntarget] substr(line,23)
            line = substr(line,1,72) segid[ntarget] substr(line,77)
            print line
            next
        }

        { print }

        END {
            if (ntarget != nref) {
                printf "ERROR: PDB atom-count mismatch: reference=%d target=%d\n",
                       nref, ntarget > "/dev/stderr"
                exit 48
            }
        }
    ' "$1" "$2" > "$3"
}


# ---- structure ---------------------------------------------------------------

if [ -n "$structure" ]; then
    # 1. Whole molecules (-pbc whole), or whole, centred and in the box
    #    (-pbc mol).
    source="$structure"
    case "$pbc" in
        whole)
            run_trjconv "System" -f "$structure" -o "$workDir/pbc.pdb" \
                -pbc whole
            source="$workDir/pbc.pdb"
            ;;
        mol)
            run_trjconv "$centerGroup System" -f "$structure" \
                -o "$workDir/pbc.pdb" -pbc mol -center -ur compact
            source="$workDir/pbc.pdb"
            ;;
    esac

    # 2. CONECT records.
    run_trjconv "System" -f "$source" -o "$workDir/conect.pdb" -conect

    # 3. Chains and segments of the input back, ENDMDL out (viewers stop
    #    reading at ENDMDL, before the CONECT records).
    case "$structure" in
        *.pdb)
            restore_pdb_labels "$structure" "$workDir/conect.pdb" \
                "$workDir/labels.pdb" || die "Could not restore the chains."
            mv "$workDir/labels.pdb" "$workDir/conect.pdb"
            ;;
    esac
    sed -i '/^ENDMDL/d' "$workDir/conect.pdb"
    grep -q '^CONECT' "$workDir/conect.pdb" \
        || die "trjconv wrote no CONECT record: no bonds in $tpr?"
fi


# ---- trajectory --------------------------------------------------------------

if [ -n "$trajectory" ]; then
    extension="${trajectoryOut##*.}"

    # 1. Whole molecules in every frame (of the frames kept by -skip).
    run_trjconv "System" -f "$trajectory" -o "$workDir/whole.$extension" \
        -pbc whole -skip "$skip"
    result="$workDir/whole.$extension"

    # 2. Centred, molecules in the box (as the structure).
    if [ "$pbc" = mol ]; then
        run_trjconv "$centerGroup System" -f "$workDir/whole.$extension" \
            -o "$workDir/mol.$extension" -pbc mol -center -ur compact
        rm "$workDir/whole.$extension"
        result="$workDir/mol.$extension"
    fi
fi


# ---- done: the outputs appear only now, complete -----------------------------

if [ -n "$structure" ]; then
    mv "$workDir/conect.pdb" "$structureOut" || die "Cannot write $structureOut"
fi
if [ -n "$trajectory" ]; then
    mv "$result" "$trajectoryOut" || die "Cannot write $trajectoryOut"
fi

echo "Wrote (-pbc $pbc):" >&2
printf '%s\n' "${outputs[@]}"
