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
          smaitik-prod) label="Smaitic Venture Prod" ;;
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
    smaitik-prod) echo "Smaitic Venture Prod" ;;
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
  local cur_profile="" cur_session="" cur_role="" cur_region="" line
  while IFS= read -r line; do
    local clean="${line%$'\r'}"
    if [[ "$clean" =~ ^\[profile[[:space:]]+([^]]+)\]$ ]]; then
      if [ "$cur_profile" = "$target_prof" ]; then
        echo "$cur_session|$cur_role|$cur_region"
        return 0
      fi
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
      if [ "$cur_profile" = "$target_prof" ]; then
        echo "$cur_session|$cur_role|$cur_region"
        return 0
      fi
      cur_profile=""
      cur_session=""
      cur_role=""
      cur_region=""
    fi
  done < "$HOME/.aws/config"
  if [ "$cur_profile" = "$target_prof" ]; then
    echo "$cur_session|$cur_role|$cur_region"
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

  if [ -z "$matched_prof" ] && [ -n "$target_sess" ]; then
    local -a dyn_roles=()
    while IFS= read -r r; do
      [ -n "$r" ] && dyn_roles+=("$r")
    done < <(_aws_fetch_dynamic_roles "$target_sess" 2>/dev/null)

    local t_lower r_match=""
    t_lower=$(echo "$target" | tr '[:upper:]' '[:lower:]')
    for r in "${dyn_roles[@]}"; do
      avail_roles+=("$r")
      local r_lower=$(echo "$r" | tr '[:upper:]' '[:lower:]')
      if [ "$t_lower" = "$r_lower" ] || \
         [ "$t_lower" = "power" -a "$r_lower" = "poweruseraccess" ] || \
         [ "$t_lower" = "read" -a "$r_lower" = "readonlyaccess" ] || \
         [ "$t_lower" = "lead" -a "$r_lower" = "leaduseraccess" ]; then
        r_match="$r"
        break
      fi
    done

    if [ -n "$r_match" ]; then
      local def_region
      case "$target_sess" in
        smaitik|smaitik-prod) def_region="us-east-2" ;;
        *) def_region="ap-south-1" ;;
      esac
      matched_prof=$(_aws_ensure_profile_for_role "$target_sess" "$r_match" "$def_region")
      matched_role="$r_match"
      matched_reg="$def_region"
    fi
  fi

  if [ -n "$matched_prof" ]; then
    echo "MATCH|$matched_prof|$matched_role|$matched_reg"
  elif [ -n "$cross_session" ]; then
    local cross_name=$(_aws_get_display_name "$cross_session")
    echo "CROSS|$cross_name|$cross_role|${avail_roles[*]}"
  else
    echo "NONE|${avail_roles[*]}"
  fi
}

