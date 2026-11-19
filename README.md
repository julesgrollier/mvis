# mvis

Open a Martini 3 trajectory in VMD, nicely rendered, with one short command.

```bash
mvis prep 03_equilibrate.pdb 03_equilibrate.xtc    # where GROMACS is (cluster)
mvis 03_equilibrate.pdb 03_equilibrate.xtc         # where VMD is (laptop)
```

- Correct bonds (from the `.tpr`, cholesterol drawn as rings), whole
  molecules, centred membrane.
- Lipids coloured by class (PC, PE, PI, SM, cholesterol, ionizable, ...),
  grey tails under coloured head beads; other styles for tails, heads and
  figures.
- Everything `prep` writes goes into one folder, `visualization/`, next to
  the structure. Your simulation files are never changed.
- No VMD console and no long paths. A small window in VMD changes the style
  and shows or hides water and ions.

## Install

Needs bash, plus VMD on the computers where you view and GROMACS where you
prepare. No Python environment (only the optional MartiniGlass needs one).

1. Download the zip: <https://github.com/julesgrollier/mvis/archive/refs/heads/main.zip>
2. Unpack it where it should stay, for example `~/tools/mvis`.
3. Run the installer once:

   ```bash
   bash ~/tools/mvis/install.sh
   ```

   It links the command `mvis` into `~/bin` or `~/.local/bin`, writes the
   settings file `~/.config/mvis/config` if there is none, and prints what
   it found. Follow what it prints:

   | It says | Do |
   |---|---|
   | the folder is not in your PATH | add the `export PATH=...` line it shows to `~/.zshrc` (macOS) or `~/.bashrc`, open a new terminal |
   | VMD not found (on a viewing computer) | write the path in the settings file, e.g. `VMD="/Applications/VMD 1.9.4a57-arm64-Rev12.app/Contents/MacOS/startup.command"` |
   | GROMACS not available (on the cluster) | load GROMACS before `mvis prep`, or write the commands that load it in the settings file: `GMX_SETUP="source /path/to/env.bash; module add gromacs"` |

4. Check: `mvis config` shows the settings in use, `mvis -h` the help.

**Nothing in the home folder** (clusters where home is small or off
limits): `bash install.sh -local`. The settings then go to a folder next to
the installation, named after it with `_settings` (for `~/tools/mvis`:
`~/tools/mvis_settings`), and the link goes to the first folder of your
PATH outside the home folder that you can write to (or `-bin FOLDER`).
That folder is kept by `mvis update`. Wherever this README says
`~/.config/mvis`, read that folder instead.

Optional, on the cluster, for `mvis prep -glass`:
`bash install.sh -glass` installs MartiniGlass 1.1.3 in its own environment
(`~/.local/share/mvis/venv`, or the `_settings` folder with `-local`).

### Update

```bash
mvis update                  # newest version
mvis update -version v0.1.0  # a given version (git tag)
```

This downloads the zip from GitHub and replaces the installation folder
(no git needed). Your settings are not in that folder and are kept. In a
git clone, use `git pull` instead. The whole folder is replaced: do not
keep your own files in it.

## Use

### 1. Prepare (cluster, in the simulation folder)

```bash
mvis prep STRUCTURE [TRAJECTORY]
```

`STRUCTURE` is a `.pdb` or `.gro` file, `TRAJECTORY` a `.xtc` or `.trr`.

| Option | Meaning | Default |
|---|---|---|
| `-s FILE` | run input file (`.tpr`): the bonds come from it | name of the structure + `.tpr` |
| `-n FILE` | index file, with the groups `System` and the centre group | `index.ndx` next to the structure |
| `-pbc LEVEL` | `none` (coordinates untouched), `whole` (molecules made whole), `mol` (whole, centred, molecules back in the box) | `mol` |
| `-cg GROUP` | index group whose centre of mass is held still in the middle of the box (see "Centring") | `Lipids` |
| `-skip N` | keep 1 frame out of N (smaller file for a slow connection) | `1` |
| `-cylinder FILE` | chain coordinate runs: the `NAME_cylinder.xvg` to prepare (see "The chain coordinate cylinder") | the one next to the trajectory or the structure, if any |
| `-glass` | also run MartiniGlass (see below) | off |
| `-p FILE` | topology for `-glass` | `topol.top` next to the structure |
| `-yes` | do not ask before overwriting | ask |

It prints the files it uses, with the defaults marked, and writes:

```
visualization/
  03_equilibrate.pdb          structure with its bonds (CONECT records)
  03_equilibrate.xtc          matching trajectory
  03_equilibrate_glass/       only with -glass
  03_equilibrate_cylinder.xvg, _slices.dat, _frames.dat, _cylinder_beads.ndx
                              only for a run with cylinder files
```

