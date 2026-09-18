_aws_get_sso_sessions() {
  local config_file="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
  if [ -f "$config_file" ]; then
    grep -E '^\[sso-session ' "$config_file" 2>/dev/null | sed -E 's/\[sso-session[[:space:]]+([^]]+)\]/\1/'
  fi
}

_aws_select_menu() {
  local prompt="$1"
  shift
  local options=("$@")
  local cur=0
  local count=${#options[@]}
  local key=""

  if [ "$count" -eq 0 ]; then
    return 1
  fi
  if [ "$count" -eq 1 ]; then
    REPLY="${options[0]}"
    return 0
  fi

  # Hide cursor
  printf "\033[?25l" >&2
  trap 'printf "\033[?25h" >&2; return 1' INT TERM

  echo "$prompt (↑/↓ to navigate, Enter to select, q to cancel):" >&2

  while true; do
    local i=0
    for opt in "${options[@]}"; do
      if [ "$i" -eq "$cur" ]; then
        printf "\033[1;32m> [%s]\033[0m\n" "$opt" >&2
      else
        printf "    %s  \n" "$opt" >&2
      fi
      i=$((i + 1))
    done

    IFS= read -rsn1 key
    if [ "$key" = $'\x1b' ]; then
      read -rsn2 -t 0.1 rest
      key+="$rest"
    fi

    case "$key" in
      $'\x1b[A'|[kK]) # Up
        cur=$(( (cur - 1 + count) % count ))
        ;;
      $'\x1b[B'|[jJ]) # Down
        cur=$(( (cur + 1) % count ))
        ;;
      ""|$'\n'|$'\r') # Enter
        printf "\033[?25h" >&2
        trap - INT TERM
        REPLY="${options[$cur]}"
        return 0
        ;;
      q|Q|$'\x03') # Cancel
        printf "\033[?25h" >&2
        trap - INT TERM
        echo "Cancelled." >&2
        return 1
        ;;
    esac

    # Move cursor back up to redraw menu
    printf "\033[%dA" "$count" >&2
  done
}

aws() {
  case "$1" in
    login)
      local session="$2"
      if [ -z "$session" ]; then
        local sessions=($(_aws_get_sso_sessions))
        if [ ${#sessions[@]} -eq 0 ]; then
          echo "No [sso-session] found in ~/.aws/config."
          return 1
        elif [ ${#sessions[@]} -eq 1 ]; then
          session="${sessions[0]}"
        else
          if _aws_select_menu "Select SSO Session" "${sessions[@]}"; then
            session="$REPLY"
          else
            return 1
          fi
        fi
      fi
      echo "Logging into SSO session: $session"
      if command aws sso login --sso-session "$session"; then
        echo "Login successful for session: $session"
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

      if [ "$target" = "clear" ]; then
        unset AWS_PROFILE
        unset KUBECONFIG
        rm -f "$HOME/.aws/last-profile"
        echo "AWS_PROFILE and KUBECONFIG cleared. SSO session is still active."
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
        "")
          echo "Missing profile name."
          echo "Usage: aws switch lead or power or read or svpl-power or clear"
          return 1
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
