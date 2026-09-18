_aws_pick_session() {
  local -a sessions labels
  local prev_line=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^\[sso-session[[:space:]]+([^]]+)\]$ ]]; then
      local name="${BASH_REMATCH[1]%$'\r'}"
      local label
      if [[ "$prev_line" =~ ^#[[:space:]]*display_name[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        label="${BASH_REMATCH[1]%$'\r'}"
      else
        case "$name" in
          smaitic) label="Smaitic Labs" ;;
          smaitik) label="Smaitik Venture" ;;
          *) label="$name" ;;
        esac
      fi
      sessions+=("$name")
      labels+=("$label")
    fi
    prev_line="$line"
  done < "$HOME/.aws/config"

  if [ ${#sessions[@]} -eq 0 ]; then
    echo "No sso-session blocks found in ~/.aws/config" >&2
    return 1
  fi

  labels+=("[Abort]")
  sessions+=("__ABORT__")

  local idx=0 total=${#labels[@]}
  local ESC=$'\033'

  tput civis >/dev/tty 2>/dev/null
  trap 'tput cnorm >/dev/tty 2>/dev/null' RETURN INT TERM

  local i
  for i in "${!labels[@]}"; do
    if [ "$i" -eq "$idx" ]; then
      printf "\e[32m> %s\e[0m\n" "${labels[$i]}" >&2
    else
      printf "  %s\n" "${labels[$i]}" >&2
    fi
  done

  while true; do
    IFS= read -rsn1 key
    if [[ "$key" == "$ESC" ]]; then
      IFS= read -rsn2 -t 0.1 seq
      key="$ESC$seq"
    fi
    case "$key" in
      "${ESC}[A"|"k")
        (( idx = (idx - 1 + total) % total ))
        ;;
      "${ESC}[B"|"j")
        (( idx = (idx + 1) % total ))
        ;;
      "")
        break
        ;;
      "q"|$'\x03')
        tput cnorm >/dev/tty 2>/dev/null
        printf "\n" >&2
        return 1
        ;;
    esac
    printf "\e[%dA" "$total" >&2
    for i in "${!labels[@]}"; do
      if [ "$i" -eq "$idx" ]; then
        printf "\e[32m> %s\e[0m\n" "${labels[$i]}" >&2
      else
        printf "  %s\n" "${labels[$i]}" >&2
      fi
    done
  done

  tput cnorm >/dev/tty 2>/dev/null
  printf "\n" >&2
  if [ "${sessions[$idx]}" = "__ABORT__" ]; then
    echo "Login aborted." >&2
    return 1
  fi
  echo "${sessions[$idx]}"
}

_aws_get_display_name() {
  local session="$1" prev_line="" line
  while IFS= read -r line; do
    local clean="${line%$'\r'}"
    if [[ "$clean" =~ ^\[sso-session[[:space:]]+([^]]+)\]$ ]]; then
      local sname="${BASH_REMATCH[1]%$'\r'}"
      if [ "$sname" = "$session" ]; then
        if [[ "$prev_line" =~ ^#[[:space:]]*display_name[[:space:]]*=[[:space:]]*(.+)$ ]]; then
          echo "${BASH_REMATCH[1]%$'\r'}"
          return 0
        fi
        break
      fi
    fi
    prev_line="$clean"
  done < "$HOME/.aws/config"

  case "$session" in
    smaitic) echo "Smaitic Labs" ;;
    smaitik) echo "Smaitik Venture" ;;
    *) echo "$session" ;;
  esac
}

