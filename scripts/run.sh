#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

discover_project() {
  local projects=()
  local project

  while IFS= read -r -d '' project; do
    projects+=("$project")
  done < <(find "$ROOT_DIR" -maxdepth 3 -name '*.xcodeproj' -type d -print0)

  case "${#projects[@]}" in
    0)
      die "no .xcodeproj found under $ROOT_DIR; set PROJECT"
      ;;
    1)
      printf '%s' "${projects[0]}"
      ;;
    *)
      printf 'error: multiple .xcodeproj files found under %s; set PROJECT\n' "$ROOT_DIR" >&2
      printf 'found:\n' >&2
      printf '  %s\n' "${projects[@]}" >&2
      exit 1
      ;;
  esac
}

default_scheme() {
  local project="$1"
  local project_name
  local scheme_dir
  local scheme_path
  local schemes=()

  project_name="$(basename "$project" .xcodeproj)"
  scheme_dir="$project/xcshareddata/xcschemes"
  scheme_path="$scheme_dir/$project_name.xcscheme"

  if [[ -f "$scheme_path" ]]; then
    printf '%s' "$project_name"
    return
  fi

  if [[ -d "$scheme_dir" ]]; then
    while IFS= read -r -d '' scheme_path; do
      schemes+=("$(basename "$scheme_path" .xcscheme)")
    done < <(find "$scheme_dir" -maxdepth 1 -name '*.xcscheme' -type f -print0)
  fi

  if [[ "${#schemes[@]}" -eq 1 ]]; then
    printf '%s' "${schemes[0]}"
  else
    printf '%s' "$project_name"
  fi
}

default_app_name() {
  local project="$1"
  local scheme="$2"
  local scheme_path="$project/xcshareddata/xcschemes/$scheme.xcscheme"
  local buildable_name=""

  if [[ -f "$scheme_path" ]]; then
    buildable_name="$(
      awk -F'"' '
        /BuildableName =/ && $2 ~ /\.app$/ {
          sub(/\.app$/, "", $2)
          print $2
          exit
        }
      ' "$scheme_path"
    )"
  fi

  printf '%s' "${buildable_name:-$scheme}"
}

default_bundle_id() {
  local project="$1"
  local project_file="$project/project.pbxproj"

  [[ -f "$project_file" ]] || return 0

  awk -F' = ' '
    /PRODUCT_BUNDLE_IDENTIFIER =/ {
      value = $2
      gsub(/;$/, "", value)
      gsub(/"/, "", value)
      print value
      exit
    }
  ' "$project_file"
}

simulator_destination() {
  local simulator="$1"

  if [[ "$simulator" =~ ^[0-9A-Fa-f-]{8}-[0-9A-Fa-f-]{4}-[0-9A-Fa-f-]{4}-[0-9A-Fa-f-]{4}-[0-9A-Fa-f-]{12}$ ]]; then
    printf 'platform=iOS Simulator,id=%s' "$simulator"
  else
    printf 'platform=iOS Simulator,name=%s' "$simulator"
  fi
}

physical_destination() {
  local device_name="$1"

  if [[ -n "$device_name" ]]; then
    printf 'platform=iOS,name=%s' "$device_name"
  else
    printf 'generic/platform=iOS'
  fi
}

CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"

DEVICE="${DEVICE:-${DEVICE_ID:-}}"
DEVICE_NAME="${DEVICE_NAME:-}"
SIMULATOR="${SIMULATOR:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/run.sh <target> [options]

Targets:
  device      Build, install, and launch on a physical iPhone.
  simulator   Build, install, and launch on an iOS simulator.
  devices     List physical devices known to Xcode.
  simulators  List available simulators.

Options:
  --launch             Launch the app after installing. This is the default.
  --no-launch          Install without launching.
  --skip-build         Install the app already built in .build/DerivedData.
  --device NAME_OR_ID  Override the physical iPhone used by devicectl.
  --device-name NAME   Build for a named iPhone instead of generic iOS.
  --simulator NAME     Override the simulator name or identifier.
  -h, --help           Show this help.

Configuration:
  PROJECT                      Defaults to the only .xcodeproj in this folder.
  SCHEME                       Defaults to a matching shared scheme or project name.
  APP_NAME                     Defaults to the scheme's .app product name.
  BUNDLE_ID                    Defaults to the first bundle id in the project.
  DEVICE                       Optional devicectl name, UDID, serial, or ECID.
  DEVICE_NAME                  Optional xcodebuild device name.
  SIMULATOR                    Optional simulator name or identifier.

Examples:
  scripts/run.sh device --device "iPhone"
  scripts/run.sh devices
  scripts/run.sh simulators
  scripts/run.sh simulator --simulator "iPhone 17"
  scripts/run.sh simulator --simulator "iPhone 17 Pro"
USAGE
}

