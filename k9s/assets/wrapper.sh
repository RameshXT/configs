k9s() {
  case "${1:-}" in
    -w|--write)
      shift
      echo "[k9s] WRITE MODE — mutating commands enabled" >&2
      command k9s --readonly=false "$@"
      ;;
    -r|--read)
      shift
      echo "[k9s] read-only mode" >&2
      command k9s --readonly "$@"
      ;;
    *)
      echo "[k9s] read-only mode (default)" >&2
      command k9s --readonly "$@"
      ;;
  esac
}
