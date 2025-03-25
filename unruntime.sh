#!/bin/bash
# shellcheck disable=SC1090,SC109,SC2001,SC1091,SC2086,SC2068

# settings
UNRUNTIME_VERSION=1.0.0
UNRUNTIME_URL=https://raw.githubusercontent.com/jasenmichael/unruntime/refs/heads/main/unruntime.sh
UNRUNTIME_DIR="$HOME/.unruntime"

NVM_INSTALL_URL=https://raw.githubusercontent.com/nvm-sh/nvm/refs/heads/master/nvm.sh
BUN_INSTALL_URL=https://bun.sh/install
DENO_INSTALL_URL=https://deno.land/x/install/install.sh
NODE_VERSION=${NODE_VERSION:---lts}

# ===========================================================

set -E # Make ERR trap inherited by shell functions

USAGE_TEXT=$(
  cat <<EOF
  Usage: $(basename "$0") [option]
         or
         $(basename "$0") [package1 package2 ...]
  
  Options:
    -h, --help     Show this help message
    -V, --version  Show script version (v${UNRUNTIME_VERSION})
    -a, --all      Install all packages
    -n, --none     Install only nvm, node (${NODE_VERSION}), and npm
  
  Packages:
    pnpm     Install pnpm via corepack
    yarn     Install yarn via corepack
    bun      Install bun via curl or wget $BUN_INSTALL_URL
    deno     Install deno via curl or wget $DENO_INSTALL_URL
  
  Examples:
    $(basename "$0")             # Interactive mode, prompt for each package
    $(basename "$0") -a          # Install all packages
    $(basename "$0") pnpm yarn   # Install specific packages
    $(basename "$0") -n          # Install only nvm, node, and npm
  
  Note: 
    - nvm, node, and npm are always installed/updated first
    - For Windows users, this script requires WSL (Windows Subsystem for Linux)
    - Options and packages cannot be mixed (e.g., -h pnpm is invalid)
EOF
)

# print usage
print_usage() {
  echo "$USAGE_TEXT" | sed 's/^  //'
}

# validate arguments
VALID_PACKAGES=(pnpm yarn bun deno nypm)
VALID_ARGUMENTS=("-h" "--help" "-V" "--version" "-n" "--none" "-a" "--all")

args_valid() {
  # If no args, return success
  [ $# -eq 0 ] && return 0

  # If exactly one arg, it must be a valid argument
  if [ $# -eq 1 ]; then
    [[ ! " ${VALID_ARGUMENTS[*]} " =~ ${1} ]] && echo "Invalid argument: $1" && return 1
    return 0
  fi

  # If multiple args, they must all be valid packages
  for arg in "$@"; do
    if [[ " ${VALID_ARGUMENTS[*]} " =~ ${arg} ]]; then
      echo -e "Error: Cannot mix arguments with packages.\nUse either arguments (-h, -v, etc.) or packages (pnpm, yarn, etc.), but not both.\n"
      return 1
    fi
    [[ ! " ${VALID_PACKAGES[*]} " =~ ${arg} ]] && echo "Invalid package: $arg" && return 1
  done
  return 0
}

if ! args_valid "$@"; then
  print_usage
  exit 1
fi

# version
if [ "$1" = "-V" ] || [ "$1" = "--version" ]; then
  echo "unruntime v$UNRUNTIME_VERSION"
  exit 0
fi

# help/usage
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  print_usage
  exit 0
fi

wgurl() {
  curl_available=$(command -v curl &>/dev/null)
  wget_available=$(command -v wget &>/dev/null)
  if [ "$1" = "--check" ]; then
    if $curl_available || $wget_available; then
      return 0
    fi
    return 1
  fi

  URL=$1
  if $curl_available; then
    curl -fsSL "$URL"
  elif $wget_available; then
    wget -qO- "$URL"

  else
    echo "Failed to get $URL, curl or wget not found"
    exit 1
  fi
}

# Load nvm before using it
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

# nvm versions
if [ -d "$NVM_DIR" ]; then
  NVM_VERSION=$(nvm --version | tr -d '\n' && echo)
fi
get_nvm_latest_version() {
  # wgurl https://latest.nvm.sh | grep -i location | tail -n1 | sed 's/.*\/v//' | tr -d '[:space:]'
  wgurl https://raw.githubusercontent.com/nvm-sh/nvm/master/package.json | grep '"version":' | cut -d'"' -f4

}
NVM_LATEST_VERSION=$(get_nvm_latest_version)
PACKAGES_INSTALLED=()

# helper functions
unruntime_is_installed() {
  [ -d "$UNRUNTIME_DIR" ] && [ -f "$UNRUNTIME_DIR/unruntime.sh" ] &>/dev/null
}

unruntime_is_up_to_date() {
  get_unruntime_latest_version() {
    wgurl "$UNRUNTIME_URL" | grep "^UNRUNTIME_VERSION=" | cut -d'=' -f2 | tr -d '"' | sed 's/unruntime v//' | tr -d '[:space:]'
  }
  UNRUNTIME_LATEST_VERSION=$(get_unruntime_latest_version)

  ! unruntime_is_installed && return 1

  UNRUNTIME_VERSION=$("$UNRUNTIME_DIR/unruntime.sh" --version | sed 's/unruntime v//' | tr -d '[:space:]')

  if [ -n "$UNRUNTIME_LATEST_VERSION" ] && [ "$(printf '%s\n' "$UNRUNTIME_VERSION" "$UNRUNTIME_LATEST_VERSION" | sort -V | tail -n1)" = "$UNRUNTIME_VERSION" ]; then
    return 0
  else
    return 1
  fi
}

nvm_is_installed() {
  [ -d "$NVM_DIR" ] && command -v nvm &>/dev/null
}

nvm_is_up_to_date() {
  ! nvm_is_installed && return 1

  if [ "$NVM_VERSION" == "$NVM_LATEST_VERSION" ]; then
    is_up_to_date=true
  else
    is_up_to_date=false
  fi
  $is_up_to_date || return 1
}

prompt_install() {
  echo ""
  local package=$1
  local response

  # When piped, explicitly connect to terminal for input
  if [ -t 0 ]; then
    read -rp "Press Y to install $package?: " response
  else
    read -rp "Press Y to install $package?: " response </dev/tty
  fi

  case "${response:-n}" in
  [yY]) return 0 ;;
  *) return 1 ;;
  esac
}

