# VPC CNI and pod networking: from the internet to a pod

This note follows one question at a time, in the order I asked them while looking at our load balancer in the AWS console. Each chapter answers the question the previous chapter raised. Read it from top to bottom.

Names, ports and IP addresses are the real ones from our cluster, so you can compare them with `kubectl` and the AWS console.

---

## The cast

| Name | What it is |
|---|---|
| **NLB** | the AWS Network Load Balancer. The only thing on the internet. |
| `ingress-nginx-controller` | the **Service** (type LoadBalancer) that made the NLB appear. Namespace `ingress-nginx`. |
| **nginx pods** | 2 pods running the ingress-nginx controller (`replicaCount: 2`). They route every request. |
| **AWS Load Balancer Controller** | a pod that watches Services and builds and updates the NLB in AWS |
| **Ingress** `app-ingress-resource` | only rules: `/` → frontend, `/api` and `/health` → backend |
| `frontend-service` :8080, `backend-service` :8081 | internal Services (ClusterIP) in namespace `app` |
| **VPC CNI** | the network plugin that gives every pod an IP address from our VPC |

Where they are defined:

- the NLB settings: [`tf/infra/modules/addons/nginx-ingress-controller-helm-values.yaml`](../tf/infra/modules/addons/nginx-ingress-controller-helm-values.yaml)
- the Helm installs: [`tf/infra/modules/addons/main.tf`](../tf/infra/modules/addons/main.tf)
- the routing rules: [`eks-todo-jenkins-gitops/ingress/ingress.yaml`](https://github.com/Wicky2001/eks-todo-jenkins-gitops/blob/main/ingress/ingress.yaml)

---

## Chapter 1. How the NLB came to exist

Nobody writes "create an NLB" anywhere. It appears through a chain:

```
terraform apply
 └─ Helm installs ingress-nginx
      ├─ Deployment  ingress-nginx-controller → 2 nginx pods
      └─ Service     ingress-nginx-controller, type: LoadBalancer
             │
             ▼
   AWS Load Balancer Controller sees "type: LoadBalancer"
             │
             ▼
   creates ONE NLB in AWS (in the public subnets, tag kubernetes.io/role/elb = 1)
```

- The NLB is created **once**, when the controller is installed, not when an Ingress file is applied.
- An **Ingress file creates nothing in AWS**. The nginx pods read it and add its rules to their own config. A second Ingress (for example one for Argo CD) adds more rules to the **same** NLB.
- The NLB is **not in the Terraform state**. Terraform only knows the Helm release. That is why `terraform destroy` can leave the NLB behind if the Load Balancer Controller is removed before it finishes deleting it.

## Chapter 2. What the console shows: listeners, target groups, targets

The NLB's **Resource map** in the AWS console showed this:

```
LISTENERS (2)          TARGET GROUPS (2)                 TARGETS (4)
TCP:443  ───────►  k8s-ingressn-ingressn-147559e5c8  ───►  10.0.2.81:443    healthy
                                                     ───►  10.0.24.193:443  healthy
TCP:80   ───────►  k8s-ingressn-ingressn-0f6e3862ab  ───►  10.0.2.81:80     healthy
                                                     ───►  10.0.24.193:80   healthy
```

- **Listeners** are the ports the NLB accepts from the internet. They come from the ports of the `ingress-nginx-controller` Service (`http` 80, `https` 443).
- **Targets** are **2 nginx pods × 2 ports**. `10.0.2.81` and `10.0.24.193` are the two nginx pods.
- Our app ports **8080 and 8081 never appear**. The NLB never talks to our apps. It only talks to nginx, and nginx talks to the apps (chapter 9).

Check that the targets are the nginx pods:

```bash
kubectl get pods -n ingress-nginx -o wide     # the IP column shows 10.0.2.81 and 10.0.24.193
```

## Chapter 3. Why target groups exist

**The problem.** Pods change all the time: they restart, Karpenter moves them, we scale from 2 to 3. Their IPs change. If the listener pointed at pod IPs, it would have to be rewritten after every change.

**The answer.** Put a group in the middle:

```
             fixed                        changes often
LISTENER  ──────────►  TARGET GROUP  ──────────────────►  TARGETS
"port 80"  points to    "nginx pods      holds whoever      10.0.2.81:80
           the group    on port 80"      is alive now       10.0.24.193:80
```

- The listener never changes. Only the group's member list changes, and the **AWS Load Balancer Controller** updates it automatically.
- Each group runs **health checks**. Traffic only goes to **healthy** members. If one nginx pod hangs, the NLB stops sending to it without anyone doing anything.
- There is **one group per listener**, because the group also stores **which port** to use on the targets.

A picture to remember: a reception desk (listener) sends visitors "to the IT department" (target group). The desk does not need to know who is working today. The department keeps its own list.

What one group holds:

```
TARGET GROUP  k8s-ingressn-ingressn-0f6e3862ab
 ├─ protocol and port:   TCP 80
 ├─ target type:         IP   (pod IPs, from nlb-target-type: "ip")
 ├─ health check:        "is the pod answering?" every few seconds
 └─ members:             10.0.2.81:80 healthy, 10.0.24.193:80 healthy
```

## Chapter 4. Turning off port 443

We have no TLS certificate, so on port 443 nginx only answers with its own built-in fake certificate (browsers show a warning). To listen on port 80 only, set this in the Helm values:

```yaml
controller:
  service:
    type: LoadBalancer
    enableHttps: false     # the Service gets only port 80
```

After `terraform apply`: Helm removes port 443 from the Service, and the Load Balancer Controller deletes the 443 listener and its target group. The NLB and its address stay the same. Result: 1 listener, 1 target group, 2 targets.

## Chapter 5. Why the NLB does not send traffic to the Service

`kubectl get svc -n ingress-nginx` shows:

```
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP                PORT(S)
ingress-nginx-controller             LoadBalancer   172.20.68.174   k8s-ingressn-...elb...     80:30711/TCP,443:31251/TCP
ingress-nginx-controller-admission   ClusterIP      172.20.3.74     <none>                     443/TCP
```

The Service has a fixed address, `172.20.68.174`. So why not send traffic there?

Because a **ClusterIP is virtual**. No machine owns it. It only works **inside** the cluster, where every node has rules (written by kube-proxy) that say "172.20.68.174 → one of the nginx pods". The NLB lives **outside** the cluster in the VPC and has no such rules.

```
inside the cluster:  pod → 172.20.68.174 → node rules → nginx pod     works
the NLB (outside):   NLB → 172.20.68.174 → ???                         nothing there
```

The Service is still used, as the **list of pods**. The Load Balancer Controller reads which pods match the Service's selector and copies their IPs into the target group:

```
Service selector → matching pods 10.0.2.81, 10.0.24.193 → copied into the target group
```

## Chapter 6. Two ways for an NLB to reach pods: instance mode and IP mode

`80:30711/TCP` means: Service port 80, **NodePort** 30711. A NodePort is a port opened on **every node**. It gives the NLB two possible ways in.

The example: two nodes, one nginx pod on node B.

```
Node A   10.0.1.10   (no nginx pod)
Node B   10.0.2.20   nginx pod 10.0.2.81
```

**Instance mode** (through the NodePort):

```
Target group: 10.0.1.10:30711, 10.0.2.20:30711        (every node)

Client → NLB → Node A :30711
                 │ kube-proxy rule: "30711 → an nginx pod" → the pod is on Node B
                 ▼
               Node B → nginx pod :80                   (one extra hop between nodes)
```

**IP mode** (ours: `service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"`):

```
Target group: 10.0.2.81:80                              (the pod itself)

Client → NLB → 10.0.2.81:80 → arrives at Node B → nginx pod   (no NodePort, no kube-proxy)
```

| | Instance mode | IP mode (ours) |
|---|---|---|
| Target group holds | nodes + NodePort | pod IPs |
| Last step to the pod | kube-proxy on a node | the node's kernel delivers it directly |
| Extra hop to another node | possible | never |
| Pod sees the real client address | no (unless extra settings) | easier to keep |
| Needs pods with real VPC addresses | no | **yes** (chapter 10) |

In both modes the traffic physically enters an EC2 node, because the pod lives inside it. The difference is the **address** the NLB sends to: the node's address plus NodePort (the building's front desk passes it on), or the pod's own address (a letter addressed to the flat).

