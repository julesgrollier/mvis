# Usage:
#   MVIS_PDB=visualization/NAME.pdb MVIS_CYLINDER=visualization/TRAJ \
#   MVIS_TEST_FRAMES="0 3" [MVIS_TEST_GRO="f0.gro f3.gro" MVIS_TEST_OUT=DIR] \
#   tclsh tests/test_cylinder.tcl
#
# Runs tcl/mvis.tcl + cylinder.tcl with the stand-ins of vmd_stub.tcl and
# prints, for each frame of MVIS_TEST_FRAMES, what would be drawn: the
# tubes (centre, bottom, top, radius; Angstrom), the number of discs, the
# text. With MVIS_TEST_GRO (one .gro per frame, the prepared trajectory at
# that frame, e.g. gmx trjconv -dump), the selection of the beads inside
# is worked out on those coordinates and the atom numbers (from 1) are
# written to MVIS_TEST_OUT/inside_FRAME.txt, to compare with a count made
# another way (tests/check_cylinder.py).
set here [file dirname [file normalize [info script]]]
source [file join $here vmd_stub.tcl]
set frames $env(MVIS_TEST_FRAMES)
set ::numframes [expr {[info exists env(MVIS_TEST_NUMFRAMES)] ? $env(MVIS_TEST_NUMFRAMES) : 11}]
set env(MVIS_CYLINDER_SHOW) 1
source [file join $here .. tcl mvis.tcl]

proc tcl::mathfunc::sqr {value} { expr {$value * $value} }

proc inside {selection groFile beads} {
    # Atom numbers (from 1) of BEADS (VMD indices) that SELECTION picks,
    # with the coordinates of GROFILE (nm -> Angstrom, as VMD does).
    regsub -all {\m(beta|x|y|z)\M} $selection {$\1} test
    set test [string map {" and " " && " " or " " || "} $test]
    set handle [open $groFile r]
    set lines [split [read $handle] \n]
    close $handle
    set beta 1
    set picked {}
    foreach index $beads {
        set line [lindex $lines [expr {$index + 2}]]
        set x [expr {10.0 * [string trim [string range $line 20 27]]}]
        set y [expr {10.0 * [string trim [string range $line 28 35]]}]
        set z [expr {10.0 * [string trim [string range $line 36 43]]}]
        if {[expr $test]} { lappend picked [expr {$index + 1}] }
    }
    return $picked
}

puts "cylinder available: [expr {$::mvis::cylinder ne ""}], shown: $::mvis::showCylinder"
set beads {}
set beadsFile $env(MVIS_CYLINDER)_cylinder_beads.ndx
if {[file exists $beadsFile]} { set beads [::mvis::cylinder_beads $beadsFile] }
set number 0
foreach frame $frames {
    set ::frame $frame
    set ::vmd_frame(0) $frame               ;# what VMD does: the trace draws
    puts "--- frame $frame"
    set discs 0
    dict for {id command} $::drawn {
        switch [lindex $command 0] {
            cylinder {
                if {[lindex $command 8] eq "no"} {
                    lassign [lindex $command 1] cx cy bottom
                    puts [format "    tube   centre %8.3f %8.3f   z %8.3f to %8.3f   radius %.3f" \
                              $cx $cy $bottom [lindex [lindex $command 2] 2] [lindex $command 4]]
                } else { incr discs }
            }
            text { puts "    text   [lindex $command 2]   at [lindex $command 1]" }
        }
    }
    puts "    discs  $discs"
    set rep [mol repindex 0 $::mvis::cylinderRep]
    if {$rep >= 0} {
        set selection [lindex [lindex [lindex $::reps $rep] 0] 0]
        puts "    beads  $selection"
        if {[info exists env(MVIS_TEST_GRO)]} {
            set found [inside $selection [lindex $env(MVIS_TEST_GRO) $number] $beads]
            puts "    beads inside: [llength $found]"
            set handle [open [file join $env(MVIS_TEST_OUT) inside_$frame.txt] w]
            puts $handle [join $found \n]
            close $handle
        }
    }
    incr number
}
# a change of style removes all representations: the beads must come back
::mvis::apply_style tails
puts "--- after a change of style: beads representation [mol repindex 0 $::mvis::cylinderRep] of [llength $::reps]"
set ::mvis::showCylinder 0
::mvis::show_cylinder
puts "--- cylinder off: [dict size $::drawn] graphics left, [llength $::reps] representations"
