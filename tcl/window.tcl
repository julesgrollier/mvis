# ==============================================================================
# window.tcl - small window to change the style, show water / ions
# ==============================================================================
#
# Opens with mvis; also in the VMD menu Extensions > Visualization > mvis.
# Without Tk (VMD in text mode) nothing is opened.
# ==============================================================================

proc ::mvis::window {} {
    variable styles

    if {![info exists ::tk_version]} { return }
    if {[winfo exists .mvis]} {
        wm deiconify .mvis
        raise .mvis
        return .mvis
    }
    toplevel .mvis
    wm title .mvis "mvis"
    wm resizable .mvis 0 0

    labelframe .mvis.style -text "Style" -padx 8 -pady 4
    foreach name $styles {
        radiobutton .mvis.style.$name -text $name -value $name -anchor w \
            -variable ::mvis::style -command {::mvis::apply_style $::mvis::style}
        pack .mvis.style.$name -side top -fill x
    }

    labelframe .mvis.show -text "Show" -padx 8 -pady 4
    checkbutton .mvis.show.water -text "water" -anchor w \
        -variable ::mvis::showWater -command ::mvis::show_water_and_ions
    checkbutton .mvis.show.ions -text "ions" -anchor w \
        -variable ::mvis::showIons -command ::mvis::show_water_and_ions
    pack .mvis.show.water .mvis.show.ions -side top -fill x
    if {$::mvis::cylinder ne ""} {
        # only when the cylinder files were prepared (cylinder.tcl)
        checkbutton .mvis.show.cylinder -text "cylinder" -anchor w \
            -variable ::mvis::showCylinder -command ::mvis::show_cylinder
        pack .mvis.show.cylinder -side top -fill x
    }

    labelframe .mvis.smooth -text "Smoothing (frames)" -padx 8 -pady 4
    # (a spinbox: VMD has its own "scale" command, which hides Tk's slider)
    spinbox .mvis.smooth.value -from 0 -to 20 -width 4 -state readonly \
        -textvariable ::mvis::smooth -command {::mvis::set_smooth $::mvis::smooth}
    pack .mvis.smooth.value -side top -fill x

    pack .mvis.style .mvis.show .mvis.smooth -side top -fill x -padx 8 -pady 4
    return .mvis
}

proc ::mvis::set_smooth {value} {
    variable mol
    if {$mol < 0} { return }
    for {set number 0} {$number < [molinfo $mol get numreps]} {incr number} {
        mol smoothrep $mol $number $value
    }
}

# In the Extensions menu, so that a closed window can be opened again.
catch {vmd_install_extension mvis ::mvis::window "Visualization/mvis"}
