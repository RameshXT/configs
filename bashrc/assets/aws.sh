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

_aws_get_profile_info() {
  local target_prof="$1"
  local cur_profile="" cur_session="" cur_role="" line
  while IFS= read -r line; do
    local clean="${line%$'\r'}"
    if [[ "$clean" =~ ^\[profile[[:space:]]+([^]]+)\]$ ]]; then
      if [ "$cur_profile" = "$target_prof" ]; then
        echo "$cur_session|$cur_role"
        return 0
      fi
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
      if [ "$cur_profile" = "$target_prof" ]; then
        echo "$cur_session|$cur_role"
        return 0
      fi
      cur_profile=""
      cur_session=""
      cur_role=""
    fi
  done < "$HOME/.aws/config"
  if [ "$cur_profile" = "$target_prof" ]; then
    echo "$cur_session|$cur_role"
    return 0
  fi
}

_aws_resolve_profile() {
  local target="$1" target_sess="$2"
  local cur_profile="" cur_session="" cur_role="" cur_region="" line
  local -a avail_roles
  local cross_session="" cross_role="" matched_prof="" matched_role="" matched_reg=""

  _check_prof() {
    if [ -n "$cur_profile" ]; then
      local is_match=0
      local t_lower=$(echo "$target" | tr '[:upper:]' '[:lower:]')
      local r_lower=$(echo "$cur_role" | tr '[:upper:]' '[:lower:]')
      local p_lower=$(echo "$cur_profile" | tr '[:upper:]' '[:lower:]')

      if [ "$t_lower" = "$p_lower" ] || [ "$t_lower" = "$r_lower" ] || \
         [ "$t_lower" = "power" -a "${r_lower}" = "poweruseraccess" ] || \
         [ "$t_lower" = "read" -a "${r_lower}" = "readonlyaccess" ] || \
         [ "$t_lower" = "lead" -a "${r_lower}" = "leaduseraccess" ]; then
        is_match=1
      fi

      if [ "$cur_session" = "$target_sess" ]; then
        avail_roles+=("${cur_role:-$cur_profile}")
        if [ $is_match -eq 1 ]; then
          matched_prof="$cur_profile"
          matched_role="${cur_role:-$cur_profile}"
          matched_reg="${cur_region:-ap-south-1}"
        fi
      elif [ $is_match -eq 1 ]; then
        cross_session="$cur_session"
        cross_role="${cur_role:-$cur_profile}"
      fi
    fi
  }

  while IFS= read -r line; do
    local clean="${line%$'\r'}"
    if [[ "$clean" =~ ^\[profile[[:space:]]+([^]]+)\]$ ]]; then
      _check_prof
      cur_profile="${BASH_REMATCH[1]%$'\r'}"
      cur_session=""
      cur_role=""
      cur_region=""
    elif [[ "$clean" =~ ^sso_session[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      cur_session="${BASH_REMATCH[1]%$'\r'}"
      cur_session="${cur_session#"${cur_session%%[![:space:]]*}"}"
      cur_session="${cur_session%"${cur_session##*[![:space:]]}"}"
    elif [[ "$clean" =~ ^sso_role_name[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      cur_role="${BASH_REMATCH[1]%$'\r'}"
      cur_role="${cur_role#"${cur_role%%[![:space:]]*}"}"
      cur_role="${cur_role%"${cur_role##*[![:space:]]}"}"
    elif [[ "$clean" =~ ^region[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      cur_region="${BASH_REMATCH[1]%$'\r'}"
      cur_region="${cur_region#"${cur_region%%[![:space:]]*}"}"
      cur_region="${cur_region%"${cur_region##*[![:space:]]}"}"
    elif [[ "$clean" =~ ^\[.*\]$ ]]; then
      _check_prof
      cur_profile=""
      cur_session=""
      cur_role=""
      cur_region=""
    fi
  done < "$HOME/.aws/config"
  _check_prof
  unset -f _check_prof

  if [ -n "$matched_prof" ]; then
    echo "MATCH|$matched_prof|$matched_role|$matched_reg"
  elif [ -n "$cross_session" ]; then
    local cross_name=$(_aws_get_display_name "$cross_session")
    echo "CROSS|$cross_name|$cross_role|${avail_roles[*]}"
  else
    echo "NONE|${avail_roles[*]}"
  fi
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

        local prof_info role_display
        prof_info=$(_aws_get_profile_info "$selected")
        role_display="${prof_info##*|}"
        [ -z "$role_display" ] && role_display="$selected"

        echo "Verifying credentials for $role_display"
        local identity
        identity=$(command aws sts get-caller-identity --output json 2>&1)
        if [ $? -ne 0 ]; then
          echo "Session check failed for $role_display. Run: aws login"
          return 1
        fi
        local role=$(echo "$identity" | grep -o '"Arn":[^,]*' | sed 's/.*assumed-role\///;s/".*//')
        echo "Switched to: $role_display"
        echo "Role: $role"
        mkdir -p "$HOME/.aws"
        echo "$selected" > "$HOME/.aws/last-profile"
        return 0
      fi

      local res status_code m_prof m_role m_reg
      res=$(_aws_resolve_profile "$target" "$_last_sess")
      status_code=$(echo "$res" | cut -d'|' -f1)

      if [ "$status_code" = "CROSS" ]; then
        local cross_acc=$(echo "$res" | cut -d'|' -f2)
        local roles=$(echo "$res" | cut -d'|' -f4)
        echo "Error: Role '$target' belongs to $cross_acc. You are currently logged into $_acct_name."
        echo "Available roles under $_acct_name: $roles"
        return 1
      elif [ "$status_code" = "NONE" ]; then
        local roles=$(echo "$res" | cut -d'|' -f2)
        echo "Error: Unknown role '$target'."
        echo "Available roles under $_acct_name: $roles"
        return 1
      fi

      m_prof=$(echo "$res" | cut -d'|' -f2)
      m_role=$(echo "$res" | cut -d'|' -f3)
      m_reg=$(echo "$res" | cut -d'|' -f4)

      export AWS_PROFILE="$m_prof"
      echo "Verifying credentials for $m_role"
      local identity
      identity=$(command aws sts get-caller-identity --output json 2>&1)
      if [ $? -ne 0 ]; then
        echo "Profile set to $m_prof but session check failed."
        echo "You likely need to run: aws login"
        return 1
      fi
      local role=$(echo "$identity" | grep -o '"Arn":[^,]*' | sed 's/.*assumed-role\///;s/".*//')
      echo "Switched to: $m_role"
      echo "Role: $role"

      local cluster="<YOUR_ORG_NAME>-production"
      if [ "$_last_sess" = "smaitik" ]; then
        cluster="smaitik-engineering"
      fi

      local kubeconfig_path="$HOME/.kube/config-$target"
      echo "Fetching kubeconfig for $target"
      if command aws eks update-kubeconfig \
          --name "$cluster" \
          --region "$m_reg" \
          --profile "$m_prof" \
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
        echo "Check EKS cluster name, region, and IAM permissions for $m_prof."
        return 1
      fi
      ;;

    status)
      local _last_sess
      _last_sess=$(cat "$HOME/.aws/last-session" 2>/dev/null | tr -d $'\r')

      if [ -z "$AWS_PROFILE" ]; then
        if [ -n "$_last_sess" ]; then
          local _acct_name=$(_aws_get_display_name "$_last_sess")
          echo "[AWS]: $_acct_name"
          echo "Status: No role selected. Run: aws switch"
        else
          echo "Status: Not logged in. Run: aws login"
        fi
        return 1
      fi

      local prof_info sess role_name
      prof_info=$(_aws_get_profile_info "$AWS_PROFILE")
      sess="${prof_info%%|*}"
      role_name="${prof_info##*|}"
      [ -z "$sess" ] && sess="$_last_sess"
      if [ -n "$sess" ]; then
        local _acct_name=$(_aws_get_display_name "$sess")
        echo "[AWS]: $_acct_name"
      fi
      [ -n "$role_name" ] && echo "Role: $role_name"

      local identity
      identity=$(command aws sts get-caller-identity --output json 2>&1)
      if [ $? -eq 0 ]; then
        echo "$identity"
      else
        echo "Status: Session expired or invalid. Run: aws login"
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