add_block() {
  # remove whitespace from the beginning of each line
  TEXT=$(echo "$1" | sed 's/^[[:space:]]*//gm')

  if [ -f "$HOME/.zshrc" ]; then
    echo "" >>"$HOME/.zshrc"
    printf "\n%s" "$TEXT" >>"$HOME/.zshrc"
  fi

  if [ -f "$HOME/.bashrc" ]; then
    echo "" >>"$HOME/.bashrc"
    printf "\n%s" "$TEXT" >>"$HOME/.bashrc"
  fi

  # remove duplicate empty lines from zshrc and bashrc
  sed -i '/./,/^$/!d' "$HOME/.zshrc"
  sed -i '/./,/^$/!d' "$HOME/.bashrc"
}

remove_block() {
  local block_id=$1
  sed -i "/# >> unruntime: $block_id/,/# << unruntime: $block_id/d" "$HOME/.zshrc"
  sed -i "/# >> unruntime: $block_id/,/# << unruntime: $block_id/d" "$HOME/.bashrc"
}

# Update a block in shell config files
update_block() {
  local block_id=$1
  local content=$2
  local wrapped_block="# >> unruntime: $block_id"$'\n'"$content"$'\n'"# << unruntime: $block_id"
  remove_block "$block_id"
  add_block "$wrapped_block"
}

print_report() {
  if [ ${#PACKAGES_INSTALLED[@]} -gt 0 ]; then
    printf "\nUnruntime installed/updated the following:\n"
    for package in "${PACKAGES_INSTALLED[@]}"; do
      case "$package" in
      deno) v=$("$package" -v) ;;
      *) v=$("$package" --version) ;;
      esac
      # v=$(echo "$v" | sed 's/deno //' | sed 's/^v//' | sed 's/ (.*//')
      v=$(echo "$v" | sed 's/deno //' | sed 's/^v//' | sed 's/ //')
      if [ "$package" = "corepack" ]; then
        echo -e "  $package:\t $v"
      else
        echo -e "  $package:\t\t $v"
      fi
    done
    echo ""
  fi

  if [ "$error_occurred" = false ]; then
    echo "Installation complete!"
    echo "Please restart your terminal or run: source \$HOME/.zshrc && source \$HOME/.bashrc"
  fi
}

# exit handlers
on_interrupt() {
  echo "Script was interrupted (${1:-unknown signal})."
  exit 1
}

on_error() {
  echo "Error occurred at line $1, exit code $2"
  error_occurred=true
  print_usage
  exit "$2"
}

on_exit() {
  if [ "$skip_report" = false ]; then
    print_report
  fi
}

# da trap house
trap 'on_interrupt SIGINT' SIGINT SIGTERM
trap 'on_error ${LINENO} $?' ERR
trap on_exit EXIT

