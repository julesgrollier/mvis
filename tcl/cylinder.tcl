# ==============================================================================
# cylinder.tcl - the chain coordinate cylinder, drawn at every frame
# ==============================================================================
#
# For runs with the chain coordinate (stalk formation): draws the cylinder
# mdrun used at the time of each frame. Used with "mvis ... -cylinder" or
# the box "cylinder" of the mvis window. The files, all written into
# visualization/ by "mvis prep" (NAME = the trajectory without extension):
#
#   NAME_cylinder.xvg   one line per table of mdrun: time (ps), xi, centre
#                       x y z (nm), 1/(s2+c2) x and y, dxy, frozen (0/1,
#                       may be missing). Header line used:
#                       "# Cylinder: N slices of D nm (z), radius R nm ..."
#   NAME_slices.dat     same times: time, z of the cylinder bottom (nm),
#                       filling psi of every slice (0 to 1), bottom first
#   NAME_frames.dat     one line per frame of the prepared trajectory:
#                       time (ps), shift x y z (nm), box x y z (nm)
#   NAME_cylinder_beads.ndx   optional: the atoms (numbered from 1) shown
#                       when they are inside the cylinder
#
# The first two are copies of the files of the simulation (martini-LNP:
# scripts/cylinder_output.sh writes them); the last two are made by prep.
#
# Where the cylinder is drawn
# ---------------------------
# mdrun gives the cylinder in the coordinates of the original trajectory.
# The prepared trajectory has whole molecules and, by default, is centred:
# every atom of a frame is moved by one vector, the shift of that frame
# (measured by prep, libexec/frame_shifts.sh), and by whole box lengths.
# So the cylinder is drawn at
#     (x, y, z) + shift of the frame,
# brought into the box, and again at each periodic image that reaches into
# the box (x, y and z). Lengths: the files are in nm, VMD works in
# Angstrom: everything is multiplied by 10 here, nothing else is scaled.
# Each frame is paired with the table of the same time (from
# NAME_frames.dat, so -skip and -step are taken into account); a frame
# without a table within half a table interval shows no cylinder.
#
# Drawn: the tube (transparent), a disc for every slice with psi > 0.01
# coloured by psi (blue 0, white 0.5, red 1), a line of text (time, xi,
# 1/(s2+c2), frozen or free), and as spheres the beads of
# NAME_cylinder_beads.ndx that are inside one of the tube's images.
# ==============================================================================

namespace eval ::mvis {
    variable cylinder ""        ;# dict of what was read; "" = no files
    variable showCylinder 0
    variable cylinderDrawn {}   ;# ids of the graphics drawn for this frame
    variable cylinderRep ""     ;# name of the representation of the beads
    variable cylinderMinPsi 0.01
}

