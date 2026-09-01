# linux alias
alias cc='clear'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
# history based steps back
cd() {
    case "$1" in
        "") pushd "$HOME" > /dev/null ;;
        "-") builtin cd - > /dev/null ;;
        *)  pushd "$1" > /dev/null ;;
    esac
}

alias ,,='popd > /dev/null || echo "No previous directory."'
alias ,,,='popd > /dev/null 2>&1; popd > /dev/null || echo "No previous directory."'
alias ,,,,='popd > /dev/null 2>&1; popd > /dev/null 2>&1; popd > /dev/null || echo "No previous directory."'
alias myip='curl -s ifconfig.me; echo'
alias ports='sudo ss -tulpn'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
psg() {
    ps aux | grep -i "$1" | grep -v grep
}

# nano as default editor
export EDITOR='nano'
export VISUAL='nano'

# kubectl alias
alias k='kubectl'
alias pods='kubectl get pods'
alias podsw='kubectl get pods -w'
alias badpods='kubectl get pods --field-selector=status.phase!=Running'
alias svc='kubectl get service'
alias svcw='kubectl get service -w'
alias deploy='kubectl get deployment'
alias deployw='kubectl get deployment -w'
alias nodes='kubectl get nodes'
alias nodesw='kubectl get nodes -w'
alias ns='kubectl get namespace'
alias cm='kubectl get configmap'
alias secrets='kubectl get secret'
alias ing='kubectl get ingress'
alias pvc='kubectl get pvc'
alias pv='kubectl get pv'
alias jobs='kubectl get jobs'
alias cj='kubectl get cronjob'
alias events='kubectl get events --sort-by=.lastTimestamp'
alias rs='kubectl get replicaset'
alias sts='kubectl get statefulset'
alias stsw='kubectl get statefulset -w'
alias ds='kubectl get daemonset'
alias dsw='kubectl get daemonset -w'
alias logs='kubectl logs'
alias logsf='kubectl logs -f'
alias exec='kubectl exec -it'
alias ctx='kubectl config current-context'
alias rst='kubectl rollout status'
alias top='kubectl top pods'
alias topn='kubectl top nodes'
alias all='kubectl get all'
alias taints="kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints'"
alias pf='kubectl port-forward'
alias api='kubectl api-resources'
alias explain='kubectl explain'
alias apply='kubectl apply -f'
alias edit='kubectl edit'
alias rr='kubectl rollout restart'
alias del='kubectl delete -f'
alias delete='kubectl delete -f'
alias undo='kubectl rollout undo'
alias allimg="kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{\"/\"}{.metadata.name}{\": \"}{range .spec.containers[*]}{.image}{\" \"}{end}{\"\n\"}{end}'"
desc() {
    [ -z "$1" ] && { echo "usage: desc <resource> [name]"; return 1; }
    kubectl describe "$@"
}
kyaml() {
    [ -z "$1" ] && { echo "usage: kyaml <resource> [name]"; return 1; }
    kubectl get "$@" -o yaml
}
img() {
    [ -z "$1" ] && { echo "usage: img <pod-name> [namespace]"; return 1; }
    local ns="${2:+-n $2}"
    kubectl get pod "$1" $ns -o jsonpath='{.metadata.name}{": "}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}'
}
nimg() {
    local ns_flag="$*"
    if [ -n "$1" ] && [[ "$1" != -* ]]; then
        ns_flag="-n $1"
    fi
    kubectl get pods $ns_flag -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}'
}
