# Usage: MVIS_PDB=prepared.pdb tclsh tests/test_tcl.tcl
# Runs tcl/mvis.tcl with the stand-ins of vmd_stub.tcl and prints what a
# check needs: bonds of the first cholesterol, representations per style.
set here [file dirname [file normalize [info script]]]
source [file join $here vmd_stub.tcl]
source [file join $here .. tcl mvis.tcl]

proc bonds_of_first {resname} {
    set first ""; set out {}
    foreach atom $::atoms {
        lassign $atom i name res resid residue
        if {$res ne $resname} { continue }
        if {$first eq ""} { set first $residue }
        if {$residue != $first} { break }
        foreach j $::bonds($i) {
            if {$j > $i} { lappend out "$name-[lindex [lindex $::atoms $j] 1]" }
        }
    }
    return $out
}
puts "CHOL bonds: [lsort [bonds_of_first CHOL]]"
puts "PAPC bonds: [bonds_of_first PAPC]"
puts "total bonds: [::mvis::count_bonds 0]"
foreach style $::mvis::styles {
    ::mvis::apply_style $style
    puts "--- style $style: [llength $::reps] representations"
    foreach rep $::reps { puts "    $rep" }
}
puts "--- colours"
foreach entry $::log { if {[lindex $entry 0] eq "color"} { puts "    $entry" } }
