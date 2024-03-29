#!/bin/bash

set -e


# Load config
echo "=== Loading configuration ==="
source "/tmp/provision.conf.sh"


# Add package repositories
echo "=== Adding repositories ==="
## CRI-O
cat > /etc/yum.repos.d/cri-o.repo <<EOF
[cri-o]
name=CRI-O
baseurl=https://pkgs.k8s.io/addons:/cri-o:/stable:/v${K8S_VERSION_MINOR}/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/addons:/cri-o:/stable:/v${K8S_VERSION_MINOR}/rpm/repodata/repomd.xml.key
EOF
## Kubernetes
cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION_MINOR}/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION_MINOR}/rpm/repodata/repomd.xml.key
exclude=cri-tools kubelet kubeadm kubectl kubernetes-cni
EOF
## EPEL/ELRepo
for PKG in epel-release elrepo-release yum-utils; do
	rpm -q $PKG || yum -y install $PKG
done


# Apply system updates
echo "=== Updating system ==="
yum -y update


# Update system config
echo "=== Configuring system ==="
## SELinux
sed -i 's#^SELINUX=.*$#SELINUX=disabled#g' /etc/selinux/config
setenforce 0 || true
## Kernel modules
cat > /etc/modules-load.d/k8s.conf <<EOF
br_netfilter
EOF
modprobe br_netfilter
## Sysctl
cat > /etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
## NetworkManager
cat > /etc/NetworkManager/conf.d/calico.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico
EOF
## Firewalld
systemctl disable --now firewalld
## Hosts
[ -n "$K8S_NODE_IP" -a "$K8S_NODE_IP" != "auto" ] || K8S_NODE_IP=$(ip -4 addr show $K8S_NODE_INTERFACE | egrep -o 'inet [0-9.]+' | cut -d' ' -f2)
grep -q " $K8S_MASTER_NAME\$" /etc/hosts || echo "$K8S_MASTER_IP $K8S_MASTER_NAME" | tee -a /etc/hosts
grep -q " $K8S_NODE_NAME\$" /etc/hosts || echo "$K8S_NODE_IP $K8S_NODE_NAME" | tee -a /etc/hosts


# Install Kubernetes
echo "=== Installing K8S ==="
### CRI-O/K8S/WireGuard
for PKG in cri-o cri-tools kubectl-${K8S_VERSION} kubelet-${K8S_VERSION} kubeadm-${K8S_VERSION} wireguard-tools kmod-wireguard; do
	rpm -q $PKG || yum -y install $PKG --disableexcludes=kubernetes
done
### Calico client
curl -fsSL "https://github.com/projectcalico/calico/releases/download/v${CALICO_VERSION}/calicoctl-linux-amd64" -o /usr/bin/calicoctl && chmod +x /usr/bin/calicoctl
### etcd client
curl -fsSL "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz" -o /tmp/etcd.tar.gz
tar -x -C /usr/local/bin -f /tmp/etcd.tar.gz --strip-components=1 "etcd-v${ETCD_VERSION}-linux-amd64/etcdctl"
rm -f /tmp/etcd.tar.gz
### Helm
curl -fsSL "https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3" | HELM_INSTALL_DIR=/usr/bin bash -s
### k9s
curl -fsSL "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz" -o /tmp/k9s.tar.gz
tar -x -C /usr/local/bin -f /tmp/k9s.tar.gz k9s
rm -f /tmp/k9s.tar.gz
### kubectx
curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx" -o /usr/local/bin/kubectx && chmod +x /usr/local/bin/kubectx
### kubens
curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBENS_VERSION}/kubens" -o /usr/local/bin/kubens && chmod +x /usr/local/bin/kubens

# Configure Kubernetes
echo "=== Configuring K8S ==="
### Kubelet
sed -i "s#^KUBELET_EXTRA_ARGS=.*#KUBELET_EXTRA_ARGS=\"--node-ip=$K8S_NODE_IP --runtime-request-timeout=15m --cgroup-driver=systemd -v=2 --fail-swap-on=false\"#g" /etc/sysconfig/kubelet
### Containers policy
echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json


# Enable and start services
echo "=== Enabling services ==="
systemctl daemon-reload
systemctl enable crio kubelet
systemctl restart crio kubelet


