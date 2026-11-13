# ==============================================================================
# mvis.tcl - VMD side of mvis: load, bonds, colours, styles, small window
# ==============================================================================
#
# Started by bin/mvis (vmd -e mvis.tcl), which passes everything through
# environment variables:
#   MVIS_ROOT        the package folder                        (required)
#   MVIS_PDB         structure with CONECT records            (required)
#   MVIS_TRAJECTORY  trajectory to load on it                 (may be empty)
#   MVIS_GLASS       folder written by MartiniGlass           (may be empty)
#   MVIS_STYLE       default, tails, heads or figure
#   MVIS_WATER, MVIS_IONS   1 = shown
#   MVIS_STEP        load every N-th frame
#   MVIS_SMOOTH      smoothing window of the representations
#   MVIS_PRESETS     folder with your own molecules.tsv / bonds.tsv (optional)
#   MVIS_CYLINDER    path prefix of the cylinder files (cylinder.tcl), if
#                    they were prepared                      (may be empty)
#   MVIS_CYLINDER_SHOW   1 = the cylinder is drawn from the start
#
# Bonds: VMD's own guess from distances is switched off (it is meaningless
# for coarse-grained beads). The bonds are those of the file (CONECT, i.e.
# the bonds and constraints of the .tpr) or of MartiniGlass, then corrected
# by presets/bonds.tsv (cholesterol).
# Colours and classes: presets/molecules.tsv. Styles: styles.tcl.
# ==============================================================================

namespace eval ::mvis {
    # The package folder. bin/mvis gives it in MVIS_ROOT: VMD does not tell
    # a script started with "vmd -e" where it is ([info script] is empty).
    variable root
    if {[info exists ::env(MVIS_ROOT)] && $::env(MVIS_ROOT) ne ""} {
        set root $::env(MVIS_ROOT)
    } else {
        set root [file dirname [file dirname [file normalize [info script]]]]
    }
    variable mol -1
    variable style default
    variable showWater 0
    variable showIons 0
    variable smooth 0
    variable rules {}           ;# list of {pattern class r g b}
    variable drawBonds          ;# array: resname -> {mode {{a b} {a b} ...}}
    variable classOf            ;# array: resname of the molecule -> class
    variable sel                ;# array: water ions sterol body tail -> selection text
    variable repWater -1        ;# representation numbers of the current style
    variable repIons -1
    variable firstColor 17      ;# colour numbers 17-32 are redefined
    variable lastColor 32
    variable beadRadius 2.35    ;# Angstrom; VDW representations scale it
    # Tail beads, by name: C1A D2B T1A (Martini 3 lipids), and CA1 CB2 CBX
    # (ionizable lipids such as SM-102).
    variable tailNames {"[CDT][0-9]+[A-Z]" "C[A-Z][0-9X]"}
}

proc ::mvis::say {text} {
    puts "mvis: $text"
}

proc ::mvis::data_lines {path} {
    # Lines of a presets file without comments and empty lines.
    set lines {}
    set handle [open $path r]
    while {[gets $handle line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} { continue }
        lappend lines $line
    }
    close $handle
    return $lines
}

proc ::mvis::preset_file {name} {
    # Your own copy next to the config file (MVIS_PRESETS, kept by
    # "mvis update") is used instead of the one of the package.
    global env
    variable root
    if {[info exists env(MVIS_PRESETS)]} {
        set own [file join $env(MVIS_PRESETS) $name]
        if {[file exists $own]} {
            say "$name: $own"
            return $own
        }
    }
    return [file join $root presets $name]
}

