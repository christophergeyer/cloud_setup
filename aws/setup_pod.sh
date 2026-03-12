#!/bin/bash
set -e


echo "=== Installing awscli ==="
sudo snap install aws-cli --classic

echo "=== Installing emacs, tmux, system dependencies for diffusion_policy ==="
sudo apt-get update
sudo apt-get -y install emacs tmux
sudo apt-get -y install make
#\
#	libosmesa6-dev libgl1-mesa-glx libglfw3 patchelf unzip jq

echo "=== Installing cargo and rust ==="
if command -v cargo &> /dev/null; then
    echo "cargo already installed"
else
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source ~/.bashrc
fi

# echo "=== Installing MessagePack tools ==="
# cargo install msgpack-cli

#echo "=== Setting up ssh agent and key ==="
#cp -r /workspace/.ssh ~/.
#chmod og-rw ~/.ssh/id_rsa_cmgeyer*
#eval "$(ssh-agent -s)"
#ssh-add ~/.ssh/id_rsa_cmgeyer

echo "=== Getting claude ==="
if command -v claude &> /dev/null; then
    echo "claude already installed"
else
    curl -fsSL https://claude.ai/install.sh | bash
fi

echo "=== Installing uv ==="
if command -v uv &> /dev/null; then
    echo "uv already installed"
else
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

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

echo "=== Setup complete ==="
echo "Run: source ~/.bashrc"