# unruntime install/update functions
install_unruntime() {
  mkdir -p "$UNRUNTIME_DIR" >/dev/null 2>&1
  wgurl "$UNRUNTIME_URL" >"$UNRUNTIME_DIR/unruntime.sh"

  local rc_block
  rc_block=$(
    cat <<EOF
UNRUNTIME_DIR="$HOME/.unruntime"
alias unrun="$UNRUNTIME_DIR/unruntime.sh"
alias unruntime="$UNRUNTIME_DIR/unruntime.sh"
EOF
  )
  update_block "unrun" "$rc_block"
  UNRUNTIME_DIR="$HOME/.unruntime"
  chmod +x "$UNRUNTIME_DIR/unruntime.sh"
  echo -e "Unruntime installed! v$UNRUNTIME_VERSION\n"
}

update_unruntime() {
  # backup unruntime.sh
  if ! unruntime_is_up_to_date; then
    cp "$UNRUNTIME_DIR/unruntime.sh" "$UNRUNTIME_DIR/unruntime.sh.bak"
    install_unruntime
    # if install was successful, remove the backup
    if unruntime_is_installed; then
      echo "Unruntime updated!"
      rm "$UNRUNTIME_DIR/unruntime.sh.bak"
      # Execute the new version with all arguments
      # shellcheck disable=SC2086,SC2068
      exec "$UNRUNTIME_DIR/unruntime.sh" "$@"
    else
      echo "Failed to update unruntime"
      cp "$UNRUNTIME_DIR/unruntime.sh.bak" "$UNRUNTIME_DIR/unruntime.sh"
    fi
  else
    echo "Unruntime is up to date! v$UNRUNTIME_VERSION"
    return 0
  fi
}

# install functions
install_nvm_node() {
  echo "####### Installing/Updating nvm, node, and npm..."

  # install/update nvm
  local update_nvm=false
  if nvm_is_installed; then
    echo "nvm installed, checking for updates..."
    if nvm_is_up_to_date; then
      echo "nvm is up to date! v$NVM_VERSION"
    else
      echo "nvm v$NVM_LATEST_VERSION is available, current version is v$NVM_VERSION"
      if [ -t 0 ]; then
        read -rp "Update nvm? (y/n): " update_nvm
      else
        read -rp "Update nvm? (y/n): " update_nvm </dev/tty
      fi

      case "${update_nvm:-n}" in
      [yY]) update_nvm=true ;;
      *) update_nvm=false ;;
      esac
    fi
  else
    echo "nvm not installed, installing..."
    update_nvm=true
  fi

  if [ "$update_nvm" = true ]; then
    wgurl "$NVM_INSTALL_URL" | bash

    # update nvm from git
    if command -v git &>/dev/null; then
      (
        cd "$NVM_DIR"
        git fetch --tags origin
        git checkout "$(git describe --abbrev=0 --tags --match "v[0-9]*" "$(git rev-list --tags --max-count=1)")"
      ) && \. "$NVM_DIR/nvm.sh"
    else
      echo "git not found, skipping nvm update"
    fi

    PACKAGES_INSTALLED+=("nvm")

    # remove exports generated by nvm
    sed -i '/NVM_DIR/d' "$HOME/.zshrc"
    sed -i '/NVM_DIR/d' "$HOME/.bashrc"

    # Then update nvm block in rc files
    local rc_block
    rc_block=$(
      cat <<EOF
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
EOF
    )
    update_block "nvm" "$rc_block"
  fi

  echo "Installing/Updating node and npm..."
  # echo "NODE_VERSION: $NODE_VERSION"

  # install/update node and npm
  nvm install "$NODE_VERSION" >/dev/null 2>&1
  nvm use "$NODE_VERSION" >/dev/null 2>&1
  PACKAGES_INSTALLED+=("node")
  PACKAGES_INSTALLED+=("npm")

  # Extract the node version and compare it to check if it supports corepack
  node_version=$(node -v | sed 's/^v//')
  if [ "$NODE_VERSION" == "--lts" ] || [ "$(printf '%s\n' "16.9.0" "$node_version" | sort -V | head -n1)" = "16.9.0" ]; then
    echo "Node version $node_version supports corepack, installing..."
    npm install --global corepack@latest
    PACKAGES_INSTALLED+=("corepack")
  else
    echo "Node version $node_version does not support corepack (requires v16.9.0+), skipping..."
  fi

}

install_pnpm() {
  echo "####### Installing pnpm..."

  npm uninstall -g pnpm >/dev/null 2>&1
  corepack enable
  corepack enable pnpm
  corepack prepare pnpm@latest --activate

  local rc_block
  rc_block=$(
    cat <<EOF
export PNPM_HOME="\$HOME/.local/share/pnpm"
case ":\$PATH:" in
*":\$PNPM_HOME:"*) ;;
*) export PATH="\$PNPM_HOME:\$PATH" ;;
esac
EOF
  )

  update_block "pnpm" "$rc_block"

  if ! command -v pnpm &>/dev/null; then
    echo "Failed to install pnpm"
    exit 1
  fi
  echo "Pnpm installed: $(pnpm --version)"
  PACKAGES_INSTALLED+=("pnpm")
}