**Why the NodePort exists in IP mode anyway.** Kubernetes creates a NodePort for every `type: LoadBalancer` Service automatically. In IP mode nobody uses `30711` or `31251`. They can be switched off with `allocateLoadBalancerNodePorts: false`, but leaving them is harmless.

## Chapter 7. NodePort, as an interview answer

> **NodePort is a Service type that opens the same port on every node in the cluster, in the range 30000–32767 by default. Traffic sent to any node's IP on that port is forwarded by kube-proxy to the Service's pods, even when the pod runs on another node.**

```
ClusterIP     → reachable only inside the cluster              (the default)
NodePort      → ClusterIP + a port on every node               (outside: nodeIP:port)
LoadBalancer  → NodePort + a cloud load balancer in front      (outside: the LB address)
```

- Used for: quick outside access or tests, and load balancers in instance mode.
- Downsides: odd high ports, node IPs are exposed, clients break when node IPs change, only about 2,700 ports in the range.
- In production there is usually a LoadBalancer Service or an Ingress in front instead.

## Chapter 8. The other Service: `ingress-nginx-controller-admission`

It is a **checker for Ingress files**, used when an Ingress is created or changed, never for website traffic.

```
kubectl apply -f ingress.yaml   (or Argo CD applies it)
   ▼
API server: "before I save this Ingress, ask nginx whether it is valid"
   ▼
ingress-nginx-controller-admission :443 → the nginx controller checks it
   ├─ valid   → the Ingress is saved
   └─ invalid → kubectl shows an error, nothing is saved
```

