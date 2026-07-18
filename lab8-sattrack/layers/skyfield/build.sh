#!/usr/bin/env bash
# Builds the Skyfield Lambda layer into layers/skyfield/python/.
#
# Lambda layers for Python must place packages under a top-level python/
# directory -- Lambda adds that directory to sys.path at runtime.
#
# The Lambda runtime is python3.12 on x86_64 Linux, but this script may run
# on any OS/Python (Derek's machine is Windows + Python 3.14), so we tell pip
# to download wheels for the *target* environment instead of the local one:
#   --platform manylinux2014_x86_64  -> Linux x86_64 binary wheels
#   --python-version 3.12            -> CPython 3.12 wheels
#   --implementation cp              -> CPython (not PyPy)
#   --only-binary=:all:              -> never build from source (a source
#                                       build would use the local toolchain
#                                       and produce non-Linux binaries)
set -euo pipefail
cd "$(dirname "$0")"

rm -rf python
python -m pip install \
  --requirement requirements.txt \
  --target python \
  --platform manylinux2014_x86_64 \
  --python-version 3.12 \
  --implementation cp \
  --only-binary=:all: \
  --upgrade

# Trim bytecode caches; they are regenerated at runtime and bloat the layer.
find python -type d -name "__pycache__" -prune -exec rm -rf {} +

echo "--- layer contents ---"
du -sh python
python_dir_size_kb=$(du -sk python | cut -f1)
if [ "$python_dir_size_kb" -gt 250000 ]; then
  echo "ERROR: layer exceeds the 250 MB unzipped Lambda limit" >&2
  exit 1
fi
