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
          smaitik) label="Smaitic Venture Stage" ;;
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
    smaitik) echo "Smaitic Venture Stage" ;;
    *) echo "$session" ;;
  esac
}

_aws_ensure_account_id() {
  local session="$1"
  local acct_id="" cur_profile="" cur_session="" line needs_update=0
  local config_file="$HOME/.aws/config"

  [ ! -f "$config_file" ] && return 0

  while IFS= read -r line; do
    local clean="${line%$'\r'}"
    if [[ "$clean" =~ ^\[profile[[:space:]]+([^]]+)\]$ ]]; then
      cur_profile="${BASH_REMATCH[1]%$'\r'}"
      cur_session=""
    elif [[ "$clean" =~ ^sso_session[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      cur_session="${BASH_REMATCH[1]%$'\r'}"
      cur_session="${cur_session#"${cur_session%%[![:space:]]*}"}"
      cur_session="${cur_session%"${cur_session##*[![:space:]]}"}"
    elif [[ "$clean" =~ ^sso_account_id[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      local val="${BASH_REMATCH[1]%$'\r'}"
      val="${val#"${val%%[![:space:]]*}"}"
      val="${val%"${val##*[![:space:]]}"}"
      if [ "$cur_session" = "$session" ]; then
        if [[ ! "$val" =~ ^[0-9]{12}$ ]]; then
          needs_update=1
          break
        fi
      fi
    elif [[ "$clean" =~ ^\[.*\]$ ]]; then
      cur_profile=""
      cur_session=""
    fi
  done < "$config_file"

  if [ $needs_update -eq 1 ]; then
    local disp_name
    disp_name=$(_aws_get_display_name "$session")
    echo -e -n "\n\e[33m[AWS]\e[0m Account ID not configured for \e[32m$disp_name\e[0m.\nEnter 12-digit AWS Account ID: " >&2
    read -r acct_id </dev/tty
    acct_id=$(echo "$acct_id" | tr -d ' \r\n')

    if [[ ! "$acct_id" =~ ^[0-9]{12}$ ]]; then
      echo "Invalid Account ID (must be exactly 12 numeric digits). Aborting login." >&2
      return 1
    fi

    local tmp_file="${config_file}.tmp"
    awk -v target_sess="$session" -v new_acct="$acct_id" '
      function flush_block() {
        if (block != "") {
          if (is_profile && block_sess == target_sess) {
            if (has_acct) {
              sub(/sso_account_id[ \t]*=[ \t]*[^\r\n]+/, "sso_account_id = " new_acct, block)
            } else {
              block = block "\nsso_account_id = " new_acct
            }
          }
          printf "%s", block
          block = ""
        }
      }
      /^\[/ {
        flush_block()
        is_profile = ($0 ~ /^\[profile /)
        block_sess = ""
        has_acct = 0
        block = $0 "\n"
        next
      }
      {
        if ($0 ~ /^[ \t]*sso_session[ \t]*=/) {
          split($0, a, "=")
          gsub(/^[ \t]+|[ \t\r]+$/, "", a[2])
          block_sess = a[2]
        }
        if ($0 ~ /^[ \t]*sso_account_id[ \t]*=/) {
          has_acct = 1
        }
        block = block $0 "\n"
      }
      END { flush_block() }
    ' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"

    echo -e "\e[32m[OK]\e[0m Saved Account ID $acct_id for $disp_name in ~/.aws/config\n" >&2
  fi
  return 0
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

_aws_fetch_kubeconfig() {
  local profile="$1" session="$2" region="$3" role_name="$4"
  local cluster=""

  if [ "$session" = "smaitik" ]; then
    cluster="smaitik-engineering"
  else
    cluster="smaitic-production"
  fi

  [ -z "$region" ] && region="ap-south-1"

  local kubeconfig_path="$HOME/.kube/config-$session-$profile"
  echo "Fetching kubeconfig for $role_name ($cluster in $region)..."
  mkdir -p "$HOME/.kube"

  if command aws eks update-kubeconfig \
      --name "$cluster" \
      --region "$region" \
      --profile "$profile" \
      --kubeconfig "$kubeconfig_path" \
      --alias "$role_name" > /dev/null 2>&1; then
    export KUBECONFIG="$kubeconfig_path"
    chmod 600 "$kubeconfig_path"
    mkdir -p "$HOME/.aws"
    echo "$kubeconfig_path" > "$HOME/.aws/last-kubeconfig"
    echo "Kubeconfig ready: $kubeconfig_path"
    local kctx
    kctx=$(kubectl --kubeconfig "$kubeconfig_path" config current-context 2>/dev/null)
    if kubectl --kubeconfig "$kubeconfig_path" get ns > /dev/null 2>&1; then
      echo "kubectl context: $kctx (cluster reachable)"
    else
      echo "kubectl context: $kctx"
    fi
  else
    echo "Notice: Could not fetch kubeconfig for cluster '$cluster' (region: $region)."
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
      _aws_ensure_account_id "$session" || return 1
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
        session=$(cat "$HOME/.aws/last-session" 2>/dev/null | tr -d $'\r')
      fi
      if [ -z "$session" ]; then
        echo "Not logged into any SSO session."
        return 0
      fi
      local _disp
      _disp=$(_aws_get_display_name "$session")
      echo "Logging out of SSO session: $_disp"
      if command aws sso logout; then
        unset AWS_PROFILE
        unset KUBECONFIG
        rm -f "$HOME/.aws/last-profile"
        rm -f "$HOME/.aws/last-kubeconfig"
        rm -f "$HOME/.aws/last-session"
        echo "Logout successful for: $_disp"
      else
        echo "Logout failed."
        return 1
      fi
      ;;

    set-account|account)
      local session="$2"
      if [ -z "$session" ]; then
        session=$(_aws_pick_session) || return 1
        session="${session%$'\r'}"
      fi
      local disp_name
      disp_name=$(_aws_get_display_name "$session")
      local config_file="$HOME/.aws/config"
      [ ! -f "$config_file" ] && { echo "Error: ~/.aws/config not found" >&2; return 1; }

      local cur_acct="" cur_profile="" cur_session="" line
      while IFS= read -r line; do
        local clean="${line%$'\r'}"
        if [[ "$clean" =~ ^\[profile[[:space:]]+([^]]+)\]$ ]]; then
          cur_profile="${BASH_REMATCH[1]%$'\r'}"
          cur_session=""
        elif [[ "$clean" =~ ^sso_session[[:space:]]*=[[:space:]]*(.+)$ ]]; then
          cur_session="${BASH_REMATCH[1]%$'\r'}"
          cur_session="${cur_session#"${cur_session%%[![:space:]]*}"}"
          cur_session="${cur_session%"${cur_session##*[![:space:]]}"}"
        elif [[ "$clean" =~ ^sso_account_id[[:space:]]*=[[:space:]]*(.+)$ ]]; then
          local val="${BASH_REMATCH[1]%$'\r'}"
          val="${val#"${val%%[![:space:]]*}"}"
          val="${val%"${val##*[![:space:]]}"}"
          if [ "$cur_session" = "$session" ] && [[ "$val" =~ ^[0-9]{12}$ ]]; then
            cur_acct="$val"
            break
          fi
        elif [[ "$clean" =~ ^\[.*\]$ ]]; then
          cur_profile=""
          cur_session=""
        fi
      done < "$config_file"

      echo "[AWS]: Configure Account ID for $disp_name"
      if [ -n "$cur_acct" ]; then
        echo "Current Account ID: $cur_acct"
      else
        echo "Current Account ID: Not configured"
      fi
      echo -e -n "Enter new 12-digit AWS Account ID: "
      read -r acct_id </dev/tty
      acct_id=$(echo "$acct_id" | tr -d ' \r\n')

      if [[ ! "$acct_id" =~ ^[0-9]{12}$ ]]; then
        echo "Invalid Account ID (must be exactly 12 numeric digits). Cancelled." >&2
        return 1
      fi

      local tmp_file="${config_file}.tmp"
      awk -v target_sess="$session" -v new_acct="$acct_id" '
        function flush_block() {
          if (block != "") {
            if (is_profile && block_sess == target_sess) {
              if (has_acct) {
                sub(/sso_account_id[ \t]*=[ \t]*[^\r\n]+/, "sso_account_id = " new_acct, block)
              } else {
                block = block "\nsso_account_id = " new_acct
              }
            }
            printf "%s", block
            block = ""
          }
        }
        /^\[/ {
          flush_block()
          is_profile = ($0 ~ /^\[profile /)
          block_sess = ""
          has_acct = 0
          block = $0 "\n"
          next
        }
        {
          if ($0 ~ /^[ \t]*sso_session[ \t]*=/) {
            split($0, a, "=")
            gsub(/^[ \t]+|[ \t\r]+$/, "", a[2])
            block_sess = a[2]
          }
          if ($0 ~ /^[ \t]*sso_account_id[ \t]*=/) {
            has_acct = 1
          }
          block = block $0 "\n"
        }
        END { flush_block() }
      ' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"

      echo -e "\e[32m[OK]\e[0m Updated Account ID to $acct_id for $disp_name in ~/.aws/config\n"
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
        rm -f "$HOME/.aws/last-kubeconfig"
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

        _aws_fetch_kubeconfig "$selected" "$_last_sess" "" "$role_display"
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

      mkdir -p "$HOME/.aws"
      echo "$m_prof" > "$HOME/.aws/last-profile"

      _aws_fetch_kubeconfig "$m_prof" "$_last_sess" "$m_reg" "$m_role"
      return 0
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
      echo "aws login [session]    -    Log into SSO (interactive selector if omitted)."
      echo "aws logout <session>   -    Log out of SSO session."
      echo "aws switch [role]      -    Switch role (lead, power, read, or interactive picker)."
      echo "aws switch clear       -    Unset AWS_PROFILE and KUBECONFIG."
      echo "aws set-account        -    Update AWS Account ID for an SSO session."
      echo "aws status             -    Show active account, role, and token status."
      echo "aws menu               -    Show this list."
      echo "aws <command>          -    Passes through to native AWS CLI."
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
  _last_prof=$(cat "$HOME/.aws/last-profile" 2>/dev/null | tr -d $'\r')
  if [ -n "$_last_prof" ]; then
    export AWS_PROFILE="$_last_prof"
  fi
  unset _last_prof
fi

if [ -s "$HOME/.aws/last-kubeconfig" ]; then
  _last_kcfg=$(cat "$HOME/.aws/last-kubeconfig" 2>/dev/null | tr -d $'\r')
  if [ -f "$_last_kcfg" ]; then
    export KUBECONFIG="$_last_kcfg"
  fi
  unset _last_kcfg
fi