_aws_pick_profile() {
  local target_session="$1"
  local -a profiles labels
  local cur_profile="" cur_session="" cur_role="" line

  _record_profile() {
    if [ -n "$cur_profile" ]; then
      if [ -z "$target_session" ] || [ "$cur_session" = "$target_session" ]; then
        profiles+=("$cur_profile")
        labels+=("${cur_role:-$cur_profile}")
      fi
    fi
  }

  while IFS= read -r line; do
    local clean="${line%$'\r'}"
    if [[ "$clean" =~ ^\[profile[[:space:]]+([^]]+)\]$ ]]; then
      _record_profile
      cur_profile="${BASH_REMATCH[1]%$'\r'}"
      cur_session=""
      cur_role=""
    elif [[ "$clean" =~ ^sso_session[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      cur_session="${BASH_REMATCH[1]%$'\r'}"
      cur_session="${cur_session#"${cur_session%%[![:space:]]*}"}"
      cur_session="${cur_session%"${cur_session##*[![:space:]]}"}"
    elif [[ "$clean" =~ ^sso_role_name[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      cur_role="${BASH_REMATCH[1]%$'\r'}"
      cur_role="${cur_role#"${cur_role%%[![:space:]]*}"}"
      cur_role="${cur_role%"${cur_role##*[![:space:]]}"}"
    elif [[ "$clean" =~ ^\[.*\]$ ]]; then
      _record_profile
      cur_profile=""
      cur_session=""
      cur_role=""
    fi
  done < "$HOME/.aws/config"
  _record_profile
  unset -f _record_profile

  [ ${#labels[@]} -eq 0 ] && { echo "No profiles matching active session in ~/.aws/config" >&2; return 1; }

  labels+=("[Abort]")
  profiles+=("__ABORT__")

  local idx=0 total=${#labels[@]} ESC=$'\033' i
  tput civis >/dev/tty 2>/dev/null
  trap 'tput cnorm >/dev/tty 2>/dev/null' RETURN INT TERM

  for i in "${!labels[@]}"; do
    [ "$i" -eq "$idx" ] && printf "\e[32m> %s\e[0m\n" "${labels[$i]}" >&2 || printf "  %s\n" "${labels[$i]}" >&2
  done

  while true; do
    IFS= read -rsn1 key
    [[ "$key" == "$ESC" ]] && { IFS= read -rsn2 -t 0.1 seq; key="$ESC$seq"; }
    case "$key" in
      "${ESC}[A"|"k") (( idx = (idx - 1 + total) % total )) ;;
      "${ESC}[B"|"j") (( idx = (idx + 1) % total )) ;;
      "") break ;;
      "q"|$'\x03') tput cnorm >/dev/tty 2>/dev/null; printf "\n" >&2; return 1 ;;
    esac
    printf "\e[%dA" "$total" >&2
    for i in "${!labels[@]}"; do
      [ "$i" -eq "$idx" ] && printf "\e[32m> %s\e[0m\n" "${labels[$i]}" >&2 || printf "  %s\n" "${labels[$i]}" >&2
    done
  done

  tput cnorm >/dev/tty 2>/dev/null
  printf "\n" >&2
  if [ "${profiles[$idx]}" = "__ABORT__" ]; then
    echo "Selection aborted." >&2
    return 1
  fi
  echo "${profiles[$idx]}"
}

aws() {
  case "$1" in
    login)
      local session="$2"
      if [ -z "$session" ]; then
        session=$(_aws_pick_session) || return 1
        session="${session%$'\r'}"
      fi
      echo "Logging into SSO session: $session"
      if command aws sso login --sso-session "$session"; then
        echo "Login successful for session: $session"
        echo "$session" > "$HOME/.aws/last-session"
      else
        echo "Login failed. Check session name or network."
        return 1
      fi
      ;;

    logout)
      local session="$2"
      if [ -z "$session" ]; then
        echo "Session name required. Use: aws logout smaitic or aws logout smaitik"
        return 1
      fi
      echo "Logging out of SSO session: $session"
      if command aws sso logout; then
        unset AWS_PROFILE
        unset KUBECONFIG
        rm -f "$HOME/.aws/last-profile"
        echo "Logout successful for session: $session"
        echo "To log back in run: aws login $session"
      else
        echo "Logout failed."
        return 1
      fi
      ;;

    switch)
      local target="$2"

      local _last_sess _acct_name=""
      _last_sess=$(cat "$HOME/.aws/last-session" 2>/dev/null | tr -d $'\r')
      if [ -n "$_last_sess" ]; then
        _acct_name=$(_aws_get_display_name "$_last_sess")
        echo "[AWS]: $_acct_name"
      fi

      if [ "$target" = "clear" ]; then
        unset AWS_PROFILE
        unset KUBECONFIG
        rm -f "$HOME/.aws/last-profile"
        echo "AWS_PROFILE and KUBECONFIG cleared. SSO session is still active."
        return 0
      fi

      if [ -z "$target" ]; then
        if [ -n "$_acct_name" ]; then
          echo "Select role under $_acct_name account:"
          echo ""
        fi
        local selected
        selected=$(_aws_pick_profile "$_last_sess") || return 1
        export AWS_PROFILE="$selected"
        echo "Verifying credentials for $selected"
        local identity
        identity=$(command aws sts get-caller-identity --output json 2>&1)
        if [ $? -ne 0 ]; then
          echo "Session check failed for $selected. Run: aws login"
          return 1
        fi
        local role=$(echo "$identity" | grep -o '"Arn":[^,]*' | sed 's/.*assumed-role\///;s/".*//')
        echo "Switched to: $selected"
        echo "Role: $role"
        mkdir -p "$HOME/.aws"
        echo "$selected" > "$HOME/.aws/last-profile"
        return 0
      fi

      local profile="" cluster="<YOUR_ORG_NAME>-production" region="ap-south-1"
      case "$target" in
        lead)  profile="<YOUR_ORG_NAME>-lead" ;;
        power) profile="<YOUR_ORG_NAME>-power" ;;
        read)  profile="<YOUR_ORG_NAME>-read" ;;
        svpl-power)
          profile="svpl-power"
          cluster="smaitik-engineering"
          region="us-east-2"
          ;;
        *)
          echo "Unknown profile: $target"
          echo "Usage: aws switch lead or power or read or svpl-power or clear"
          return 1
          ;;
      esac

      export AWS_PROFILE="$profile"
      echo "Verifying credentials for $profile"
      local identity
      identity=$(command aws sts get-caller-identity --output json 2>&1)
      if [ $? -ne 0 ]; then
        echo "Profile set to $profile but session check failed."
        echo "You likely need to run: aws login"
        return 1
      fi
      local role=$(echo "$identity" | grep -o '"Arn":[^,]*' | sed 's/.*assumed-role\///;s/".*//')
      echo "Switched to: $profile"
      echo "Role: $role"

      local kubeconfig_path="$HOME/.kube/config-$target"
      echo "Fetching kubeconfig for $target"
      if command aws eks update-kubeconfig \
          --name "$cluster" \
          --region "$region" \
          --profile "$profile" \
          --kubeconfig "$kubeconfig_path" \
          --alias "$target" > /dev/null 2>&1; then
        export KUBECONFIG="$kubeconfig_path"
        chmod 600 "$kubeconfig_path"
        echo "Kubeconfig ready: $kubeconfig_path"
        mkdir -p "$HOME/.aws"
        echo "$target" > "$HOME/.aws/last-profile"
        local kctx
        kctx=$(kubectl --kubeconfig "$kubeconfig_path" config current-context 2>&1)
        if kubectl --kubeconfig "$kubeconfig_path" get ns > /dev/null 2>&1; then
          echo "kubectl context: $kctx (cluster reachable)"
        else
          echo "kubectl context: $kctx (cluster not reachable, check RBAC or network)"
        fi
      else
        echo "Failed to fetch kubeconfig for $target."
        echo "Check EKS cluster name, region, and IAM permissions for $profile."
        return 1
      fi
      ;;

    status)
      if [ -z "$AWS_PROFILE" ]; then
        echo "No AWS_PROFILE set. Run: aws switch lead or power or read"
        return 1
      fi
      echo "Current profile: $AWS_PROFILE"
      local identity
      identity=$(command aws sts get-caller-identity --output json 2>&1)
      if [ $? -eq 0 ]; then
        echo "$identity"
      else
        echo "Session expired or invalid. Run: aws login"
        return 1
      fi

      local cache_file expires_at=""
      cache_file=$(ls -t "$HOME/.aws/sso/cache"/*.json 2>/dev/null | head -n 1)
      if [ -n "$cache_file" ] && [ -f "$cache_file" ]; then
        if command -v jq >/dev/null 2>&1; then
          expires_at=$(jq -r '.expiresAt // empty' "$cache_file" 2>/dev/null)
        fi
        if [ -z "$expires_at" ]; then
          expires_at=$(grep -o '"expiresAt":[ ]*"[^"]*"' "$cache_file" 2>/dev/null | head -n 1 | cut -d '"' -f 4)
        fi
      fi

      if [ -n "$expires_at" ]; then
        local expire_epoch current_epoch
        expire_epoch=$(date -u -d "$expires_at" +%s 2>/dev/null)
        current_epoch=$(date -u +%s 2>/dev/null)
        if [ -n "$expire_epoch" ] && [ -n "$current_epoch" ]; then
          local diff_mins=$(( (expire_epoch - current_epoch) / 60 ))
          if [ $diff_mins -le 0 ]; then
            echo "SSO token expired. Run: aws login"
          elif [ $diff_mins -lt 30 ]; then
            echo "SSO token expires in $diff_mins minutes. Consider running: aws login soon."
          else
            echo "SSO token valid for $diff_mins more minutes."
          fi
        else
          echo "Could not determine token expiry."
        fi
      else
        echo "Could not determine token expiry."
      fi

      if [ -n "$KUBECONFIG" ]; then
        echo "Current KUBECONFIG: $KUBECONFIG"
        kubectl config current-context 2>&1
      else
        echo "No KUBECONFIG set."
      fi
      ;;

    menu)
      echo "aws login [session]    -    Log into SSO. Default session is <YOUR_ORG_NAME>."
      echo "aws logout             -    Log out of SSO. Clears token, AWS_PROFILE, KUBECONFIG."
      echo "aws switch lead        -    Switch to <YOUR_ORG_NAME>-lead profile and fetch its kubeconfig."
      echo "aws switch power       -    Switch to <YOUR_ORG_NAME>-power profile and fetch its kubeconfig."
      echo "aws switch read        -    Switch to <YOUR_ORG_NAME>-read profile and fetch its kubeconfig."
      echo "aws switch svpl-power  -    Switch to svpl-power profile (SVPL Engineering stage) and fetch its kubeconfig."
      echo "aws switch clear       -    Unset AWS_PROFILE and KUBECONFIG, keep SSO session alive."
      echo "aws status             -    Show current profile, identity, and kubectl context."
      echo "aws menu               -    Show this list."
      echo "aws anything-else      -    Passes through to normal AWS CLI."
      ;;

    *)
      command aws "$@"
      ;;
  esac
}

if command -v aws_completer &> /dev/null; then
  complete -C "$(command -v aws_completer)" aws
fi

if [ -s "$HOME/.aws/last-profile" ]; then
  _last_role=$(cat "$HOME/.aws/last-profile" 2>/dev/null)
  case "$_last_role" in
    lead|power|read)
      export AWS_PROFILE="<YOUR_ORG_NAME>-$_last_role"
      export KUBECONFIG="$HOME/.kube/config-$_last_role"
      ;;
  esac
  unset _last_role
fi