target="${1:-}"
if [[ -z "$target" || "$target" == "-h" || "$target" == "--help" ]]; then
  usage
  [[ -n "$target" ]] && exit 0
  exit 1
fi
shift

launch=false
no_launch=false
skip_build=false
device_override=""
device_name_override=""
simulator_override=""

while (($#)); do
  case "$1" in
    --launch)
      launch=true
      shift
      ;;
    --no-launch)
      launch=false
      no_launch=true
      shift
      ;;
    --skip-build)
      skip_build=true
      shift
      ;;
    --device)
      [[ $# -ge 2 ]] || die "--device requires a name, UDID, serial, or ECID"
      device_override="$2"
      shift 2
      ;;
    --device-name)
      [[ $# -ge 2 ]] || die "--device-name requires a device name"
      device_name_override="$2"
      shift 2
      ;;
    --simulator)
      [[ $# -ge 2 ]] || die "--simulator requires a simulator name or identifier"
      simulator_override="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

platform=""
destination=""
app_platform=""
install_device=""

case "$target" in
  devices|list-devices)
    xcrun devicectl list devices
    exit 0
    ;;
  simulators|list-simulators)
    xcrun simctl list devices available
    exit 0
    ;;
  device|iphone)
    platform="device"
    device_name="${device_name_override:-$DEVICE_NAME}"
    install_device="${device_override:-${DEVICE:-$device_name}}"
    [[ -n "$install_device" ]] || die "set DEVICE or pass --device; run scripts/run.sh devices to see options"
    destination="$(physical_destination "$device_name")"
    app_platform="iphoneos"
    ;;
  simulator|sim)
    platform="simulator"
    install_device="${simulator_override:-$SIMULATOR}"
    [[ -n "$install_device" ]] || die "set SIMULATOR or pass --simulator; run scripts/run.sh simulators to see options"
    destination="$(simulator_destination "$install_device")"
    app_platform="iphonesimulator"
    ;;
  *)
    usage
    die "unknown target: $target"
    ;;
esac

if [[ "$no_launch" == false ]]; then
  launch=true
fi

PROJECT="${PROJECT:-$(discover_project)}"
SCHEME="${SCHEME:-$(default_scheme "$PROJECT")}"
APP_NAME="${APP_NAME:-$(default_app_name "$PROJECT" "$SCHEME")}"
BUNDLE_ID="${BUNDLE_ID:-$(default_bundle_id "$PROJECT")}"
app_path="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-$app_platform/$APP_NAME.app"

if [[ "$skip_build" == false ]]; then
  log "Building $SCHEME for $destination"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "$destination" \
    -allowProvisioningUpdates \
    build
else
  log "Skipping build"
fi

[[ -d "$app_path" ]] || die "app bundle not found at $app_path"
if [[ "$launch" == true && -z "$BUNDLE_ID" ]]; then
  die "bundle id could not be inferred; set BUNDLE_ID to use --launch"
fi

if [[ "$platform" == "device" ]]; then
  log "Installing $APP_NAME on $install_device"
  xcrun devicectl device install app --device "$install_device" "$app_path"

  if [[ "$launch" == true ]]; then
    log "Launching $BUNDLE_ID on $install_device"
    xcrun devicectl device process launch --device "$install_device" "$BUNDLE_ID"
  fi
else
  log "Booting $install_device if needed"
  xcrun simctl bootstatus "$install_device" -b

  log "Installing $APP_NAME on $install_device"
  xcrun simctl install "$install_device" "$app_path"

  if [[ "$launch" == true ]]; then
    log "Launching $BUNDLE_ID on $install_device"
    xcrun simctl launch "$install_device" "$BUNDLE_ID"
  fi
fi

log "Installed $APP_NAME for $target"
