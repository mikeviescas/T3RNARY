#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
godot_binary=${GODOT_BIN:-godot}
"$godot_binary" --headless --path "$project_dir/godot" --script res://tests/run_tests.gd