# Configure node
if [ "$K8S_NODE_ROLE" = "master" ]; then
	## Master
	echo "=== Configuring master node ==="
	[ -e "/var/lib/kubelet/config.yaml" ] || kubeadm init --node-name=$K8S_NODE_NAME --pod-network-cidr=$K8S_POD_CIDR --service-cidr=$K8S_SERVICE_CIDR --control-plane-endpoint=$K8S_MASTER_NAME:6443 --apiserver-advertise-address=$K8S_NODE_IP --upload-certs --cri-socket=unix:///var/run/crio/crio.sock --ignore-preflight-errors=swap

	## Configure kubectl/labels/taints
	mkdir -p /root/.kube
	cp -f /etc/kubernetes/admin.conf /root/.kube/config
	kubectl taint nodes --all node-role.kubernetes.io/master- || true
	kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
	kubectl label nodes $K8S_NODE_NAME $K8S_NODE_LABELS || true

	## Install Calico
	echo "=== Installing Calico ==="
	cat > calico.yaml <<-EOF
	installation:
	  calicoNetwork:
	    ipPools:
	    - blockSize: 26
	      cidr: $K8S_POD_CIDR
	      encapsulation: VXLANCrossSubnet
	      natOutgoing: Enabled
	      nodeSelector: all()
	    nodeAddressAutodetectionV4:
	      firstFound: false
	      interface: $K8S_NODE_INTERFACE
	EOF
	helm repo add projectcalico https://projectcalico.docs.tigera.io/charts
	helm repo update projectcalico
	helm upgrade calico projectcalico/tigera-operator --install --version $CALICO_VERSION --namespace tigera-operator --create-namespace -f calico.yaml
	rm -f calico.yaml

	## Configure Calico
	echo "=== Configuring Calico ==="
	mkdir -p /etc/calico
	cat > /etc/calico/calicoctl.cfg <<-EOF
	apiVersion: projectcalico.org/v3
	kind: CalicoAPIConfig
	metadata:
	spec:
	  datastoreType: "kubernetes"
	  kubeconfig: "/root/.kube/config"
	EOF
	while ! calicoctl get felixconfiguration default >/dev/null; do sleep 5; done
	calicoctl patch felixconfiguration default --type=merge -p '{"spec":{"wireguardEnabled":true,"failsafeInboundHostPorts":[{"protocol":"tcp","port":22},{"protocol":"udp","port":68}]}}'
	while ! calicoctl get kubecontrollersconfiguration default >/dev/null; do sleep 5; done
	calicoctl patch kubecontrollersconfiguration default -p '{"spec":{"controllers":{"node":{"hostEndpoint":{"autoCreate":"Enabled"}}}}}'

	## Install Ingress Nginx
	echo "=== Installing Ingress Nginx ==="
	cat > ingress-nginx.yaml <<-EOF
	controller:
	  image:
	    digest:
	  config:
	    proxy-body-size: 100m
	  kind: DaemonSet
	  nodeSelector:
	    server-role-web: 'true'
	  service:
	    externalTrafficPolicy: Local
	    type: NodePort
	    nodePorts:
	      http: 30080
	      https: 30443
	EOF
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx/
	helm repo update ingress-nginx
	helm upgrade ingress-nginx ingress-nginx/ingress-nginx --install --version $INGRESS_NGINX_VERSION --namespace ingress-nginx --create-namespace -f ingress-nginx.yaml
	rm -f ingress-nginx.yaml

	## Install OpenEBS
	echo "=== Installing OpenEBS ==="
	helm repo add openebs https://openebs.github.io/charts
	helm repo update openebs
	helm upgrade openebs openebs/openebs --install --version $OPENEBS_VERSION --namespace openebs --create-namespace --set localprovisioner.hostpathClass.isDefaultClass=true

elif [ "$K8S_NODE_ROLE" = "worker" ]; then
	## Worker
	echo "=== Configuring worker node ==="
	[ -e "/var/lib/kubelet/config.yaml" ] || kubeadm join --node-name=$K8S_NODE_NAME --token $K8S_TOKEN $K8S_MASTER_NAME:6443 --discovery-token-ca-cert-hash sha256:$K8S_CERTHASH --cri-socket=unix:///var/run/crio/crio.sock --ignore-preflight-errors=swap 

	## Node labels
	echo "!!! Execute the following command on master to label this node:"
	echo "kubectl label nodes $K8S_NODE_NAME $K8S_NODE_LABELS"
fi


# Final message
echo
echo "=== FINISHED ==="
echo "To access a shell prompt, please run:     vagrant ssh"
echo "Switch to root user with:                 sudo su -"
echo "On master node, check pod status with:    kubectl get all -A"
echo "Get an interactive text interface with:   k9s"
echo "On each node, check network status with:  calicoctl node status"
needs-restarting -r || echo "!!! VM needs to be restarted, please run: vagrant reload"
