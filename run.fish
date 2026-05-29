#!/opt/homebrew/bin/fish
# Quick run helper (fish shell)

set -l binary life

if not test -x $binary
    echo "Building odin-life..."
    odin build . -out:$binary -o:minimal
end

./$binary $argv
