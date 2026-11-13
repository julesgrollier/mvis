#!/usr/bin/env python3
"""
Check of where mvis draws the cylinder, made another way.

    check_cylinder.py CYLINDER.xvg SLICES.dat BEADS.ndx TIME ORIGINAL.gro
                      [INSIDE.txt]

ORIGINAL.gro is one frame of the ORIGINAL trajectory (not prepared), at
TIME ps (gmx trjconv -dump TIME). With the cylinder of that time as mdrun
printed it (nm, coordinates of the original trajectory), the beads of
BEADS.ndx inside it are found: lateral distance to the axis below the
radius (nearest periodic image), z between bottom and top (nearest image
of the middle). Printed: their number, and per slice the number of beads
next to the filling psi mdrun printed (beads where psi is high: the
cylinder is where mdrun had it).

INSIDE.txt: atom numbers that tests/test_cylinder.tcl found inside the
tube it would draw on the prepared trajectory. The two sets must be the
same, except beads within the rounding of the files of the tube surface.
"""
import math
import re
import sys


def rows(path):
    with open(path) as handle:
        return [line.split() for line in handle
                if line.strip() and line[0] not in "#@"]


def main():
    cylinder_file, slices_file, ndx, time, gro = sys.argv[1:6]
    time = float(time)
    with open(cylinder_file) as handle:
        header = handle.read()
    thickness, radius = map(float, re.search(
        r"# Cylinder: \d+ slices of (\S+) nm \(z\), radius (\S+) nm",
        header).groups())
    row = min(rows(cylinder_file), key=lambda r: abs(float(r[0]) - time))
    slices = min(rows(slices_file), key=lambda r: abs(float(r[0]) - time))
    assert float(row[0]) == time == float(slices[0]), "no table at that time"
    x0, y0 = float(row[2]), float(row[3])
    bottom = float(slices[1])
    psi = [float(value) for value in slices[2:]]
    top = bottom + len(psi) * thickness
    middle = 0.5 * (bottom + top)

    with open(gro) as handle:
        lines = handle.read().splitlines()
    box = [float(value) for value in lines[-1].split()[:3]]
    beads = [int(number) for line in open(ndx) if "[" not in line
             for number in line.split()]

    inside = {}
    margin = {}
    for number in beads:
        line = lines[number + 1]
        x, y, z = (float(line[20:28]), float(line[28:36]), float(line[36:44]))
        dx = x - x0
        dy = y - y0
        dz = z - middle
        dx -= box[0] * round(dx / box[0])
        dy -= box[1] * round(dy / box[1])
        dz -= box[2] * round(dz / box[2])
        lateral = math.hypot(dx, dy)
        # distance to the surface of the tube (negative: inside)
        margin[number] = max(lateral - radius, abs(dz) - 0.5 * (top - bottom))
        if margin[number] < 0:
            inside[number] = int((dz + 0.5 * (top - bottom)) / thickness)

    print("t %g ps: cylinder at x/y %.4f/%.4f nm, z %.4f to %.4f nm, radius"
          " %g nm, box %s" % (time, x0, y0, bottom, top, radius, box))
    print("%d of %d beads inside (original trajectory)"
          % (len(inside), len(beads)))
    counts = [0] * len(psi)
    for index in inside.values():
        counts[min(index, len(psi) - 1)] += 1
    print("slice: beads / psi   " + "  ".join(
        "%d/%.2f" % (count, value) for count, value in zip(counts, psi)))

    if len(sys.argv) > 6:
        drawn = {int(line) for line in open(sys.argv[6]) if line.strip()}
        different = sorted(drawn ^ set(inside))
        print("%d inside the tube mvis draws (prepared trajectory); %d in"
              " one set only" % (len(drawn), len(different)))
        for number in different:
            print("   atom %d: %.3f nm from the tube surface"
                  % (number, margin[number]))
        worst = max([abs(margin[n]) for n in different], default=0.0)
        if worst > 0.03:
            sys.exit("FAILED: beads %.3f nm from the surface differ" % worst)
        print("OK")


main()
