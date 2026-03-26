#!/bin/bash
set -e

echo "=== Installing emacs, tmux, system dependencies for diffusion_policy ==="
echo "=== Installing system dependencies for diffusion_policy ==="
apt-get update
apt-get -y install emacs tmux unzip jq
#	libosmesa6-dev libgl1-mesa-glx libglfw3 patchelf unzip jq

echo "=== Installing cargo and rust ==="
curl https://sh.rustup.rs -sSf | sh -s -- -y

echo "=== Installing MessagePack tools ==="
source ~/.bashrc
cargo install msgpack-cli

echo "=== Getting claude ==="
curl -fsSL https://claude.ai/install.sh | bash

echo "=== Installing uv ==="
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

echo "=== Setting git config ==="
git config --global user.email "chris@treqs.ai"
git config --global user.name "Chris Geyer"

echo "=== Setting path and venv alias ==="

# Add to bashrc if not already there
if ! grep -q 'local/bin' ~/.bashrc 2>/dev/null; then
    echo >> ~/.bashrc
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

if ! grep -q '.venv/bin/activate' ~/.bashrc 2>/dev/null; then
    echo >> ~/.bashrc
    echo 'alias venvhere="source .venv/bin/activate"' >> ~/.bashrc
fi

if ! grep -q 'purina' ~/.bashrc 2>/dev/null; then
    echo >> ~/.bashrc
    echo 'export BUCKET=s3://chris-purina-playground/' >> ~/.bashrc
fi

if ! grep -q 'alias bashrc' ~/.bashrc 2>/dev/null; then
    echo >> ~/.bashrc
    echo 'alias bashrc="source ~/.bashrc"' >> ~/.bashrc
fi

if ! grep -q 'alias gh_christophergeyer' ~/.bashrc 2>/dev/null; then
    echo >> ~/.bashrc
    echo 'alias gh_christophergeyer="source ~/.ssh/christophergeyer.sh"' >> ~/.bashrc
    echo 'alias gh_chris_treqs="source ~/.ssh/chris_treqs.sh"' >> ~/.bashrc
fi

exit
