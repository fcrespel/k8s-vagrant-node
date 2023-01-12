# Kubernetes Vagrant node

This repository contains a [Vagrant](https://www.vagrantup.com) VM to run a Kubernetes node (master or worker) for local testing/debugging, using:
- [CRI-O](https://cri-o.io) as the container runtime
- [Calico](https://www.projectcalico.org) as the network plugin
- [WireGuard](https://www.wireguard.com) to encrypt communication between nodes
- [Ingress Nginx](https://kubernetes.github.io/ingress-nginx/) to expose ingress resources

## Prerequisites

Make sure you have [VirtualBox](https://www.virtualbox.org) and [Vagrant](https://www.vagrantup.com) installed before starting.

You may clone this repository mutliple times in different folders to build a cluster with multiple VMs (e.g. 1 master and 2 workers). 

## Configuration

First, configure the `Vagrantfile`:
- Update the `private_network` IP address (e.g. 192.168.56.101 for master, 192.168.56.102 for worker).
- Adjust `vb.memory` depending on your available RAM and node role (at least 2048 MB for a master, less for a worker).

Edit the `provision.conf.sh` file:
- Update `K8S_MASTER_IP` if you changed it in the master `Vagrantfile`
- Set `K8S_NODE_ROLE` to `master` or `worker`
- Set `K8S_NODE_NAME` to an arbitrary name  (e.g. `node1`, `node2`, ...)

For a worker node, you will need to obtain a token and certificate hash from the master first. This information is displayed at the end of master creation, if necessary you can get it again with:

```
kubeadm token create

openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'
```

Then, update the worker `provision.conf.sh`:
- Set `K8S_TOKEN` to the join token
- Set `K8S_CERTHASH` to the certificate hash

## Running

Start the VM by running `vagrant up` in the repository directory. The provisioning script will take some time to install and configure the node.

When done or if an error occurs, you should restart the VM with `vagrant reload` to make sure the updated kernel and modules are properly loaded.

After that, you may get a shell in the VM with `vagrant ssh`, and run commands such as the following:
```
# Switch to root
sudo su -

# Check pod/deployment status
kubectl get all -A

# Check Calico node status
calicoctl node status

# Check WireGuard status
wg

# Check containers running locally
crictl ps
```

If everything is OK, you may deploy pods with `kubectl` or `helm`, or configure Calico resources with `calicoctl`. You may also use `k9s` to get an interactive text-based interface.

Note that Ingress Nginx is preinstalled and exposed on node ports 30080 (HTTP) and 30443 (HTTPS).
