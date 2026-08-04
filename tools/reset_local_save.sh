#!/bin/bash
# Dev-only helper: deletes the local Godot save file so the next launch
# starts from a fresh account (no purchases, no progression). Godot
# regenerates user://save.json on demand, so nothing else to do after this.
set -euo pipefail

SAVE_FILE="$HOME/Library/Application Support/Godot/app_userdata/wizard-kittenz/save.json"

if [ -f "$SAVE_FILE" ]; then
	rm "$SAVE_FILE"
	echo "Deleted $SAVE_FILE"
else
	echo "No save file found at $SAVE_FILE (already clean)"
fi
