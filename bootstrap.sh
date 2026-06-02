#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"

# Use sudo only when needed: empty when already root, else `sudo` if available.
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif command -v sudo &>/dev/null; then
    SUDO="sudo"
else
    echo "ERROR: not running as root and sudo is not installed; can't install packages." >&2
    exit 1
fi

#: Dependencies {{{

echo "Installing dependencies..."
# build-essential: C compiler for treesitter parser compilation (:TSUpdate)
# ripgrep/fd-find/bat/fzf: used by the rg-fzf widget and FZF_* env in .zshrc.
#   (fd-find and bat install as `fdfind`/`batcat`; .aliases bridges the names.)
$SUDO apt install -y zsh git stow tree curl build-essential \
    ripgrep fd-find bat fzf

# Neovim: do NOT use apt — its package is far too old for this config, which
# uses 0.11+ APIs (vim.lsp.config/enable, vim.uv, vim.treesitter.foldexpr).
# Install the official build only if a sufficiently new nvim isn't present,
# so machines that already have a modern nvim are left untouched.
nvim_ok() {
    command -v nvim &>/dev/null || return 1
    local v major minor
    v=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    major=${v%%.*}; minor=${v#*.}
    (( major > 0 || minor >= 11 ))
}

if nvim_ok; then
    echo "neovim $(nvim --version | head -1) already new enough."
else
    echo "Installing modern neovim from official release..."
    case "$(uname -m)" in
        x86_64)        NVIM_ARCH=x86_64 ;;
        aarch64|arm64) NVIM_ARCH=arm64 ;;
        *) echo "ERROR: unsupported arch $(uname -m) for neovim install."; exit 1 ;;
    esac
    NVIM_TARBALL="nvim-linux-${NVIM_ARCH}.tar.gz"
    TMP="$(mktemp -d)"
    curl -fsSL "https://github.com/neovim/neovim/releases/download/stable/${NVIM_TARBALL}" \
        -o "$TMP/$NVIM_TARBALL"
    mkdir -p "$HOME/.local" "$HOME/.local/bin"
    tar -C "$HOME/.local" -xzf "$TMP/$NVIM_TARBALL"
    ln -sf "$HOME/.local/nvim-linux-${NVIM_ARCH}/bin/nvim" "$HOME/.local/bin/nvim"
    rm -rf "$TMP"
    echo "neovim installed to ~/.local/bin/nvim (ensure ~/.local/bin is on PATH)."
fi

# zsh-autosuggestions
if [ ! -d "$HOME/.zsh/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/zsh-autosuggestions"
else
    echo "zsh-autosuggestions already installed."
fi

# zsh-syntax-highlighting
if [ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.zsh/zsh-syntax-highlighting"
else
    echo "zsh-syntax-highlighting already installed."
fi

# starship
if ! command -v starship &>/dev/null; then
    echo "Installing starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
else
    echo "starship already installed."
fi

#: }}}


#: Shell {{{

ZSH_PATH="$(which zsh)"

# chsh fails if the target shell isn't listed in /etc/shells
if ! grep -qxF "$ZSH_PATH" /etc/shells; then
    echo "Adding $ZSH_PATH to /etc/shells..."
    echo "$ZSH_PATH" | $SUDO tee -a /etc/shells >/dev/null
fi

if [ "$SHELL" != "$ZSH_PATH" ]; then
    echo "Switching default shell to zsh..."
    chsh -s "$ZSH_PATH"
else
    echo "Shell is already zsh."
fi

#: }}}


#: Stow {{{

cd "$DOTFILES_DIR"

echo ""
echo "Dry-run: checking for conflicts..."

# --simulate does a dry run; exit code is nonzero if conflicts exist
if ! stow --simulate --verbose --target="$HOME" \
    --ignore='README.md' \
    --ignore='bootstrap.sh' \
    --ignore='bench-prompt.zsh' \
    . 2>&1; then
    echo ""
    echo "ERROR: Conflicts detected above. Resolve them before running bootstrap again."
    echo "Tip: back up or delete the conflicting files in ~ then re-run."
    exit 1
fi

echo ""
echo "No conflicts. Stowing dotfiles..."
stow --verbose --target="$HOME" \
    --ignore='README.md' \
    --ignore='bootstrap.sh' \
    --ignore='bench-prompt.zsh' \
    .

echo ""
echo "Done! Open a new terminal (or run: exec zsh) to load the new shell."

#: }}}


#: Neovim directories {{{

echo ""
echo "Creating neovim backup/swap/undo directories..."
mkdir -p ~/.vim/backups ~/.vim/swaps ~/.vim/undo

#: }}}