proc ::mvis::cylinder_rows {path} {
    # Data rows of an .xvg/.dat file (lines not starting with # or @).
    set rows {}
    set handle [open $path r]
    while {[gets $handle line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] in {# @}} { continue }
        lappend rows $line
    }
    close $handle
    return $rows
}

proc ::mvis::cylinder_beads {path} {
    # Atom numbers of the first group of an index file, as VMD indices
    # (GROMACS counts from 1, VMD from 0).
    set indices {}
    foreach line [cylinder_rows $path] {
        if {[string index $line 0] eq "\["} { continue }
        foreach number $line { lappend indices [expr {$number - 1}] }
    }
    return $indices
}

proc ::mvis::cylinder_load {prefix step} {
    # Read the files PREFIX_cylinder.xvg, PREFIX_slices.dat,
    # PREFIX_frames.dat (and PREFIX_cylinder_beads.ndx). STEP: every
    # STEP-th frame of the trajectory was loaded. Returns 1 if usable.
    variable mol
    variable cylinder

    set cylinder ""
    set cylinderFile ${prefix}_cylinder.xvg
    set slicesFile ${prefix}_slices.dat
    set framesFile ${prefix}_frames.dat
    foreach file [list $cylinderFile $slicesFile $framesFile] {
        if {![file exists $file]} {
            say "cylinder: no $file"
            return 0
        }
    }

    set handle [open $cylinderFile r]
    set text [read $handle]
    close $handle
    if {![regexp {# Cylinder: \d+ slices of ([0-9.eE+-]+) nm \(z\), radius ([0-9.eE+-]+) nm} \
              $text -> thickness radius]} {
        say "cylinder: no '# Cylinder: N slices of D nm (z), radius R nm' line in $cylinderFile"
        return 0
    }
    set frozenAt ""
    regexp {frozen at x/y ([0-9.]+)/([0-9.]+) nm} $text -> frozenX frozenY
    if {[info exists frozenX]} { set frozenAt "$frozenX/$frozenY" }

    set rows [cylinder_rows $cylinderFile]
    set slices [cylinder_rows $slicesFile]
    if {[llength $rows] == 0 || [llength $slices] != [llength $rows]} {
        say "cylinder: $cylinderFile and $slicesFile do not have the same\
             number of lines: write them again, then mvis prep"
        return 0
    }
    set times {}
    foreach row $rows slice $slices {
        if {abs([lindex $row 0] - [lindex $slice 0]) > 1e-3} {
            say "cylinder: $cylinderFile and $slicesFile do not have the same times"
            return 0
        }
        lappend times [lindex $row 0]
    }
    # Half the interval between two tables: how far a frame may be from one.
    set tolerance 1e9
    if {[llength $times] > 1} {
        set tolerance [expr {([lindex $times 1] - [lindex $times 0]) / 2.0 + 1e-3}]
    }

    # The frames loaded in VMD: every STEP-th line of the frames file.
    set frames {}
    set number 0
    foreach line [cylinder_rows $framesFile] {
        if {$number % $step == 0} { lappend frames $line }
        incr number
    }
    set loaded [molinfo $mol get numframes]
    if {[llength $frames] != $loaded} {
        say "WARNING: cylinder: $loaded frames loaded, [llength $frames] in\
             $framesFile: run mvis prep again. No cylinder on the frames\
             without a line."
    }

    set beads {}
    set beadsFile ${prefix}_cylinder_beads.ndx
    if {[file exists $beadsFile]} {
        set beads [cylinder_beads $beadsFile]
        set all [atomselect $mol all]
        set count [$all num]
        $all delete
        foreach index $beads {
            if {$index < 0 || $index >= $count} {
                say "cylinder: $beadsFile names atoms that are not in the\
                     structure: no beads shown"
                set beads {}
                break
            }
        }
    }
    if {[llength $beads] > 0} {
        # Marked in the beta field: a selection text can then name them
        # without listing thousands of numbers at every frame.
        set all [atomselect $mol all]
        $all set beta 0
        $all delete
        set marked [atomselect $mol "index $beads"]
        $marked set beta 1
        $marked delete
    }

    set cylinder [dict create times $times rows $rows slices $slices \
                      frames $frames tolerance $tolerance \
                      thickness $thickness radius $radius \
                      frozenAt $frozenAt beads [llength $beads]]
    say "cylinder: [llength $rows] tables ([lindex $times 0] to\
         [lindex $times end] ps), radius $radius nm, [llength $beads] beads\
         to show inside"
    return 1
}

proc ::mvis::cylinder_table {time} {
    # Index of the table nearest to TIME (ps), or -1 if none is within
    # half a table interval.
    variable cylinder
    set times [dict get $cylinder times]
    set i [lsearch -real -sorted -bisect $times $time]
    set best -1
    set bestGap 1e30
    foreach j [list $i [expr {$i + 1}]] {
        if {$j < 0 || $j >= [llength $times]} { continue }
        set gap [expr {abs([lindex $times $j] - $time)}]
        if {$gap < $bestGap} { set best $j; set bestGap $gap }
    }
    if {$best < 0 || $bestGap > [dict get $cylinder tolerance]} { return -1 }
    return $best
}

proc ::mvis::cylinder_geometry {frame} {
    # Where the cylinder is at FRAME (number of the loaded frame), in
    # Angstrom, in the coordinates of the prepared trajectory. Returns a
    # dict: note (why there is none, else ""), and if there is one:
    #   time, row (the line of the table), radius, thickness, psi
    #   xy    list of {x y}: the axis and its periodic images in x, y
    #   z     list of {bottom top}: the same in z
    #   box   {a b c}
    # xy and z hold all nine and three images; "inBox" tells for each
    # whether the tube there reaches into the box (those are drawn).
    variable cylinder
    set frames [dict get $cylinder frames]
    if {$frame < 0 || $frame >= [llength $frames]} {
        return [dict create note "no time known for this frame"]
    }
    lassign [lindex $frames $frame] time shiftX shiftY shiftZ boxA boxB boxC
    set i [cylinder_table $time]
    if {$i < 0} {
        return [dict create note "t [format %.0f $time] ps: no table" time $time]
    }
    set row [lindex [dict get $cylinder rows] $i]
    set slice [lindex [dict get $cylinder slices] $i]
    set psi [lrange $slice 2 end]

    # nm -> Angstrom
    set boxA [expr {10.0 * $boxA}]
    set boxB [expr {10.0 * $boxB}]
    set boxC [expr {10.0 * $boxC}]
    set radius [expr {10.0 * [dict get $cylinder radius]}]
    set thickness [expr {10.0 * [dict get $cylinder thickness]}]
    # original position + shift of the frame
    set x [expr {10.0 * ([lindex $row 2] + $shiftX)}]
    set y [expr {10.0 * ([lindex $row 3] + $shiftY)}]
    set bottom [expr {10.0 * ([lindex $slice 1] + $shiftZ)}]
    set top [expr {$bottom + [llength $psi] * $thickness}]
    # into the box: the axis in x and y, the middle of the tube in z
    set x [expr {$x - $boxA * floor($x / $boxA)}]
    set y [expr {$y - $boxB * floor($y / $boxB)}]
    set middle [expr {0.5 * ($bottom + $top)}]
    set back [expr {$boxC * floor($middle / $boxC)}]
    set bottom [expr {$bottom - $back}]
    set top [expr {$top - $back}]

    set xy {}
    set xyInBox {}
    foreach ix {0 -1 1} {
        foreach iy {0 -1 1} {
            set cx [expr {$x + $ix * $boxA}]
            set cy [expr {$y + $iy * $boxB}]
            lappend xy [list $cx $cy]
            lappend xyInBox [expr {$cx + $radius > 0 && $cx - $radius < $boxA
                                   && $cy + $radius > 0 && $cy - $radius < $boxB}]
        }
    }
    set z {}
    set zInBox {}
    foreach iz {0 -1 1} {
        set z0 [expr {$bottom + $iz * $boxC}]
        set z1 [expr {$top + $iz * $boxC}]
        lappend z [list $z0 $z1]
        lappend zInBox [expr {$z1 > 0 && $z0 < $boxC}]
    }
    return [dict create note "" time $time row $row psi $psi \
                radius $radius thickness $thickness \
                xy $xy xyInBox $xyInBox z $z zInBox $zInBox \
                box [list $boxA $boxB $boxC]]
}

proc ::mvis::cylinder_selection {geometry} {
    # Selection text: the marked beads inside the tube or one of its
    # periodic images (all of them: whole molecules reach out of the box).
    set r2 [format %.3f [expr {[dict get $geometry radius] ** 2}]]
    set discs {}
    foreach centre [dict get $geometry xy] {
        lassign $centre cx cy
        # sqr(x-12.300) or sqr(x+4.100): no "x--4.1"
        lappend discs "sqr(x[format %+.3f [expr {-$cx}]])+sqr(y[format %+.3f [expr {-$cy}]]) < $r2"
    }
    set layers {}
    foreach range [dict get $geometry z] {
        lassign $range z0 z1
        lappend layers "(z > [format %.3f $z0] and z < [format %.3f $z1])"
    }
    return "beta > 0 and ([join $discs { or }]) and ([join $layers { or }])"
}

proc ::mvis::cylinder_graphics {args} {
    # graphics command on the molecule; the ids of what is drawn are kept.
    variable mol
    variable cylinderDrawn
    set id [graphics $mol {*}$args]
    if {[lindex $args 0] ni {color material materials}} { lappend cylinderDrawn $id }
}

proc ::mvis::cylinder_clear {} {
    variable mol
    variable cylinderDrawn
    foreach id $cylinderDrawn { catch {graphics $mol delete $id} }
    set cylinderDrawn {}
}

proc ::mvis::cylinder_draw {} {
    variable mol
    variable cylinder
    variable style
    variable cylinderMinPsi

    cylinder_clear
    set textColor [expr {$style eq "figure" ? "black" : "white"}]
    set geometry [cylinder_geometry [molinfo $mol get frame]]
    if {[dict get $geometry note] ne ""} {
        cylinder_graphics color $textColor
        cylinder_graphics text {0 0 0} "cylinder: [dict get $geometry note]" size 1.2
        cylinder_beads_rep "none"
        return
    }
    set radius [dict get $geometry radius]
    set thickness [dict get $geometry thickness]
    set psi [dict get $geometry psi]
    set firstScale [colorinfo num]
    set scaleSteps [expr {[colorinfo max] - $firstScale - 1}]
    set labelAt ""

    catch {graphics $mol materials on}
    foreach centre [dict get $geometry xy] xyIn [dict get $geometry xyInBox] {
        lassign $centre cx cy
        foreach range [dict get $geometry z] zIn [dict get $geometry zInBox] {
            if {!$xyIn || !$zIn} { continue }
            lassign $range bottom top
            if {$labelAt eq ""} { set labelAt [list $cx $cy [expr {$top + 10.0}]] }
            cylinder_graphics material Transparent
            cylinder_graphics color silver
            cylinder_graphics cylinder [list $cx $cy $bottom] [list $cx $cy $top] \
                radius $radius resolution 36 filled no
            cylinder_graphics material Opaque
            set k 0
            foreach p $psi {
                if {$p > $cylinderMinPsi} {
                    set p [expr {min(1.0, max(0.0, $p))}]
                    cylinder_graphics color [expr {$firstScale + int(round($p * $scaleSteps))}]
                    set z0 [expr {$bottom + $k * $thickness}]
                    cylinder_graphics cylinder [list $cx $cy $z0] \
                        [list $cx $cy [expr {$z0 + 0.6 * $thickness}]] \
                        radius [expr {0.97 * $radius}] resolution 36 filled yes
                }
                incr k
            }
        }
    }

    # time, xi, spread, frozen or free at this time (last column; files
    # without it: a frozen cylinder was frozen for the whole run)
    lassign [dict get $geometry row] time xi x y z spreadX spreadY move isFrozen
    set state free
    if {[dict get $cylinder frozenAt] ne "" && $isFrozen ne "0"} {
        set state "frozen at x/y [dict get $cylinder frozenAt] nm"
    }
    if {$labelAt eq ""} { set labelAt {0 0 0} }
    cylinder_graphics material Opaque
    cylinder_graphics color $textColor
    cylinder_graphics text $labelAt \
        [format "t %.0f ps  xi %.3f  1/(s2+c2) %.1f %.1f  (%s)" \
             $time $xi $spreadX $spreadY $state] size 1.2

    cylinder_beads_rep [cylinder_selection $geometry]
}

proc ::mvis::cylinder_beads_rep {selection} {
    # Give the representation of the beads its selection of this frame
    # (made again if a change of style removed it).
    variable mol
    variable cylinder
    variable cylinderRep
    if {[dict get $cylinder beads] == 0} { return }
    set rep -1
    if {$cylinderRep ne ""} { set rep [mol repindex $mol $cylinderRep] }
    if {$rep < 0} {
        set rep [rep $selection [vdw 1.0] {ColorID 3} Opaque]
        set cylinderRep [mol repname $mol $rep]
    } else {
        mol modselect $rep $mol $selection
    }
}

proc ::mvis::cylinder_on_frame {args} {
    variable showCylinder
    if {$showCylinder} { cylinder_draw }
}

proc ::mvis::show_cylinder {} {
    # Draw or remove the cylinder, following ::mvis::showCylinder (option
    # -cylinder, box of the window). Also called after a change of style.
    variable mol
    variable cylinder
    variable showCylinder
    variable cylinderRep

    if {$cylinder eq ""} {
        set showCylinder 0
        return
    }
    set callback [list ::mvis::cylinder_on_frame]
    catch {trace remove variable ::vmd_frame($mol) write $callback}
    if {$showCylinder} {
        catch {color scale method BWR}
        trace add variable ::vmd_frame($mol) write $callback
        cylinder_draw
    } else {
        cylinder_clear
        if {$cylinderRep ne ""} {
            set rep [mol repindex $mol $cylinderRep]
            if {$rep >= 0} { mol delrep $rep $mol }
            set cylinderRep ""
        }
    }
}
