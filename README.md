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
| `-cg GROUP` | index group put in the centre of the box | `Lipids` |
| `-skip N` | keep 1 frame out of N (smaller file for a slow connection) | `1` |
| `-glass` | also run MartiniGlass (see below) | off |
| `-p FILE` | topology for `-glass` | `topol.top` next to the structure |
| `-yes` | do not ask before overwriting | ask |

It prints the files it uses, with the defaults marked, and writes:

```
visualization/
  03_equilibrate.pdb          structure with its bonds (CONECT records)
  03_equilibrate.xtc          matching trajectory
  03_equilibrate_glass/       only with -glass
```

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
switches style, water, ions and smoothing.

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
