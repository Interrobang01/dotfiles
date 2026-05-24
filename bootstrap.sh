#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"

#: Dependencies {{{

echo "Installing dependencies..."
sudo apt install -y zsh neovim git stow tree

#: }}}


#: Shell {{{

ZSH_PATH="$(which zsh)"

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
    .

echo ""
echo "Done! Open a new terminal (or run: exec zsh) to load the new shell."

#: }}}


#: Neovim directories {{{

echo ""
echo "Creating neovim backup/swap/undo directories..."
mkdir -p ~/.vim/backups ~/.vim/swaps ~/.vim/undo

#: }}}
