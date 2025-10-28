# Local orchestrator for installer-staging
# Runs on deployment machine, orchestrates remote installation
{pkgs, ...}: {
  type = "app";

  program = builtins.toString (pkgs.writeShellScript "installer-staging" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Local orchestrator that runs on deployment machine
    # Arguments: --flake <uri> --target-host <user@host> --build-on <local|remote|auto> --cross-hosts <hosts> --kexec <yes|no|auto> --stage <0|1> --mode <install|bootstrap> --nix-user <user> --nix-cfg <config>

    # Source configuration
    source ${./config.sh}

    # Default values
    FLAKE=""
    TARGET_HOST=""
    BUILD_ON="$DEFAULT_BUILD_ON"
    KEXEC_BOOT="$DEFAULT_KEXEC_BOOT"
    LOG_LEVEL="$DEFAULT_LOG_LEVEL"
    FLAKE_EXCLUDE="$DEFAULT_FLAKE_EXCLUDE"
    FORCE="$DEFAULT_FORCE"
    SYSTEM_CLOSURE=""
    DISKO_SCRIPT=""
    STAGE="$DEFAULT_STAGE"
    FULL="$DEFAULT_FULL"
    LOW_MEM="$DEFAULT_LOW_MEM"
    SUBS_ON_DEST="yes"
    MODE="install"
    NIXUSER="$(whoami)"
    NIXCFG="lamt-nixconfig"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --flake) FLAKE="$2"; shift ;;
        --target-host) TARGET_HOST="$2"; shift ;;
         --build-on) BUILD_ON="$2"; shift ;;
         --cross) BUILD_ON="cross" ;;
        --kexec) KEXEC_BOOT="$2"; shift ;;
        --low-mem) LOW_MEM="$2"; shift ;;
        --substitute-on-destination) SUBS_ON_DEST="$2"; shift ;;
        --stage) STAGE="$2"; shift ;;
        --log-level) LOG_LEVEL="$2"; shift ;;
        --exclude) FLAKE_EXCLUDE="$2"; shift ;;
        --force) FORCE="yes" ;;
        --full)
          if ! [[ "$2" =~ ^($VALID_FULL_MODES)$ ]]; then
            echo "ERROR: Invalid --full mode: $2 (must be $VALID_FULL_MODES)"
            exit 1
          fi
          FULL="$2"
          shift
          ;;
        --mode) MODE="$2"; shift ;;
        --nix-user) NIXUSER="$2"; shift ;;
        --nix-cfg) NIXCFG="$2"; shift ;;
        --help)
        echo "Usage: $0 --flake <flake-uri> --target-host <user@host> [options]"
        echo ""
        echo "Options:"
        echo "  --flake <uri>        Flake URI (e.g., .#hostname)"
        echo "  --target-host <host> Target SSH host (e.g., root@192.168.1.100)"
        echo "  --build-on <mode>    Build mode: local, remote, auto, cross (default: remote)"
        echo "  --cross              Enable cross-compilation (shortcut for --build-on cross)"
        echo "  --kexec <mode>       Kexec mode: yes, no, auto (default: auto)"
        echo "  --low-mem <mode>     Low memory mode: yes (apply optimizations), no (default)"
        echo "  --substitute-on-destination <mode> Substitute on destination: yes (default), no"
        echo "  --stage <stage>      Installation stage: 0 (minimal), 1 (full) (default: 0)"
        echo "  --log-level <level>  Log level: debug, info, warn, error (default: info)"
        echo "  --exclude <args>     Rsync exclude arguments (default: standard excludes)"
        echo "  --force              Skip confirmation prompts"
        echo "  --full <yes|no|auto> Full build mode: yes (build full system), no (staged), auto (default based on build-on)"
        echo "  --mode <mode>        Orchestration mode: install (default), bootstrap"
        echo "  --nix-user <user>    Nix user name (default: current user)"
        echo "  --nix-cfg <config>   Nix config directory name (default: lamt-nixconfig)"
        exit 0
        ;;
        *) echo "Unknown option: $1"; exit 1 ;;
      esac
      shift
    done

    # Default SUBS_ON_DEST to no when LOW_MEM=yes
    if [[ "$LOW_MEM" == "yes" ]] && [[ "$SUBS_ON_DEST" == "yes" ]]; then
      SUBS_ON_DEST="no"
    fi

    # Validation
    if [[ -z "$FLAKE" ]]; then
      echo "ERROR: --flake is required"
      exit 1
    fi

    if [[ -z "$TARGET_HOST" ]]; then
      echo "ERROR: --target-host is required"
      exit 1
    fi

    # Validate build-on mode
    if ! [[ "$BUILD_ON" =~ ^($VALID_BUILD_MODES)$ ]]; then
      echo "ERROR: Invalid --build-on mode: $BUILD_ON (must be $VALID_BUILD_MODES)"
      exit 1
    fi

    # Validate kexec mode
    if ! [[ "$KEXEC_BOOT" =~ ^($VALID_KEXEC_MODES)$ ]]; then
      echo "ERROR: Invalid --kexec mode: $KEXEC_BOOT (must be $VALID_KEXEC_MODES)"
      exit 1
    fi

    # Validate low-mem mode
    if ! [[ "$LOW_MEM" =~ ^($VALID_LOW_MEM_MODES)$ ]]; then
      echo "ERROR: Invalid --low-mem mode: $LOW_MEM (must be $VALID_LOW_MEM_MODES)"
      exit 1
    fi

    # Validate substitute-on-destination mode
    if ! [[ "$SUBS_ON_DEST" =~ ^($VALID_SUBS_ON_DEST_MODES)$ ]]; then
      echo "ERROR: Invalid --substitute-on-destination mode: $SUBS_ON_DEST (must be $VALID_SUBS_ON_DEST_MODES)"
      exit 1
    fi

    # Validate stage
    if ! [[ "$STAGE" =~ ^($VALID_STAGES)$ ]]; then
      echo "ERROR: Invalid --stage: $STAGE (must be $VALID_STAGES)"
      exit 1
    fi

    # Source the orchestration library
    source ./apps/installer-staging/orchestrator-lib.sh

    # Determine host
    HOST=''${FLAKE#*.#}
    FLAKE_CONFIG_ATTR="nixosConfigurations.$HOST"  # Default, will be overridden in lib

    # Export global variables for the library
    export FLAKE FLAKE_CONFIG_ATTR TARGET_HOST BUILD_ON KEXEC_BOOT LOW_MEM LOG_LEVEL FLAKE_EXCLUDE FORCE SYSTEM_CLOSURE DISKO_SCRIPT STAGE FULL SUBS_ON_DEST MODE NIXUSER NIXCFG

    # Run the orchestration based on mode
    if [[ "$MODE" == "bootstrap" ]]; then
      bootstrap_orchestrator
    else
      main_orchestration
    fi
  '');
}