_aws_pick_cluster() {
  local -a clusters=("$@")
  local -a labels=()
  local i
  for i in "${clusters[@]}"; do
    labels+=("$i")
  done
  labels+=("[Abort]")
  clusters+=("__ABORT__")

  local idx=0 total=${#labels[@]} ESC=$'\033'

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
  [ "${clusters[$idx]}" = "__ABORT__" ] && return 1
  echo "${clusters[$idx]}"
}

_aws_fetch_kubeconfig() {
  local profile="$1" session="$2" region="$3" role_name="$4"
  local disp_name
  disp_name=$(_aws_get_display_name "$session")

  if [ -z "$region" ]; then
    case "$session" in
      smaitik|smaitik-prod) region="us-east-2" ;;
      *) region="ap-south-1" ;;
    esac
  fi

  local cluster_json cluster_list=()
  cluster_json=$(command aws eks list-clusters --profile "$profile" --region "$region" --output json 2>/dev/null)
  if [ -n "$cluster_json" ]; then
    while IFS= read -r c; do
      [ -n "$c" ] && cluster_list+=("$c")
    done < <(echo "$cluster_json" | grep -o '"[^"]*"' | tr -d '"' | grep -v '^clusters$' 2>/dev/null)
  fi

  local target_cluster=""
  if [ ${#cluster_list[@]} -eq 0 ]; then
    case "$session" in
      smaitik) target_cluster="smaitik-engineering" ;;
      smaitik-prod) target_cluster="smaitik-production" ;;
      *) target_cluster="smaitic-production" ;;
    esac
  elif [ ${#cluster_list[@]} -eq 1 ]; then
    target_cluster="${cluster_list[0]}"
  else
    echo "Select EKS cluster under $disp_name account:"
    echo ""
    target_cluster=$(_aws_pick_cluster "${cluster_list[@]}")
    if [ -z "$target_cluster" ]; then
      echo "Cluster selection skipped. AWS_PROFILE remains active."
      return 0
    fi
  fi

  local kubeconfig_path="$HOME/.kube/config-$session-$profile"
  echo "Fetching kubeconfig for $role_name ($target_cluster in $region)..."
  mkdir -p "$HOME/.kube"

  if command aws eks update-kubeconfig \
      --name "$target_cluster" \
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
    echo "Notice: Could not fetch kubeconfig for cluster '$target_cluster' (region: $region)."
  fi
}

_aws_get_session_details() {
  local target_session="$1"
  local cur_sess="" s_url="" s_reg="" line
  while IFS= read -r line; do
    local clean="${line%$'\r'}"
    if [[ "$clean" =~ ^\[sso-session[[:space:]]+([^]]+)\]$ ]]; then
      if [ "$cur_sess" = "$target_session" ]; then
        break
      fi
      cur_sess="${BASH_REMATCH[1]%$'\r'}"
      s_url=""
      s_reg=""
    elif [[ "$clean" =~ ^sso_start_url[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      local v="${BASH_REMATCH[1]%$'\r'}"
      v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
      [ "$cur_sess" = "$target_session" ] && s_url="$v"
    elif [[ "$clean" =~ ^sso_region[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      local v="${BASH_REMATCH[1]%$'\r'}"
      v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
      [ "$cur_sess" = "$target_session" ] && s_reg="$v"
    fi
  done < "$HOME/.aws/config"
  echo "$s_url|$s_reg"
}

_aws_get_session_account_id() {
  local target_session="$1"
  local cur_sess="" cur_prof="" line
  while IFS= read -r line; do
    local clean="${line%$'\r'}"
    if [[ "$clean" =~ ^\[profile[[:space:]]+([^]]+)\]$ ]]; then
      cur_prof="${BASH_REMATCH[1]%$'\r'}"
      cur_sess=""
    elif [[ "$clean" =~ ^sso_session[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      local v="${BASH_REMATCH[1]%$'\r'}"
      cur_sess="${v#"${v%%[![:space:]]*}"}"; cur_sess="${cur_sess%"${cur_sess##*[![:space:]]}"}"
    elif [[ "$clean" =~ ^sso_account_id[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      local v="${BASH_REMATCH[1]%$'\r'}"
      v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
      if [ "$cur_sess" = "$target_session" ] && [[ "$v" =~ ^[0-9]{12}$ ]]; then
        echo "$v"
        return 0
      fi
    fi
  done < "$HOME/.aws/config"
}

_aws_fetch_dynamic_roles() {
  local session="$1"
  local sess_info s_url s_reg acct_id token
  sess_info=$(_aws_get_session_details "$session")
  s_url=$(echo "$sess_info" | cut -d'|' -f1)
  s_reg=$(echo "$sess_info" | cut -d'|' -f2)
  [ -z "$s_reg" ] && s_reg="ap-south-1"

  acct_id=$(_aws_get_session_account_id "$session")

  local f t_url t_val
  for f in "$HOME/.aws/sso/cache"/*.json; do
    [ ! -f "$f" ] && continue
    if command -v jq >/dev/null 2>&1; then
      t_url=$(jq -r '.startUrl // empty' "$f" 2>/dev/null)
      t_val=$(jq -r '.accessToken // empty' "$f" 2>/dev/null)
    else
      t_url=$(grep -o '"startUrl":[ ]*"[^"]*"' "$f" 2>/dev/null | head -n1 | cut -d'"' -f4)
      t_val=$(grep -o '"accessToken":[ ]*"[^"]*"' "$f" 2>/dev/null | head -n1 | cut -d'"' -f4)
    fi
    if [ -n "$t_val" ]; then
      if [ -z "$s_url" ] || [ "$t_url" = "$s_url" ]; then
        token="$t_val"
        break
      fi
    fi
  done

  [ -z "$token" ] && return 1

  if [ -z "$acct_id" ]; then
    local acct_json
    acct_json=$(command aws sso list-accounts --access-token "$token" --region "$s_reg" --output json 2>/dev/null)
    if [ -n "$acct_json" ]; then
      if command -v jq >/dev/null 2>&1; then
        acct_id=$(echo "$acct_json" | jq -r '.accountList[0].accountId // empty' 2>/dev/null)
      else
        acct_id=$(echo "$acct_json" | grep -o '"accountId":[ ]*"[0-9]*"' | head -n1 | cut -d'"' -f4)
      fi
    fi
  fi

  [ -z "$acct_id" ] && return 1

  local role_json
  role_json=$(command aws sso list-account-roles --access-token "$token" --account-id "$acct_id" --region "$s_reg" --output json 2>/dev/null)
  [ -z "$role_json" ] && return 1

  if command -v jq >/dev/null 2>&1; then
    echo "$role_json" | jq -r '.roleList[].roleName' 2>/dev/null
  else
    echo "$role_json" | grep -o '"roleName":[ ]*"[^"]*"' | cut -d'"' -f4
  fi
}

_aws_ensure_profile_for_role() {
  local session="$1" role_name="$2" region="$3"
  local config_file="$HOME/.aws/config"
  local acct_id
  acct_id=$(_aws_get_session_account_id "$session")
  if [ -z "$region" ]; then
    case "$session" in
      smaitik|smaitik-prod) region="us-east-2" ;;
      *) region="ap-south-1" ;;
    esac
  fi

  local prof_name="${session}-${role_name}"

  if grep -q "^\[profile[[:space:]]\+${prof_name}\]" "$config_file" 2>/dev/null; then
    echo "$prof_name"
    return 0
  fi

  {
    echo ""
    echo "[profile $prof_name]"
    echo "sso_session = $session"
    echo "sso_account_id = ${acct_id:-<ACCOUNT_ID>}"
    echo "sso_role_name = $role_name"
    echo "region = $region"
    echo "output = json"
  } >> "$config_file"

  echo "$prof_name"
}

_aws_pick_profile() {
  local target_session="$1"
  local -a profiles labels
  local cur_profile="" cur_session="" cur_role="" line

  # Dynamic role fetching for any active/target session
  if [ -n "$target_session" ]; then
    local -a dyn_roles=()
    while IFS= read -r r; do
      [ -n "$r" ] && dyn_roles+=("$r")
    done < <(_aws_fetch_dynamic_roles "$target_session" 2>/dev/null)

    if [ ${#dyn_roles[@]} -gt 0 ]; then
      for r in "${dyn_roles[@]}"; do
        profiles+=("$r")
        labels+=("$r")
      done
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

      local sel_role="${profiles[$idx]}"
      local def_region
      case "$target_session" in
        smaitik|smaitik-prod) def_region="us-east-2" ;;
        *) def_region="ap-south-1" ;;
      esac
      _aws_ensure_profile_for_role "$target_session" "$sel_role" "$def_region"
      return 0
    fi
  fi

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
        echo ""
        aws switch
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

        local prof_info role_display reg
        prof_info=$(_aws_get_profile_info "$selected")
        role_display=$(echo "$prof_info" | cut -d'|' -f2)
        reg=$(echo "$prof_info" | cut -d'|' -f3)
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

        _aws_fetch_kubeconfig "$selected" "$_last_sess" "$reg" "$role_display"
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
