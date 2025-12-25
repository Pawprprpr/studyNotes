┌─────────────────────────────────────────────────────────────────┌─────────────────────────────────────────────────────────────┐
│                         Control Plane (Master Node)             │                         Worker Nodes                        │
│                                                                 │                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   API       │    │  Scheduler  │    │ Controller  │        │  │    kubelet  │    │  kube-proxy │    │  Container  │     │
│  │   Server    │◄───│             │◄───│  Manager    │        │  │             │    │             │    │  Runtime    │     │
│  │             │    │             │    │             │        │  │             │    │             │    │ (Docker/    │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘        │  └──────┬──────┘    └──────┬──────┘    │  containerd)│     │
│         │                  │                  │               │         │                  │           └──────┬───────┘     │
│         └──────────────────┼──────────────────┘               │         └──────────────────┼─────────────────┘             │
│                            │                                  │                            │                               │
│  ┌────────────────────────────────────────────┐               │  ┌─────────────────────────────────────────────────────┐   │
│  │             etcd Cluster                   │               │  │                  Pods                              │   │
│  │  ┌─────┐   ┌─────┐   ┌─────┐               │               │  │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐      │   │
│  │  │Node │   │Pod  │   │Config│               │               │  │  │App  │  │Side-│  │App  │  │App  │  │Init │      │   │
│  │  │Info │   │Info │   │Maps  │               │               │  │  │Cont │  │car  │  │Cont │  │Cont │  │Cont │      │   │
│  │  └─────┘   └─────┘   └─────┘               │               │  │  └─────┘  └─────┘  └─────┘  └─────┘  └─────┘      │   │
│  └────────────────────────────────────────────┘               │  └─────────────────────────────────────────────────────┘   │
│                                                                 │                                                             │
└─────────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────┘

                                ▲                                                                 ▲
                                │                                                                 │
                                │                                                                 │
                          kubectl / API                                                    Workloads
                           Commands                                                      (Deployments, etc.)


cubectl命令大全
https://kubernetes.io/zh-cn/docs/reference/kubectl/
常用如下
使用 kubectl create 命令创建管理 Pod 的 Deployment。该 Pod 根据提供的 Docker 镜像运行容器。

# 运行包含 Web 服务器的测试容器镜像
kubectl create deployment hello-node --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- /agnhost netexec --http-port=8080
查看 Deployment：

kubectl get deployments
输出结果类似于这样：

NAME         READY   UP-TO-DATE   AVAILABLE   AGE
hello-node   1/1     1            1           1m
（该 Pod 可能需要一些时间才能变得可用。如果你在输出结果中看到 “0/1”，请在几秒钟后重试。）

查看 Pod：

kubectl get pods
输出结果类似于这样：

NAME                          READY     STATUS    RESTARTS   AGE
hello-node-5f76cf6ccf-br9b5   1/1       Running   0          1m
查看集群事件：

kubectl get events
查看 kubectl 配置：

kubectl config view
查看 Pod 中容器的应用程序日志（将 Pod 名称替换为你用 kubectl get pods 命令获得的名称）。

说明：
将 kubectl logs 命令中的 hello-node-5f76cf6ccf-br9b5 替换为 kubectl get pods 命令输出中的 Pod 名称。

kubectl logs hello-node-5f76cf6ccf-br9b5
输出类似于：

I0911 09:19:26.677397       1 log.go:195] Started HTTP server on port 8080
I0911 09:19:26.677586       1 log.go:195] Started UDP server on port  8081
