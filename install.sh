#!/usr/bin/env bash
# Installs wt into ${WT_INSTALL_DIR:-$HOME/.local/bin}.
set -euo pipefail

dir=${WT_INSTALL_DIR:-$HOME/.local/bin}
url=${WT_URL:-https://raw.githubusercontent.com/jbsaintebeuve/wt/main/wt}

mkdir -p "$dir"
tmp=$(mktemp "$dir/.wt.XXXXXX")
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp"
chmod 755 "$tmp"
mv "$tmp" "$dir/wt"
echo "wt installed to $dir/wt"
case ":$PATH:" in
  *":$dir:"*) ;;
  *) echo "note: $dir is not on your PATH" ;;
esac
echo "optional: add 'eval \"\$(wt shell-init)\"' to your shell rc so 'wt go' changes directory"
