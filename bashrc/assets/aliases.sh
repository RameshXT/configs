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
alias clusterpolicy='kubectl get clusterpolicy'
alias policy='kubectl get policy'
alias policya='kubectl get policy -A'
d() {
    [ -z "$1" ] && { echo "usage: d [resource] <name>"; return 1; }
    case "$1" in
        pod|pods|po|svc|service|services|deploy|deployment|deployments|cm|configmap|configmaps|secret|secrets|ing|ingress|pvc|pv|job|jobs|cj|cronjob|cronjobs|rs|replicaset|sts|statefulset|ds|daemonset|node|nodes|ns|namespace|namespaces|*/*|-*)
            kubectl describe "$@"
            ;;
        *)
            kubectl describe pod "$@"
            ;;
    esac
}
alias desc='d'
alias describe='d'

yaml() {
    [ -z "$1" ] && { echo "usage: yaml [resource] <name>"; return 1; }
    case "$1" in
        pod|pods|po|svc|service|services|deploy|deployment|deployments|cm|configmap|configmaps|secret|secrets|ing|ingress|pvc|pv|job|jobs|cj|cronjob|cronjobs|rs|replicaset|sts|statefulset|ds|daemonset|node|nodes|ns|namespace|namespaces|*/*|-*)
            kubectl get "$@" -o yaml
            ;;
        *)
            kubectl get pod "$@" -o yaml
            ;;
    esac
}

img() {
    [ -z "$1" ] && { echo "usage: img <pod-name> [namespace|-n namespace]"; return 1; }
    local pod="$1"
    shift
    local ns_args=()
    if [ "$#" -gt 0 ]; then
        if [ "$1" = "-n" ]; then
            ns_args=("$@")
        else
            ns_args=("-n" "$1")
        fi
    fi
    kubectl get pod "$pod" "${ns_args[@]}" -o jsonpath='{.metadata.name}{": "}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}'
}
alias image='img'

nimg() {
    local ns_args=()
    if [ "$#" -gt 0 ]; then
        if [ "$1" = "-n" ]; then
            ns_args=("$@")
        else
            ns_args=("-n" "$1")
        fi
    fi
    kubectl get pods "${ns_args[@]}" -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}'
}
