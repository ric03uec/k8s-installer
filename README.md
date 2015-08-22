# k8s-installer

Usage:
---

```
Usage:
  ./kube-installer.sh

  Options:
    --master <master ip address>                       Install kube master with provided IP
    --slave  <slave ip address> <master ip address>    Install kube slave with provided IP
```

Objectives:
---
- provide a pure `bash` based installer to install kubernetes on custom nodes
- easily upgradable cluster
- declarative cluster configuration

TODO:
---
Future work for which suggestions/PRs are welcome
- move master components into containers
- download only the required binaries instead of complete k8s tar archive
- use certs for TLS between master-node
- use tokens for authorization of node components
- use json config for providing a declarative installation
- make cluster easily upgradable
- post installation cleanup
- support more OS's and systemd installations

Complete:
---
- first version of master and slave installation
- tested to be working with 3 vagrant nodes k8s cluster
- tested to be working with 3 Digital Ocean nodes k8s cluster
- `flannel` used as overlay network
- can be used to bring up a multi-node kubernetes cluster for ubuntu 14.04 nodes