proc ::mvis::read_presets {} {
    variable root
    variable rules
    variable drawBonds

    set rules {}
    foreach line [data_lines [preset_file molecules.tsv]] {
        if {[llength $line] != 5} {
            say "molecules.tsv: line skipped (needs PATTERN CLASS R G B): $line"
            continue
        }
        lappend rules $line
    }

    array unset drawBonds
    foreach line [data_lines [preset_file bonds.tsv]] {
        set resname [lindex $line 0]
        set mode [lindex $line 1]
        if {$mode ni {replace add}} {
            say "bonds.tsv: line skipped (MODE must be replace or add): $line"
            continue
        }
        set pairs {}
        foreach pair [lrange $line 2 end] {
            set names [split $pair -]
            if {[llength $names] == 2} { lappend pairs $names }
        }
        set drawBonds($resname) [list $mode $pairs]
    }
}

proc ::mvis::resnames_of {mol} {
    set all [atomselect $mol all]
    set names [lsort -unique [$all get resname]]
    $all delete
    return $names
}

proc ::mvis::quoted {names} {
    # Residue names for a selection text ("NA+" needs the quotes).
    set out {}
    foreach name $names { lappend out "\"$name\"" }
    return [join $out " "]
}

proc ::mvis::classify {mol} {
    # Class and colour of every residue name of the molecule; selection
    # texts for water, ions, sterols and the rest ("body").
    variable rules
    variable classOf
    variable sel
    variable firstColor
    variable lastColor
    variable tailNames

    array unset classOf
    set colorOfClass [dict create]
    set nextColor $firstColor
    set colorNames [colorinfo colors]
    set byClass [dict create water {} ion {} sterol {}]
    set body {}

    foreach resname [resnames_of $mol] {
        set class ""
        foreach rule $rules {
            lassign $rule pattern ruleClass r g b
            if {[string match $pattern $resname]} {
                set class $ruleClass
                break
            }
        }
        set classOf($resname) $class
        if {$class in {water ion sterol}} {
            dict lappend byClass $class $resname
        } else {
            lappend body $resname
        }
        if {$class eq ""} { continue }

        if {![dict exists $colorOfClass $class]} {
            if {$nextColor > $lastColor} {
                say "more than [expr {$lastColor - $firstColor + 1}] classes:\
                     $class gets the colour of the last one"
                dict set colorOfClass $class $lastColor
            } else {
                # The colour of the class: that of its first line in the table.
                foreach rule $rules {
                    lassign $rule pattern ruleClass r g b
                    if {$ruleClass eq $class} { break }
                }
                color change rgb $nextColor $r $g $b
                dict set colorOfClass $class $nextColor
                incr nextColor
            }
        }
        set colorName [lindex $colorNames [dict get $colorOfClass $class]]
        if {[catch {color Resname $resname $colorName} message]} {
            say "could not colour $resname: $message"
        }
    }

    foreach {key class} {water water ions ion sterol sterol} {
        set names [dict get $byClass $class]
        if {[llength $names] > 0} {
            set sel($key) "resname [quoted $names]"
        } else {
            set sel($key) "none"
        }
    }
    if {[llength $body] > 0} {
        set sel(body) "resname [quoted $body]"
    } else {
        set sel(body) "none"
    }
    set sel(tail) "name $tailNames"

    set summary {}
    foreach resname [lsort [array names classOf]] {
        set class $classOf($resname)
        lappend summary "$resname=[expr {$class eq "" ? "?" : $class}]"
    }
    say "residues: [join $summary { }]"
}

proc ::mvis::apply_draw_bonds {mol} {
    # Replace or complete the bonds of the residues listed in bonds.tsv.
    variable drawBonds

    foreach resname [array names drawBonds] {
        lassign $drawBonds($resname) mode pairs
        set atoms [atomselect $mol "resname \"$resname\""]
        if {[$atoms num] == 0} {
            $atoms delete
            continue
        }
        set indices [$atoms get index]
        set residues [$atoms get residue]
        set names [$atoms get name]

        # bonds of each atom, keyed by its index
        if {$mode eq "add"} {
            foreach index $indices partners [$atoms getbonds] {
                set bonded($index) $partners
            }
        } else {
            foreach index $indices { set bonded($index) {} }
        }

        # atom index of (residue, bead name)
        foreach index $indices residue $residues name $names {
            set atomOf($residue,$name) $index
        }
        set drawn 0
        foreach residue [lsort -unique -integer $residues] {
            foreach pair $pairs {
                lassign $pair first second
                if {![info exists atomOf($residue,$first)]
                        || ![info exists atomOf($residue,$second)]} { continue }
                set a $atomOf($residue,$first)
                set b $atomOf($residue,$second)
                if {$b ni $bonded($a)} { lappend bonded($a) $b }
                if {$a ni $bonded($b)} { lappend bonded($b) $a }
                incr drawn
            }
        }

        set bondLists {}
        foreach index $indices { lappend bondLists $bonded($index) }
        $atoms setbonds $bondLists
        $atoms delete
        say "$resname: $drawn bonds drawn from presets/bonds.tsv ($mode)"
        unset bonded atomOf
    }
}