One nginx serves **every** Ingress in the cluster, so one broken Ingress could break routing for every app. This checker stops a bad one before it is saved. The general name is a **validating admission webhook**. It is a ClusterIP because only the API server calls it, and it uses 443 because the API server only calls webhooks over HTTPS. Turning off the NLB's 443 (chapter 4) does not affect it.

## Chapter 9. One full request, end to end

Our cluster with 2 nginx, 2 backend and 2 frontend pods on two nodes:

```
Node A  10.0.1.10                    Node B  10.0.2.20
 ├─ nginx-1     10.0.2.81             ├─ nginx-2     10.0.24.193
 ├─ backend-1   10.0.1.55             ├─ backend-2   10.0.2.66
 └─ frontend-1  10.0.1.70             └─ frontend-2  10.0.2.90
```

A browser calls `http://<NLB address>/api/todos`:

```
1. Internet → NLB
2. The NLB picks ONE healthy target from its target group: nginx-2 (10.0.24.193:80)
   → the AWS network delivers it to Node B → kernel route → nginx-2
3. nginx-2 reads the Ingress rules: "/api" → backend-service:8081
4. nginx-2 picks ONE backend pod itself: backend-1 (10.0.1.55:8081), on Node A
   (nginx keeps its own list of backend pod IPs, taken from the Service)
5. nginx-2 sends to 10.0.1.55
   → Node B's kernel: "not on this node" → out through the network card
   → the AWS network: "10.0.1.55 is on Node A" → delivers it
   → Node A's kernel route → backend-1
6. backend-1 answers → the reply goes back the same way → NLB → browser
```

A request to `/` is the same, except nginx picks a **frontend** pod on port 8080.

There are **two load-balancing steps**: the NLB chooses the nginx pod, and nginx chooses the app pod. nginx sends **straight to the pod IP** and uses `backend-service` only to know the list of pods.

## Chapter 10. Who hands the packet to the pod? The CNI

A packet for `10.0.2.81` arrives at Node B's network card. Who connects the card to the pod? **The Linux kernel on the node**, using things the CNI prepared when the pod started.

**When the pod starts** (once), the VPC CNI:

```
1. takes a free address (10.0.2.81) from the block on the node's network card
2. creates a VIRTUAL CABLE (a "veth pair"):
      one end inside the pod  → eth0, address 10.0.2.81
      other end on the node   → for example eni3f2a1b
3. adds a ROUTE to the node's routing table:
      "anything for 10.0.2.81 → send it down cable eni3f2a1b"
```

