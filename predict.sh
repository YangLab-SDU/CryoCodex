#!/bin/bash
# CryoCodex launcher

set -e

# Resolve paths from this script, leaving relative input/output paths unchanged.
CryoCodex_home="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CryoCodex_env="${CRYOCODEX_ENV:-cryocodex_env}"
Model_URL="https://yanglab.qd.sdu.edu.cn/CryoCodex/CryoCodex.pth"

# Let predict.py print this launcher's name in its usage line instead of "predict.py"
CRYOCODEX_PROG="${0##*/}"
export CRYOCODEX_PROG

# `-h` on its own prints this summary; `-h advanced` adds the full option list from predict.py
short_help() {
    cat <<EOF

usage: $CRYOCODEX_PROG [-h] -i MAP -o DIR

CryoCodex: cryo-EM map enhancement with local quality scores

==============================================================================
options:
  -h           Show every option with '-h advanced'
  -i MAP       Input EM density map (.mrc/.map)
  -o DIR       Directory to save the output maps

==============================================================================
modes:
  CryoCodex runs in one of two modes, picked with '--normal True|False'.
  In either mode, adding '--reverse_interpolation True' resamples the saved
  maps back to the voxel size of the input map; by default they are saved on
  the 1.0 Angstrom grid.

  fast mode (--normal False, the default)
      Crop the background around the molecule away and infer on the remaining
      part only, which makes the run much quicker. Two options belong to this
      mode alone:
          --crop_check True    review the cropped region before the inference
          --keep_size True     fill the cropped away background back in with
                               zeros, so the outputs span the whole input map

  normal mode (--normal True)
      Infer on the whole map, without cropping anything away. Slower, and
      neither --crop_check nor --keep_size applies here.
EOF
}

# Help needs no checkpoint, so it is answered before looking for the model weights
advanced_help=false
case " $* " in
    *" -h advanced "*|*" --help advanced "*) advanced_help=true;;
    *" -h "*|*" --help "*) short_help; exit 0;;
esac

# conda run handles activation internally, including environment activation hooks.
# CONDA_EXE also works when conda is exposed only as an interactive shell function.
conda_exe="${CONDA_EXE:-$(command -v conda || true)}"
if [ -z "$conda_exe" ] || [ ! -x "$conda_exe" ]; then
    echo "ERROR: Conda was not found. Install Conda and follow the README installation commands." >&2
    exit 1
fi
python_command=("$conda_exe" run --no-capture-output -n "$CryoCodex_env" python)
if [ "$advanced_help" = true ]; then
    exec "${python_command[@]}" "$CryoCodex_home/predict.py" --help
fi

# Report a missing environment before attempting a potentially large download.
if ! "${python_command[@]}" -c 'import sys'; then
    echo "ERROR: Cannot use '$CryoCodex_env'. Complete the README installation commands first." >&2
    exit 1
fi

# Use model_state_dicts/CryoCodex.pth, downloading it there on the first run
checkpoint="$CryoCodex_home/model_state_dicts/CryoCodex.pth"
if [ ! -s "$checkpoint" ]; then
    if [ -z "$Model_URL" ]; then
        echo "ERROR: No checkpoint at '$checkpoint' and 'Model_URL' is not set yet"
        echo "Please download the model weights to that path manually"
        exit 1
    fi
    mkdir -p -- "$(dirname -- "$checkpoint")"
    echo "Downloading the model weights to '$checkpoint' ..."
    if ! curl -fL --retry 2 -o "$checkpoint.part" "$Model_URL"; then
        rm -f "$checkpoint.part"
        echo "ERROR: Failed to download the model weights from '$Model_URL'"
        exit 1
    fi
    mv "$checkpoint.part" "$checkpoint"
fi

# All arguments are passed on to predict.py; run `predict.sh -h` for the full option list
exec "${python_command[@]}" "$CryoCodex_home/predict.py" -m "$checkpoint" "$@"