proc ::mvis::count_bonds {mol} {
    set all [atomselect $mol all]
    set total 0
    foreach partners [$all getbonds] { incr total [llength $partners] }
    $all delete
    return [expr {$total / 2}]
}

proc ::mvis::load {pdb trajectory glass step} {
    variable mol
    variable beadRadius

    set mol [mol new $pdb type pdb autobonds off waitfor all]
    mol rename $mol [file rootname [file tail $pdb]]

    if {$glass ne ""} {
        # MartiniGlass: its own cg_bonds script reads vis.top (relative
        # paths: from inside its folder).
        set here [pwd]
        cd $glass
        if {[catch {
            source cg_bonds-v6.tcl
            cg_bonds -top vis.top
        } message]} {
            say "MartiniGlass bonds failed ($message): the bonds of the .pdb are used"
        }
        cd $here
    }

    apply_draw_bonds $mol
    set bonds [count_bonds $mol]
    say "$bonds bonds"
    if {$bonds == 0} {
        say "WARNING: no bond at all: was the structure written by mvis prep?"
    }
    catch {mol reanalyze $mol}

    set all [atomselect $mol all]
    $all set radius $beadRadius
    $all delete

    if {$trajectory ne ""} {
        set type [string range [file extension $trajectory] 1 end]
        mol addfile $trajectory type $type step $step waitfor all molid $mol
        # Frame 0 is the structure: dropped, so that frame k of VMD is frame
        # k of the trajectory.
        if {[molinfo $mol get numframes] > 1} {
            animate delete beg 0 end 0 skip 0 $mol
        }
        animate goto 0
        say "[molinfo $mol get numframes] frames"
    }
    classify $mol
}

proc ::mvis::start {} {
    global env
    variable mol
    variable style
    variable showWater
    variable showIons
    variable smooth

    if {![info exists env(MVIS_PDB)] || $env(MVIS_PDB) eq ""} {
        say "nothing to open (MVIS_PDB is not set): start VMD with the mvis command"
        return
    }
    foreach {name variableName fallback} {
        MVIS_TRAJECTORY trajectory ""
        MVIS_GLASS glass ""
        MVIS_STYLE style default
        MVIS_WATER showWater 0
        MVIS_IONS showIons 0
        MVIS_STEP step 1
        MVIS_SMOOTH smooth 0
        MVIS_CYLINDER cylinderPrefix ""
        MVIS_CYLINDER_SHOW cylinderShow 0
    } {
        if {[info exists env($name)] && $env($name) ne ""} {
            set $variableName $env($name)
        } else {
            set $variableName $fallback
        }
    }

    read_presets
    load $env(MVIS_PDB) $trajectory $glass $step
    ::mvis::apply_style $style
    if {$cylinderPrefix ne "" && [::mvis::cylinder_load $cylinderPrefix $step]} {
        set ::mvis::showCylinder $cylinderShow
        ::mvis::show_cylinder
    }
    display resetview
    ::mvis::window
}

source [file join $::mvis::root tcl styles.tcl]
source [file join $::mvis::root tcl cylinder.tcl]
source [file join $::mvis::root tcl window.tcl]

::mvis::start
