#!/bin/bash

IMG=/tmp/lock.png

rm -f "$IMG"

scrot "$IMG"

convert "$IMG" -blur 0x8 \
    -gravity north \
    -fill white \
    -pointsize 72 \
    -annotate +0+120 "$(date '+%H:%M')" \
    -fill white \
    -pointsize 32 \
    -annotate +0+220 "$(date '+%A, %d %B %Y')" \
    "$IMG"

exec i3lock --nofork -i "$IMG"
