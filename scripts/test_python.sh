#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PYTHONPATH="$project_dir/research/python" python3 -m unittest discover -s "$project_dir/research/python/tests"

