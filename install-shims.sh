#!/bin/bash
# Install the stand-ins for the omarchy-* commands omdrop calls, for a desktop
# other than Omarchy. Optional: the plasmoid itself does not need them.
#
#   ./install-shims.sh               into /usr/local/bin (uses sudo)
#   ./install-shims.sh --user        into ~/.local/bin, and put that on the
#                                    PATH of systemd user units
#   ./install-shims.sh --uninstall   remove them (add --user for that copy)
#
# Nothing is installed where Omarchy's own commands are found, and only files
# this script installed are ever replaced or removed.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MARKER='omdrop-plasmoid shim'
NAMES=(omarchy-notification-send omarchy-launch-browser omarchy-default-terminal)
ENV_FILE=10-local-bin.conf

user=0 uninstall=0
for arg in "$@"; do
  case $arg in
    --user) user=1 ;;
    --uninstall) uninstall=1 ;;
    *) sed -n '2,12s/^# \{0,1\}//p' "$0"; exit 2 ;;
  esac
done

if (( user )); then
  bindir="${XDG_BIN_HOME:-$HOME/.local/bin}"
  envdir="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
  as_owner() { "$@"; }
else
  bindir=/usr/local/bin
  if (( EUID == 0 )); then as_owner() { "$@"; }; else as_owner() { sudo "$@"; }; fi
fi

ours() { [[ -f $1 ]] && grep -qF "$MARKER" "$1"; }

if (( uninstall )); then
  for name in "${NAMES[@]}"; do
    if ours "$bindir/$name"; then
      as_owner rm -f -- "$bindir/$name"
      echo "removed $bindir/$name"
    elif [[ -e $bindir/$name ]]; then
      echo "left $bindir/$name alone: it is not one of these stand-ins"
    fi
  done
  if (( user )) && ours "$envdir/$ENV_FILE"; then
    rm -f -- "$envdir/$ENV_FILE"
    echo "removed $envdir/$ENV_FILE (takes effect at the next login)"
  fi
  exit 0
fi

# On Omarchy the real commands are there and do more than these.
if command -v omarchy >/dev/null 2>&1; then
  echo "This looks like Omarchy ($(command -v omarchy)): omdrop already has what it needs. Nothing installed." >&2
  exit 1
fi
for name in "${NAMES[@]}"; do
  for found in "$(command -v "$name" 2>/dev/null || true)" "$bindir/$name"; do
    if [[ -n $found && -e $found ]] && ! ours "$found"; then
      echo "Found another $name at $found, which is not one of these stand-ins. Nothing installed." >&2
      exit 1
    fi
  done
done

for name in "${NAMES[@]}"; do
  as_owner install -Dm755 "$here/shims/$name" "$bindir/$name"
  echo "installed $bindir/$name"
done

if (( user )); then
  # A user unit's PATH is /usr/local/bin:/usr/bin unless something adds to it.
  if [[ -e $envdir/$ENV_FILE ]] && ! ours "$envdir/$ENV_FILE"; then
    echo "left $envdir/$ENV_FILE alone: it is not from here. Make sure it puts $bindir on PATH."
  else
    install -Dm644 "$here/shims/$ENV_FILE" "$envdir/$ENV_FILE"
    echo "installed $envdir/$ENV_FILE"
  fi
  # environment.d is read when the user manager starts; this covers the
  # session that is already running.
  if current=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^PATH=//p'); then
    case ":$current:" in
      *":$bindir:"*) ;;
      *) systemctl --user set-environment PATH="$bindir:${current:-/usr/local/bin:/usr/bin}"
         echo "added $bindir to the running user manager's PATH" ;;
    esac
  fi
fi

echo "Done. If omdrop is on, turn it off and on again so its watcher sees them."