**When a packet arrives** (every time):

```
NLB → 10.0.2.81
  ▼
the AWS network: "10.0.2.81 is attached to Node B's network card" → delivers it there
  ▼
Node B's kernel looks up its routing table:  10.0.2.81 → cable eni3f2a1b
  ▼
the packet goes down the cable → comes out at eth0 inside the pod → nginx on port 80
```

| Who | Job | When |
|---|---|---|
| the AWS VPC | brings the packet to the right **node** | every packet |
| the VPC CNI (`aws-node` pod) | creates the cable and the route | once, when the pod starts |
| the Linux kernel | follows the route, pushes the packet down the cable | every packet |

On a node, `ip route` shows a line like `10.0.2.81 dev eni3f2a1b scope link`.

The building picture: the node is a building, the network card is the main entrance, the pod is a flat. The CNI built a private corridor (the cable) and put up a sign (the route). The doorman (the kernel) reads the sign and points visitors down the corridor.

## Chapter 11. What a CNI is

**CNI = Container Network Interface.** It is a **standard** for how Kubernetes asks a network plugin to connect a pod. There are many plugins that follow it.

```
pod created  → kubelet calls the CNI plugin: "ADD this pod"
               → the plugin gives it an IP, a cable and a route
pod deleted  → kubelet: "DEL this pod" → the plugin removes them
```

- **Every cluster needs exactly one.** Without it, pods have no network and never start.
- Common ones: **AWS VPC CNI** (the EKS default, ours, add-on `vpc-cni`), **Calico**, **Cilium**, **Flannel**.
- **Every** CNI writes cables and routes into each node's kernel. That part is the same for all of them. They differ in **where pod addresses come from** and **how a packet travels between two nodes**.

## Chapter 12. Overlay CNIs (Flannel as the example)

### Each node gets its own slice of addresses

When the cluster is set up, it gets one big **pod range**, for example `192.168.0.0/16`. The CNI splits it into one slice per node:

```
cluster pod range 192.168.0.0/16
   ├─ Node A gets 192.168.1.0/24
   ├─ Node B gets 192.168.2.0/24
   └─ Node C gets 192.168.3.0/24
```

Why slices:

1. **No clashes and no asking.** Each node hands out addresses only from its own slice, so two pods never get the same address and a node never has to ask anyone first.
2. **Easy delivery.** The address tells you the node: `192.168.2.x` means Node B. Like a postal code, where the first part names the town.

These addresses exist **only inside the cluster**. The AWS VPC has never heard of them.

### The tables in each node's kernel

```
Node A's routing table (Flannel):
  192.168.1.5     → cable veth-aaa      my pod (same idea as the VPC CNI)
  192.168.1.6     → cable veth-bbb      my pod
  192.168.2.0/24  → tunnel device       Node B's pods: through the tunnel
  192.168.3.0/24  → tunnel device       Node C's pods: through the tunnel
```

A Flannel agent on every node also keeps a list of which slice lives on which node (`192.168.2.0/24 lives on Node B 10.0.2.20`). It learns this from the Kubernetes API.

### Pod to pod across nodes: an envelope in an envelope

Pod `192.168.1.5` on Node A sends to pod `192.168.2.7` on Node B:

```
1. the pod sends:  [ from 192.168.1.5  to 192.168.2.7 | data ]
2. Node A's kernel: "192.168.2.x → tunnel device"
3. the tunnel device looks up "192.168.2.x lives on Node B 10.0.2.20" and WRAPS the packet:
   [ from 10.0.1.10  to 10.0.2.20 | [ from 192.168.1.5 to 192.168.2.7 | data ] ]
      outer envelope: node addresses       inner envelope: unchanged
4. the AWS network reads only the outer envelope → delivers it to Node B
5. Node B's tunnel device UNWRAPS it → "to 192.168.2.7"
6. Node B's kernel: 192.168.2.7 → cable → the pod
```

The wrapping is needed because the AWS network would **drop** a packet addressed to `192.168.2.7`: it has no route for it, and EC2 also drops packets whose addresses do not belong to the instance. The common name for this wrapping is **VXLAN**. The pod network laid on top of the real network is the **overlay**.