**Centring (`-pbc mol`).** The centre of mass of the `-cg` group is held
still in the middle of the box, and every molecule is put back into the
box whole. The group is followed without jumps (`trjconv -pbc nojump
-fit translation`). `trjconv -center` is not used, because it centres
the middle between the outermost atoms of the group. That point moves
whenever a lipid crosses the box edge. For membranes spanning the box,
the picture shook by about 0.5 nm per frame. When a membrane touched a
box face (a stalk run), the whole box jumped by 6 nm. What still happens,
and cannot be avoided in a periodic box: a single molecule that leaves
through one face comes back in through the opposite one. If the box
changes a lot during the run, the group stays still and the box edges
move around it (it sits in the middle of the mean box). Any group works
as `-cg`, also one split over the box edges in the first frame.

### 2. View (laptop)

With the simulation folder mounted, same file names as for `prep`:

```bash
mvis 03_equilibrate.pdb 03_equilibrate.xtc
```

Without a mount, copy the `visualization` folder and name the files in it:

```bash
rsync -a cluster:/path/to/simulation/visualization/ sim_vis/
cd sim_vis && mvis 03_equilibrate.pdb 03_equilibrate.xtc
```

| Option | Meaning | Default |
|---|---|---|
| `-style NAME` | `default`, `tails`, `heads` or `figure` | `default` |
| `-water` | show the water | hidden |
| `-ions` | show the ions | hidden |
| `-step N` | load 1 frame out of N | `1` |
| `-smooth N` | smooth the motion over 2N+1 frames | `0` |
| `-cylinder` | draw the chain coordinate cylinder of each frame (see below) | not drawn |
| `-noglass` | ignore MartiniGlass files | used if present |
| `-dry` | only print what would be opened | |

If the files were not prepared, `mvis` prints the `prep` command to run.

Styles:

| Style | Shows |
|---|---|
| `default` | head beads as spheres in the colour of the lipid class, tails as thin grey sticks, cholesterol as a ring |
| `tails` | chains as thick sticks in the colour of the lipid, unsaturated beads as white spheres, heads faded |
| `heads` | head beads only: the surfaces of the membranes |
| `figure` | as `default`, on white, with shadows and ambient occlusion (for rendering) |

In VMD, the window **mvis** (also under Extensions > Visualization > mvis)
switches style, water, ions and smoothing (and the cylinder, when its
files were prepared).

## The chain coordinate cylinder (`-cylinder`)

For runs biased along the chain coordinate (stalk formation): the cylinder
mdrun used is drawn at every frame, where it was at that time.

```bash
mvis prep 07_pull.pdb 07_pull.xtc         # finds 07_pull_cylinder.xvg
mvis 07_pull.pdb 07_pull.xtc -cylinder
```

Drawn: the tube (transparent), a disc for each slice that is filled
(blue = empty, white = half, red = full), a line of text (time, xi,
1/(s2+c2) in x and y, frozen or free), and as orange spheres the beads of
the index group `Apolar` that are inside the tube.

`prep` needs two files of the run, next to the trajectory or the structure
and named after one of them (else: `-cylinder FILE`):

- `NAME_cylinder.xvg`: one line per table mdrun printed: time (ps), xi,
  centre x y z (nm), 1/(s2+c2) x and y, dxy, frozen (0/1; may be missing).
  One header line is read:
  `# Cylinder: N slices of D nm (z), radius R nm ...`
  (and `frozen at x/y X/Y nm` in it, for the text).
- `NAME_slices.dat`: same times: time, z of the cylinder bottom (nm), the
  filling of each slice (0 to 1), bottom slice first.

In martini-LNP, `scripts/cylinder_output.sh` writes both. `prep` copies
them into `visualization/`, with the beads group of the index file (other
group: `CYLINDER_GROUP="..."` in the settings file) and a file
`TRAJECTORY_frames.dat`, see below. Run `prep` again after the cylinder
files or the trajectory changed.

### Where it is drawn

mdrun gives the cylinder in the coordinates of the original trajectory.
`prep` makes molecules whole and, by default, centres every frame: the
atoms are then elsewhere (in the test run: up to 2.6 nm in z). So `prep`
measures, for every frame it writes, by how much it moved the atoms: it
follows 5 atoms in the original and in the prepared trajectory, checks
that all were moved by the same vector (up to whole box lengths; if not,
no cylinder file is written) and writes time and shift of the frame to
`TRAJECTORY_frames.dat`. The cylinder of a frame is drawn at

    position given by mdrun + shift of that frame

brought into the box, and at each periodic image that reaches into the
box (x, y and z). This holds for `-pbc whole` and `-pbc mol`, any `-cg`,
`-skip` and `-step`: frames and tables are paired by their time. A frame
without a table within half a table interval shows no cylinder.

Limits: rectangular boxes only. The cylinder is drawn sharp at the
positions of the frame; with smoothing on, the beads are averaged over
several frames and the cylinder is not. The beads inside are marked in
VMD's `beta` field.

