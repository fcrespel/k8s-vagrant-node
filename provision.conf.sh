#!/bin/sh

# Versions
CRIO_VERSION="1.24"
CALICO_VERSION="3.23.5"
ETCD_VERSION="3.5.6"
INGRESS_NGINX_VERSION="4.2.5"
K8S_VERSION="1.24.9"
K9S_VERSION="0.26.7"

# Cluster config
K8S_POD_CIDR="10.244.0.0/16"
K8S_SERVICE_CIDR="10.96.0.0/12"
K8S_MASTER_IP="192.168.56.101"
K8S_MASTER_NAME="master"

# Node config
K8S_NODE_ROLE="master"     # use 'master' or 'worker'
K8S_NODE_IP="auto"         # node IP reported by kubelet, use 'auto' to detect from interface
K8S_NODE_NAME="node1"      # node name reported by kubelet
K8S_NODE_INTERFACE="eth1"  # host-only interface
K8S_NODE_LABELS="kubernetes-host= server-role-web=true"

# Join config (for worker only)
## Get token from master with: kubeadm token create
K8S_TOKEN=""
## Get hash from master with: openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'
K8S_CERTHASH=""