Two pods on the **same** node need no tunnel: route, cable, done.

### A full internet request with an overlay CNI

```
browser → NLB → Node A 10.0.1.10 :30711          instance mode only (node IP + NodePort)
        → kube-proxy picks an nginx pod: 192.168.2.4 on Node B
        → wrap → AWS → Node B → unwrap → nginx pod
        → nginx picks backend pod 192.168.1.9 on Node A
        → wrap → AWS → Node A → unwrap → backend pod
```

The NLB can only use **instance mode**, because it cannot reach the cluster-only pod addresses.

## Chapter 13. VPC CNI vs overlay: the summary

```
                VPC CNI (ours)                        Overlay CNI (Flannel, Calico/Cilium in tunnel mode)
pod IPs         real VPC addresses (10.0.x.x)         a cluster-only range (192.168.x.x)
who gives them  taken from the node's network card    from the node's own slice
same node       route → cable                         route → cable                    (the same)
other node      the AWS network delivers directly     wrap → AWS delivers node to node → unwrap
NLB → pod       IP mode or instance mode              instance mode only
limit           pods per node limited by card slots   no slot limit, small extra work per packet
                (see the prefix delegation note)
```

**If we did not use the VPC CNI**, IP mode would be impossible and the NLB would have to use instance mode (NodePort). Everything else would still work, with the wrap and unwrap step on every jump between nodes.

The pods-per-node limit of the VPC CNI, and how prefix delegation raises it, is explained in [VPC CNI and prefix delegation](vpc-cni-prefix-delegation.md).

---

## Interview questions

**What is the difference between a listener, a target group and a target?**
A listener is a port the load balancer accepts traffic on. It forwards to a target group, which holds the current list of targets (instances or IPs), the port to use on them and a health check. Targets are the actual destinations. Only healthy targets get traffic.

**Why can't an NLB send traffic to a ClusterIP?**
A ClusterIP is a virtual address that only exists inside the cluster, through kube-proxy rules on each node. The NLB is outside the cluster, so it uses either the NodePort on the nodes (instance mode) or the pod IPs directly (IP mode).

**Instance mode vs IP mode?**
Instance mode targets every node on the NodePort, and kube-proxy forwards to a pod, possibly on another node. IP mode targets the pod IPs directly, which needs pods with real VPC addresses, as the VPC CNI gives them.

**What is NodePort?**
See chapter 7.

**What is a CNI?**
The Container Network Interface: the standard plugin interface that gives every pod an IP address and connects it to the network. Every cluster needs one. EKS uses the AWS VPC CNI by default.

**How is the VPC CNI different from Flannel or Calico?**
The VPC CNI gives pods real VPC addresses, so the AWS network routes between pods directly. Overlay CNIs give pods a cluster-only range, one slice per node, and wrap packets between nodes in a tunnel (VXLAN).

**What does a validating admission webhook do?**
The API server calls it before saving an object. It can reject invalid objects. ingress-nginx uses one to reject broken Ingress files.

## Check it on the real cluster

```bash
# the nginx Service: EXTERNAL-IP is the NLB, PORT(S) shows the NodePorts
kubectl get svc -n ingress-nginx

# the nginx pods and their IPs (the NLB's targets)
kubectl get pods -n ingress-nginx -o wide

# the app pods and the node each one runs on
kubectl get pods -n app -o wide

# the pod IPs behind a Service
kubectl get endpointslices -n app
```

In the AWS console: **EC2 → Load Balancers → the `k8s-ingressn-...` NLB → Resource map**.

## Sources

- [Route TCP and UDP traffic with Network Load Balancers (Amazon EKS)](https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html)
- [AWS Load Balancer Controller: Service annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/annotations/)
- [Service types (Kubernetes docs)](https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types)
- [Network plugins (Kubernetes docs)](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
- [Amazon VPC CNI (amazon-vpc-cni-k8s)](https://github.com/aws/amazon-vpc-cni-k8s)
- [Flannel](https://github.com/flannel-io/flannel)
- [ingress-nginx Helm chart values](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx)
