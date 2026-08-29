k9s() {
  case "${1:-}" in
    -w|--write)
      shift
      command k9s --readonly=false "$@"
      ;;
    -r|--read)
      shift
      command k9s --readonly "$@"
      ;;
    *)
      command k9s --readonly "$@"
      ;;
  esac
}
