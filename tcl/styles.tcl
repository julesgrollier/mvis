# ==============================================================================
# styles.tcl - the styles of mvis: which beads, how drawn, which colour
# ==============================================================================
#
# A style is a proc ::mvis::style_NAME that adds representations with
# ::mvis::rep. To add a style: write such a proc, add NAME to
# ::mvis::styles below and to the list checked in bin/mvis.
#
# Selections (built in mvis.tcl from presets/molecules.tsv):
#   $sel(body)    everything but water, ions and sterols (lipids, proteins)
#   $sel(tail)    beads named like C1A, D2B, T1A (lipid tails)
#   $sel(sterol)  $sel(water)  $sel(ions)
# Colours: "ResName" is the colour of the class of the residue
# (molecules.tsv); "ColorID N" is a fixed VMD colour.
# Sizes: Licorice RADIUS is the bond radius in Angstrom; VDW SCALE is times
# the bead radius (2.35 Angstrom). A Martini bond is about 4.7 Angstrom.
# ==============================================================================

namespace eval ::mvis {
    variable styles {default tails heads figure}
    variable material AOChalky
    variable resolution 16
}

proc ::mvis::rep {selection drawing coloring {material ""}} {
    # Add a representation; returns its number.
    variable mol
    if {$material eq ""} { set material $::mvis::material }
    mol representation {*}$drawing
    mol color {*}$coloring
    mol selection $selection
    mol material $material
    mol addrep $mol
    return [expr {[molinfo $mol get numreps] - 1}]
}

proc ::mvis::licorice {radius} {
    variable resolution
    return [list Licorice $radius $resolution $resolution]
}

proc ::mvis::vdw {scale} {
    variable resolution
    return [list VDW $scale $resolution]
}

proc ::mvis::water_and_ions {} {
    # Present in every style; shown or hidden by the options / the window.
    variable sel
    variable repWater
    variable repIons
    set repWater [rep $sel(water) [vdw 0.5] ResName Transparent]
    set repIons [rep $sel(ions) [vdw 0.7] ResName]
}

# ---- default: coloured head beads on grey tails ------------------------------

proc ::mvis::style_default {} {
    variable sel
    # whole molecule as thin grey sticks: the tails, and the links to the heads
    rep $sel(body) [licorice 0.9] {ColorID 6}
    # head beads: spheres, with thicker sticks between them, colour of the class
    rep "($sel(body)) and not ($sel(tail))" [licorice 1.1] ResName
    rep "($sel(body)) and not ($sel(tail))" [vdw 0.8] ResName
    # sterols: ring as sticks, the OH bead as a sphere
    rep $sel(sterol) [licorice 1.2] ResName
    rep "($sel(sterol)) and name ROH" [vdw 0.8] ResName
}

# ---- tails: the chains in the colour of their lipid, heads faded -------------

proc ::mvis::style_tails {} {
    variable sel
    rep $sel(body) [licorice 1.3] ResName
    # unsaturated beads (D): white spheres on the chain
    rep "($sel(body)) and name \"D\[0-9\]+\[A-Z\]\"" [vdw 0.65] {ColorID 8}
    rep "($sel(body)) and not ($sel(tail))" [vdw 0.6] ResName Transparent
    rep $sel(sterol) [licorice 1.0] ResName
}

# ---- heads: the surface of the membranes only --------------------------------

proc ::mvis::style_heads {} {
    variable sel
    rep "($sel(body)) and not ($sel(tail))" [vdw 0.9] ResName
    rep "($sel(sterol)) and name ROH" [vdw 0.9] ResName
}

# ---- figure: as default, on white, with shadows (for rendering) --------------

proc ::mvis::style_figure {} {
    style_default
}

# ------------------------------------------------------------------------------

proc ::mvis::display_settings {style} {
    display projection Orthographic
    display depthcue off
    axes location Off
    if {$style eq "figure"} {
        color Display Background white
        catch {display shadows on}
        catch {display ambientocclusion on}
        catch {display aoambient 0.9}
        catch {display aodirect 0.4}
    } else {
        color Display Background black
        catch {display shadows off}
        catch {display ambientocclusion off}
    }
}

proc ::mvis::apply_style {name} {
    # Remove all representations of the molecule and build those of the style.
    variable mol
    variable style
    variable styles
    variable smooth

    if {$name ni $styles} {
        say "unknown style $name (known: $styles): default used"
        set name default
    }
    set style $name
    while {[molinfo $mol get numreps] > 0} {
        mol delrep 0 $mol
    }
    style_$name
    water_and_ions
    display_settings $name
    for {set number 0} {$number < [molinfo $mol get numreps]} {incr number} {
        mol smoothrep $mol $number $smooth
    }
    show_water_and_ions
}

proc ::mvis::show_water_and_ions {} {
    variable mol
    variable repWater
    variable repIons
    variable showWater
    variable showIons
    mol showrep $mol $repWater $showWater
    mol showrep $mol $repIons $showIons
}