install_yarn() {
  echo "####### Installing yarn..."

  npm uninstall -g yarn >/dev/null 2>&1
  corepack enable
  corepack prepare yarn@stable --activate

  if ! command -v yarn &>/dev/null; then
    echo "Failed to install yarn"
    exit 1
  fi
  echo "Yarn installed: $(yarn --version)"
  PACKAGES_INSTALLED+=("yarn")
}

install_bun() {
  echo "####### Installing bun..."
  if [ -z "$DRY_RUN" ] && [ "$DRY_RUN" != "true" ]; then
    wgurl "$BUN_INSTALL_URL" | bash

    # remove bun completions line, and the line after it
    # this is re-added in the rc_block below
    sed -i '/# bun completions/{N;d}' "$HOME/.zshrc"
    sed -i '/# bun completions/{N;d}' "$HOME/.bashrc"

  else
    echo "Dry run, skipping bun installation"
  fi

  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"

  local rc_block
  rc_block=$(
    cat <<EOF
export BUN_INSTALL="\$HOME/.bun"
export PATH="\$BUN_INSTALL/bin:\$PATH"
[ -s "\$BUN_INSTALL/_bun" ] && source "\$BUN_INSTALL/_bun"
EOF
  )
  update_block "bun" "$rc_block"

  if ! command -v bun &>/dev/null; then
    echo "Failed to install bun"
    exit 1
  fi
  echo "Bun installed: $(bun --version)"
  PACKAGES_INSTALLED+=("bun")
}

install_deno() {
  # TODO: check if the latest deno is already installed
  # https://dl.deno.land/release-latest.txt
  echo "####### Installing deno..."
  if [ -z "$DRY_RUN" ] && [ "$DRY_RUN" != "true" ]; then
    wgurl "$DENO_INSTALL_URL" | sh

  else
    echo "Dry run, skipping deno installation"
  fi

  # remove line containing ".deno/env"
  sed -i '/\/\.deno\/env/d' "$HOME/.zshrc"
  sed -i '/\/\.deno\/env/d' "$HOME/.bashrc"

  # . "\$HOME/.deno/env"
  rc_block=". \"\$HOME/.deno/env\""
  update_block "deno" "$rc_block"

  if ! command -v deno &>/dev/null; then
    echo "Failed to install deno"
    exit 1
  fi
  echo "Deno installed: $(deno --version)"
  PACKAGES_INSTALLED+=("deno")
}

install_nypm() {
  echo "####### Installing nypm..."
  npm install --global nypm
  PACKAGES_INSTALLED+=("nypm")
}

# main
main() {
  # check if curl or wget is available
  if ! wgurl --check; then
    echo "curl or wget not found, please install one of them"
    exit 1
  fi

  # Always install/update unruntime
  if unruntime_is_installed; then
    echo "Unruntime installed, checking for updates..."
    update_unruntime "$@"
  else
    echo "####### Installing unruntime..."
    install_unruntime
  fi

  # Always install/update nvm, node, and npm first
  install_nvm_node
  install_nvm_node_exit_code=$?

  if [ "$1" = "-n" ] || [ "$1" = "--none" ]; then
    exit $install_nvm_node_exit_code
  fi

  # Define available packages
  declare -A packages=(
    [pnpm]=install_pnpm
    [yarn]=install_yarn
    [bun]=install_bun
    [deno]=install_deno
    [nypm]=install_nypm
  )
  package_order=("${VALID_PACKAGES[@]}")

  skip_report=false
  error_occurred=false

  # Install based on arguments
  # -a | --all | all - install all packages.
  # <pkg>            - install specified package. EXAMPLE: <script>.sh pnpm
  # <pkg1> <pkg2>    - install specified packages. EXAMPLE: <script>.sh pnpm yarn
  # no args          - prompt for each package
  if [ "$1" = "-a" ] || [ "$1" = "--all" ] || [ "$1" = "all" ]; then
    # install all packages
    for package in "${package_order[@]}"; do
      echo ""
      ${packages[$package]}
    done
  elif [ $# -eq 0 ]; then
    # prompt for each package
    for package in "${package_order[@]}"; do
      if prompt_install "$package"; then
        ${packages[$package]}
      else
        echo "Skipping $package"
      fi
    done
  else
    # validate all in $@ are valid packages
    for package in "$@"; do
      if [ ! "${packages[$package]+isset}" ]; then
        echo "Unknown package: $package" >&2
        echo "Use -h or --help to see available packages" >&2
        on_error ${LINENO} 1
      fi
    done

    # install specified packages
    for package in "$@"; do
      ${packages[$package]}
    done
  fi
}

main "$@"
#
