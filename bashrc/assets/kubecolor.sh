#!/usr/bin/env bash

# kubecolor integration
if command -v kubecolor >/dev/null 2>&1; then
    alias kubectl='kubecolor'
    alias k='kubecolor'
    complete -o default -F __start_kubectl kubecolor 2>/dev/null || true
    complete -o default -F __start_kubectl k 2>/dev/null || true
fi
