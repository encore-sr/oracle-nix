#!/usr/bin/env bash
# Build the qcow2 (result/nixos-image-oci-*.qcow2).
#
# Output: result/nixos-image-oci-*.qcow2
set -euo pipefail
cd "$(dirname "$0")/.."

nix build .#oracle-nix-image -L "$@"

img="$(readlink -f result)/nixos-image-oci-*.qcow2"
img=$(echo $img | head -n1)
echo
echo "image: $img"
ls -lh "$img"
