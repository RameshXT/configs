# linux alias
alias cc='clear'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias myip='curl -s ifconfig.me'
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
alias dpods='kubectl describe pod'
alias dsvc='kubectl describe service'
alias ddeploy='kubectl describe deployment'
alias dnodes='kubectl describe node'
alias logs='kubectl logs'
alias logsf='kubectl logs -f'
alias exec='kubectl exec -it'
alias ctx='kubectl config current-context'
alias rst='kubectl rollout status'
alias top='kubectl top pods'
alias all='kubectl get all'
alias taints="kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints'"
alias pf='kubectl port-forward'
alias api='kubectl api-resources'
alias explain='kubectl explain'
alias apply='kubectl apply -f'
alias edit='kubectl edit'
alias rr='kubectl rollout restart'

delete() {
    [ -z "$1" ] && { echo "usage: delete <file.yaml>"; return 1; }
    echo "Context: $(kubectl config current-context)"
    echo "Command: kubectl delete -f $1"
    read -rp "Proceed? [y/N] " confirm
    [[ "$confirm" == "y" ]] && kubectl delete -f "$1"
}

rollback() {
    [ -z "$1" ] && { echo "usage: rollback <deployment/name> [--to-revision=N]"; return 1; }
    echo "Context: $(kubectl config current-context)"
    echo "Command: kubectl rollout undo $*"
    read -rp "Proceed? [y/N] " confirm
    [[ "$confirm" == "y" ]] && kubectl rollout undo "$@"
}

scale() {
    [ -z "$1" ] && { echo "usage: scale <resource/name> --replicas=N"; return 1; }
    echo "Context: $(kubectl config current-context)"
    echo "Command: kubectl scale $*"
    read -rp "Proceed? [y/N] " confirm
    [[ "$confirm" == "y" ]] && kubectl scale "$@"
}
