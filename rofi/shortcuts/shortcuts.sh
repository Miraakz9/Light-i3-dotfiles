#!/usr/bin/env bash

I3_CONFIG="$HOME/.config/i3/config"

# Extract bindsym lines, remove comments, and format them
shortcuts=$(grep -E '^[[:space:]]*bind(sym|code)[[:space:]]' "$I3_CONFIG" |
    sed -E 's/^[[:space:]]*bind(sym|code)[[:space:]]+//' |
    sed 's/[[:space:]]*exec(_always)?[[:space:]]+--no-startup-id[[:space:]]*//' |
    sed 's/[[:space:]]*exec[[:space:]]*//' |
    sed 's/[[:space:]]*#.*$//' |
    sed 's/[[:space:]]\{2,\}/    /')

if [[ -z "$shortcuts" ]]; then
    notify-send "i3 Shortcuts" "No shortcuts found."
    exit 1
fi

rofi \
    -dmenu \
    -i \
    -p "Shortcuts" \
    -no-custom \
    -markup-rows \
    -theme-str '
        window {
            width: 800px;
            height: 600px;
        }

        listview {
            columns: 1;
            lines: 18;
        }

        element {
            padding: 8px;
        }

        element-text {
            font: "JetBrainsMono Nerd Font 11";
        }
    ' <<< "$shortcuts"
