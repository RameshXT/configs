export K9S_SKIN="transparent"

k9s() {
  case "${1:-}" in
    info|version|help|completion|license|-h|--help|-v|--version)
      command k9s "$@"
      ;;
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
