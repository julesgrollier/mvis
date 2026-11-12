# Stand-ins for the VMD commands used by tcl/*.tcl, to run them in tclsh.
# The "molecule" is read from the .pdb in MVIS_PDB (atoms + CONECT); every
# VMD command is logged in ::log. Selections understand only what the test
# needs: all, and resname "X".
set ::log {}
set ::reps {}
proc logcmd {args} { lappend ::log $args }
proc read_pdb {path} {
    set ::atoms {}; array unset ::bonds; array unset ::serial
    set handle [open $path r]; set i 0
    while {[gets $handle line] >= 0} {
        if {[string match ATOM* $line] || [string match HETATM* $line]} {
            set name [string trim [string range $line 12 15]]
            set resname [string trim [string range $line 17 20]]
            set resid [string trim [string range $line 22 25]]
            lappend ::atoms [list $i $name $resname $resid]
            set ::serial([string trim [string range $line 6 10]]) $i
            set ::bonds($i) {}
            incr i
        } elseif {[string match CONECT* $line]} {
            set a $::serial([lindex $line 1])
            foreach other [lrange $line 2 end] {
                set b $::serial($other)
                if {$b ni $::bonds($a)} { lappend ::bonds($a) $b }
                if {$a ni $::bonds($b)} { lappend ::bonds($b) $a }
            }
        }
    }
    close $handle
    # residue number: changes when resid or resname changes
    set residue -1; set previous ""; set out {}
    foreach atom $::atoms {
        set key [lrange $atom 2 3]
        if {$key ne $previous} { incr residue; set previous $key }
        lappend out [linsert $atom end $residue]
    }
    set ::atoms $out
}
set ::selcount 0
proc atomselect {mol text} {
    set picked {}
    if {$text eq "all"} {
        foreach atom $::atoms { lappend picked [lindex $atom 0] }
    } elseif {[regexp {^resname "(.*)"$} $text -> resname]} {
        foreach atom $::atoms { if {[lindex $atom 2] eq $resname} { lappend picked [lindex $atom 0] } }
    } else { error "stub: selection not understood: $text" }
    set name sel[incr ::selcount]
    set ::picked($name) $picked
    proc ::$name {sub args} "selection_command $name \$sub {*}\$args"
    return $name
}
proc selection_command {name sub args} {
    set picked $::picked($name)
    switch $sub {
        num { return [llength $picked] }
        delete { rename ::$name {}; return }
        getbonds { set out {}; foreach i $picked { lappend out $::bonds($i) }; return $out }
        setbonds { foreach i $picked partners [lindex $args 0] { set ::bonds($i) $partners }; return }
        set { logcmd sel set {*}[lrange $args 0 0]; return }
        get {
            set column [dict get {index 0 name 1 resname 2 resid 3 residue 4} [lindex $args 0]]
            set out {}; foreach i $picked { lappend out [lindex [lindex $::atoms $i] $column] }; return $out
        }
    }
    error "stub: selection command $sub"
}
proc mol {sub args} {
    logcmd mol $sub {*}$args
    switch $sub {
        new { read_pdb [lindex $args 0]; return 0 }
        addrep { lappend ::reps [list $::cur(selection) $::cur(representation) $::cur(color) $::cur(material)] }
        delrep { set ::reps [lreplace $::reps 0 0] }
        representation - color - selection - material { set ::cur($sub) $args }
    }
    return
}
proc molinfo {mol get what} {
    switch $what { numreps { return [llength $::reps] } numframes { return 11 } }
}
proc colorinfo {what} { set out {}; for {set i 0} {$i < 33} {incr i} { lappend out color$i }; return $out }
foreach command {color display axes animate} { proc $command {args} "logcmd $command {*}\$args" }
