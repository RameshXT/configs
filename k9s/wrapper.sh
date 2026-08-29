k9s() {
  local k9s_bin
  k9s_bin="$(command -v k9s)" || { echo "[k9s] error: k9s binary not found in PATH" >&2; return 1; }
  case "${1:-}" in
    -w|--write)
      shift
      echo "[k9s] WRITE MODE — mutating commands enabled" >&2
      "$k9s_bin" --readonly=false "$@"
      ;;
    -r|--read)
      shift
      echo "[k9s] read-only mode" >&2
      "$k9s_bin" --readonly "$@"
      ;;
    *)
      echo "[k9s] read-only mode (default)" >&2
      "$k9s_bin" --readonly "$@"
      ;;
  esac
}
