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
# build-essential/base-devel: C compiler for treesitter parser compilation (:TSUpdate)
# ripgrep/fd/bat: used by the rg-fzf widget and FZF_* env in .zshrc.
#   (On apt, fd-find and bat install as `fdfind`/`batcat`; .aliases bridges the names.)
# fzf is deliberately NOT installed here -- see the dedicated fzf install step
# below, which is needed for working shell integration (Ctrl-R/Ctrl-T/Alt-C).
if command -v apt &>/dev/null; then
    $SUDO apt update
    $SUDO apt install -y zsh git stow tree curl build-essential \
        ripgrep fd-find bat
elif command -v xbps-install &>/dev/null; then
    $SUDO xbps-install -S
    $SUDO xbps-install -y zsh git stow tree curl base-devel \
        ripgrep fd bat
else
    echo "ERROR: no supported package manager found (apt, xbps-install)." >&2
    exit 1
fi

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

# Install a specific neovim release into ~/.local. Returns:
#   0 on success, 2 if the binary installed but won't execute (glibc too old),
#   1 on any other failure. The runtime check matters because Ubuntu 20.04 ships
#   glibc 2.31 but recent nvim stable releases need 2.33+ -> SIGABRT on launch.
install_nvim() {
    local version=$1 arch=$2 tarball extract_dir TMP
    if [ "$version" = "stable" ]; then
        # New naming convention used by 0.11+ release tarballs.
        tarball="nvim-linux-${arch}.tar.gz"
        extract_dir="nvim-linux-${arch}"
    else
        # Pre-0.11 releases only published nvim-linux64.tar.gz (x86_64 only).
        [ "$arch" = "x86_64" ] || return 1
        tarball="nvim-linux64.tar.gz"
        extract_dir="nvim-linux64"
    fi
    TMP="$(mktemp -d)"
    curl -fsSL "https://github.com/neovim/neovim/releases/download/${version}/${tarball}" \
        -o "$TMP/$tarball" || { rm -rf "$TMP"; return 1; }
    mkdir -p "$HOME/.local" "$HOME/.local/bin"
    rm -rf "$HOME/.local/$extract_dir"
    tar -C "$HOME/.local" -xzf "$TMP/$tarball" || { rm -rf "$TMP"; return 1; }
    ln -sf "$HOME/.local/$extract_dir/bin/nvim" "$HOME/.local/bin/nvim"
    rm -rf "$TMP"
    "$HOME/.local/bin/nvim" --version >/dev/null 2>&1 || return 2
    return 0
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
    install_nvim stable "$NVIM_ARCH"
    rc=$?
    if [ $rc -eq 2 ]; then
        # stable installed but won't run (likely older glibc). v0.10.4 was the
        # last release built against glibc 2.31 and still has every API the
        # config uses (vim.uv, vim.treesitter.foldexpr).
        echo "stable nvim won't run here (glibc too old?); falling back to v0.10.4..."
        install_nvim v0.10.4 "$NVIM_ARCH" || { echo "ERROR: nvim install failed."; exit 1; }
    elif [ $rc -ne 0 ]; then
        echo "ERROR: nvim install failed."
        exit 1
    fi
    echo "neovim $($HOME/.local/bin/nvim --version | head -1) installed to ~/.local/bin/nvim."
fi

# The new .zshrc puts ~/.local/bin on PATH, but bootstrap is running under bash
# right now -- so without this export, later `nvim` invocations in this script
# get "command not found".
export PATH="$HOME/.local/bin:$PATH"

# fzf: installed from the upstream repo rather than the distro package.
# apt/xbps package versions lag badly (Mint 21.3's apt fzf is 0.29) and are too
# old for `fzf --zsh`/`--zsh` shell-integration (added in 0.48); the apt
# package also doesn't ship ~/.fzf.zsh at all (only unsourced example scripts
# under /usr/share/doc/fzf), so .zshrc's `source ~/.fzf.zsh` silently no-ops
# and Ctrl-R/Ctrl-T/Alt-C never get wired up. The upstream installer script
# always writes ~/.fzf.zsh and gives a current fzf binary in ~/.fzf/bin.
if [ ! -d "$HOME/.fzf" ]; then
    echo "Installing fzf (upstream installer, for shell integration)..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
else
    echo "fzf already installed via upstream installer."
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

STOW_FLAGS=(--target="$HOME" --no-folding
    --ignore='README.md' --ignore='bootstrap.sh' --ignore='bench-prompt.zsh')

echo ""
echo "Dry-run: checking for conflicts..."

# Capture so we can parse out which files collided and offer to delete them.
SIM_OUT="$(mktemp)"
if ! stow --simulate --verbose "${STOW_FLAGS[@]}" . > "$SIM_OUT" 2>&1; then
    cat "$SIM_OUT"
    # stow prints conflicts as e.g.
    #   * existing target is neither a link nor a directory: .zshrc
    # Extract whatever follows the final ": " on those lines.
    CONFLICTS=$(grep -E '^\s*\* existing target' "$SIM_OUT" \
        | sed -E 's/.*: //' | sort -u)
    rm -f "$SIM_OUT"
    if [ -z "$CONFLICTS" ]; then
        echo ""
        echo "ERROR: stow failed but no conflicts parsed; resolve and re-run."
        exit 1
    fi
    echo ""
    echo "Conflicting paths in \$HOME (would be overwritten):"
    while IFS= read -r f; do
        ls -ld --color=auto "$HOME/$f" 2>/dev/null || echo "  $HOME/$f"
    done <<< "$CONFLICTS"
    echo ""
    read -r -p "Delete these and retry stow? [y/N] " ans
    if [[ ! "$ans" =~ ^[Yy] ]]; then
        echo "Aborted. Back up/move the conflicts manually then re-run."
        exit 1
    fi
    while IFS= read -r f; do
        rm -rf "$HOME/$f"
        echo "  rm $HOME/$f"
    done <<< "$CONFLICTS"
    echo ""
    echo "Re-checking for conflicts..."
    if ! stow --simulate --verbose "${STOW_FLAGS[@]}" . 2>&1; then
        echo "ERROR: conflicts remain after deletion."
        exit 1
    fi
else
    rm -f "$SIM_OUT"
fi

echo ""
echo "No conflicts. Stowing dotfiles..."
stow --verbose "${STOW_FLAGS[@]}" .

echo ""
echo "Done! Open a new terminal (or run: exec zsh) to load the new shell."

#: }}}


#: Neovim directories {{{

echo ""
echo "Creating neovim backup/swap/undo directories..."
mkdir -p ~/.vim/backups ~/.vim/swaps ~/.vim/undo

#: }}}

echo "Syncing neovim plugins (headless)..."
# Headless so lazy.nvim installs/updates plugins and exits instead of blocking
# on an interactive editor. PATH already has ~/.local/bin from the install step.
nvim --headless "+Lazy! sync" +qa

# If we're actually attached to a terminal (not piped under `bash -s` from rp),
# drop the user straight into zsh so they don't have to `exec zsh` themselves.
# `-t 0 && -t 1` skips this when stdin/stdout are pipes (the rp bootstrap path).
if [ -t 0 ] && [ -t 1 ] && [ "$(basename "${SHELL:-}")" != "zsh" ]; then
    echo ""
    echo "Launching zsh..."
    exec "$ZSH_PATH" -l
fi
