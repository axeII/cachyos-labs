#!/bin/bash
# Reset display configuration to ultrawide-only setup
# Enables DP-1 (ultrawide) as primary and disables HDMI-A-1 (TV)

kscreen-doctor \
    output.DP-1.enable \
    output.DP-1.position.0,0 \
    output.DP-1.primary \
    output.DP-1.mode.3840x1600@75 \
    output.HDMI-A-1.disable \
    2>&1