## Change colours, classes and drawn bonds

Two small text tables, explained in their headers:

- `presets/molecules.tsv`: residue name pattern → class → colour.
- `presets/bonds.tsv`: bonds to draw for molecules whose topology bonds
  look wrong (now: cholesterol).

To keep your changes across updates, copy a table to `~/.config/mvis/` and
edit the copy: it is used instead of the one in the package.

Styles are in `tcl/styles.tcl` (sizes, which beads, materials).

## How the bonds are made

- VMD's own bond guess (from distances) is switched off: it is meaningless
  for coarse-grained beads.
- `prep` writes the bonds and constraints of the `.tpr` into the `.pdb`
  (`gmx trjconv -conect`).
- Martini 3 cholesterol: five of its nine beads are virtual sites without
  any bond in the topology, and its constraints are long diagonals. Neither
  the `.tpr` bonds (floating beads) nor MartiniGlass (every virtual site
  tied to three beads) gives a readable ring, so `presets/bonds.tsv`
  replaces them by a ring skeleton. Those bonds are for the picture only.

### MartiniGlass (`-glass`)

For lipid systems it gives the same bonds as the `.tpr`. It is useful for
proteins (elastic and Gō networks, virtual sites). `prep -glass` runs it
inside `visualization/NAME_glass/` on a staged copy of the topology, so
that nothing lands in the simulation folder and the result can be moved;
`mvis` then takes the bonds from it, using the `cg_bonds-v6.tcl` that
MartiniGlass itself writes there.

## Limits

- More than 99,999 atoms: the atom numbers of a `.pdb` wrap, so its bond
  records are not reliable (`prep` warns). Not solved yet.
- `-glass` handles `#include` lines of the `.top` itself, not nested
  includes or `#ifdef` blocks around them.
- Lipid tails are recognised by bead name (`C1A`, `D2B`, `T1A`, and
  `CA1`, `CB2`, `CBX` for ionizable lipids); other bead names are drawn as
  head beads.
- The installation folder must not have spaces in its path.

## Tests

`tests/test_tcl.tcl` runs the VMD scripts in plain `tclsh` with stand-ins
for the VMD commands and prints the bonds and representations:

```bash
MVIS_PDB=visualization/03_equilibrate.pdb tclsh tests/test_tcl.tcl
```

`tests/test_cylinder.tcl` prints, in the same way, where the cylinder
would be drawn at given frames and which beads are inside;
`tests/check_cylinder.py` finds the beads inside the cylinder from the
original trajectory and mdrun's numbers alone. The two lists must be the
same (usage in both files). Checked like this on a 07 pull (centred, and
centred on a bead in a box corner so that the tube crosses the box edges
in x, y and z) and on an 08 window with a moving cylinder (`-pbc whole`,
`-skip 4`, `-step 3`): identical lists at every frame tried.

## Citations

If you publish pictures made with mvis, cite the tools it runs:

- **VMD**: Humphrey, W.; Dalke, A.; Schulten, K. VMD: Visual Molecular
  Dynamics. *J. Mol. Graph.* 1996, 14, 33–38.
  doi:10.1016/0263-7855(96)00018-5
- **GROMACS** (`gmx trjconv`): Abraham, M. J.; et al. GROMACS: High
  performance molecular simulations through multi-level parallelism from
  laptops to supercomputers. *SoftwareX* 2015, 1–2, 19–25.
  doi:10.1016/j.softx.2015.06.001
- **MartiniGlass** (with `-glass`): Brasnett, C.; Marrink, S. J.
  *J. Chem. Inf. Model.* 2025, 65, 3137–3141. doi:10.1021/acs.jcim.4c02277
- **Vermouth** (used by MartiniGlass): Kroon, P. C.; Grünewald, F.;
  Barnoud, J.; van Tilburg, M.; Souza, P. C. T.; Wassenaar, T. A.;
  Marrink, S. J. Martinize2 and Vermouth: Unified Framework for Topology
  Generation. *eLife* 12, RP90627. doi:10.7554/eLife.90627
- **cg_bonds** (with `-glass`; the script MartiniGlass ships): written by
  C. Arnarez, with changes by A. H. de Vries and C. Brasnett, University of
  Groningen, Apache License 2.0. No publication.

Models the presets refer to:

- **Martini 3**: Souza, P. C. T.; et al. Martini 3: a general purpose force
  field for coarse-grained molecular dynamics. *Nat. Methods* 2021, 18,
  382–388. doi:10.1038/s41592-021-01098-3
- **Martini 3 cholesterol**: Borges-Araújo, L.; et al. Martini 3
  Coarse-Grained Force Field for Cholesterol. *J. Chem. Theory Comput.*
  2023, 19, 7387–7404. doi:10.1021/acs.jctc.3c00547
