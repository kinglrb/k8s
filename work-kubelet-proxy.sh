ansible k8sHA -m shell -a "mkdir -p /opt/k8s/"
ansible k8sHA -m shell -a "mkdir -p /opt/kubernetes/{bin,cfg,ssl,logs}"
ansible k8sHA -m copy -a "src=/opt/src/kubernetes/server/bin/kubelet dest=/opt/kubernetes/bin"
ansible k8sHA -m copy -a "src=/opt/src/kubernetes/server/bin/kube-proxy dest=/opt/kubernetes/bin"
ansible k8sHA -m copy -a "src=/opt/ansible/appFileMake/k8s/ca_tls dest=/opt/kubernetes/ssl"
ansible k8sHA -m copy -a "src=/opt/ansible/appFileMake/k8s/ca_tls dest=/opt/k8s/"
ansible k8sHA -m copy -a "src=/opt/ansible/appFileMake/docker dest=/etc/"

ansible k8sHA -m script -a "/opt/ansible/script/k8s/work-kubelet-proxy.sh"

# ansible 192.168.1.35 -m file -a "path=/opt/king state=directory"
# -----------------------------部署Worker Node
# Master Node，同时作为Worker Node
# 在所有worker node创建工作目录：
# mkdir -p /opt/kubernetes/{bin,cfg,ssl,logs} 
# 拷贝二进制文件
# cd /opt/src/kubernetes/server/bin
# cp kubelet kube-proxy /opt/kubernetes/bin   # 本地拷贝

cat >>/etc/hosts<<EOF
192.168.1.15 registry.king.cn
EOF
# -----------------------------------部署kubelet
hostName=`hostname`
echo $hostName
# 1. 创建配置文件
cat > /opt/kubernetes/cfg/kubelet.conf << EOF
KUBELET_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--hostname-override=$hostName \\
--network-plugin=cni \\
--kubeconfig=/opt/kubernetes/cfg/kubelet.kubeconfig \\
--bootstrap-kubeconfig=/opt/kubernetes/cfg/bootstrap.kubeconfig \\
--config=/opt/kubernetes/cfg/kubelet-config.yml \\
--cert-dir=/opt/kubernetes/ssl \\
--pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.4.1"
--container-runtime-endpoint=unix:///run/containerd/containerd.sock
EOF
# •	--hostname-override：			显示名称，集群中唯一                       #hostName
# •	--network-plugin：				启用CNI
# •	--kubeconfig：					空路径，会自动生成，后面用于连接apiserver
# •	--bootstrap-kubeconfig：		首次启动向apiserver申请证书
# •	--config：						配置参数文件
# •	--cert-dir：					kubelet证书生成目录
# •	--pod-infra-container-image：	管理Pod网络容器的镜像                     #lizhenliang/pause-amd64:3.0

# 2. 配置参数文件
cat > /opt/kubernetes/cfg/kubelet-config.yml << EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: 0.0.0.0
port: 10250
readOnlyPort: 10255
cgroupDriver: cgroupfs
clusterDNS:
- 10.0.0.2
clusterDomain: cluster.local 
failSwapOn: false
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: /opt/kubernetes/ssl/ca.pem 
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
evictionHard:
  imagefs.available: 15%
  memory.available: 100Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
maxOpenFiles: 1000000
maxPods: 110
EOF

sed -i s/cgroupDriver: systemd/cgroupDriver: cgroupfs/ /opt/kubernetes/cfg/kubelet-config.yml

# 3. 生成kubelet初次加入(访问)集群，需要的引导文件kubeconfig？
KUBE_CONFIG="/opt/kubernetes/cfg/bootstrap.kubeconfig"
KUBE_APISERVER="https://192.168.1.39:16443" 	# apiserver IP:PORT
#TOKEN 一机一个？
TOKEN="560efbef635ef073d52ad7214df9c29b" 		# 与token.csv保持一致

# 生成kubelet初次加入(访问:获取证书)集群，需要的引导文件kubeconfig？
#整个集群，应只需生成一次？
	# 但/opt/kubernetes/cfg/kubelet.conf引用的kubelet.kubeconfig，为本地文件
kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-credentials "kubelet-bootstrap" \
  --token=${TOKEN} \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-context default \
  --cluster=kubernetes \
  --user="kubelet-bootstrap" \
  --kubeconfig=${KUBE_CONFIG}
kubectl config use-context default --kubeconfig=${KUBE_CONFIG}

# 4. systemd管理kubelet
cat > /usr/lib/systemd/system/kubelet.service << EOF
[Unit]
Description=Kubernetes Kubelet
After=docker.service

[Service]
EnvironmentFile=/opt/kubernetes/cfg/kubelet.conf
ExecStart=/opt/kubernetes/bin/kubelet \$KUBELET_OPTS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# -------------------------------------------部署kube-proxy
# 1. 创建配置文件
cat > /opt/kubernetes/cfg/kube-proxy.conf << EOF
KUBE_PROXY_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--config=/opt/kubernetes/cfg/kube-proxy-config.yml"
EOF
# 2. 配置参数文件
cat > /opt/kubernetes/cfg/kube-proxy-config.yml << EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: 0.0.0.0
metricsBindAddress: 0.0.0.0:10249
clientConnection:
  kubeconfig: /opt/kubernetes/cfg/kube-proxy.kubeconfig
hostnameOverride: $hostName
clusterCIDR: 10.244.0.0/16
EOF
##hostName

# 3. 生成kube-proxy.kubeconfig文件
#整个集群，只需生成一次？文件通用。节点复制即可
KUBE_CONFIG="/opt/kubernetes/cfg/kube-proxy.kubeconfig"
KUBE_APISERVER="https://192.168.1.39:16443"

kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=${KUBE_CONFIG}
#kube-proxy.pem
kubectl config set-credentials kube-proxy \
  --client-certificate=/opt/k8s/ca_tls/k8s/kube-proxy.pem \
  --client-key=/opt/k8s/ca_tls/k8s/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=${KUBE_CONFIG}
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=${KUBE_CONFIG}
kubectl config use-context default --kubeconfig=${KUBE_CONFIG}

# 4. systemd管理kube-proxy
cat > /usr/lib/systemd/system/kube-proxy.service << EOF
[Unit]
Description=Kubernetes Proxy
After=network.target

[Service]
EnvironmentFile=/opt/kubernetes/cfg/kube-proxy.conf
ExecStart=/opt/kubernetes/bin/kube-proxy \$KUBE_PROXY_OPTS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# ----------------------------启动并设置开机启动
systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet
#kube-proxy
if [ $?==0 ]
then
	echo "kubelet已启动,开始启动kube-proxy"
	systemctl daemon-reload
	systemctl start kube-proxy
	systemctl enable kube-proxy
fi

# 从tail -200 /var/log/messages，
	# 会出现连接192.168.1.139:6443情况，排查没发现配置如此情况
		# 替换全部配置文件中，serverIP端口，重启全部服务
			# sed -i 's#192.168.1.35:6443#192.168.1.39:16443#' /opt/kubernetes/cfg/*
			
# 批准kubelet证书申请并加入集群
	#是否只在master做一次即可???
		# 普通node 怎么执行kubectl.
			在master可查到全部，一个master批准全部node
# 查看kubelet证书请求
# kubectl get csr
	# # NAME                                                   AGE    SIGNERNAME                                    REQUESTOR           CONDITION
	# # node-csr-uCEGPOIiDdlLODKts8J658HrFq9CZ--K6M4G7bjhk8A   6m3s   kubernetes.io/kube-apiserver-client-kubelet   kubelet-bootstrap   Pending

for id in `kubectl get csr|awk '{if (NR>1){print $1}}'`
do
    echo $id
	if [ -n $id ]
	then
		# 批准申请
		kubectl certificate approve $id
		echo "$id已批准，next"
	else
		echo "没有证书申请，请核实"
	fi
done
# 查看节点
# kubectl get node
	# NAME         STATUS     ROLES    AGE   VERSION
	# k8s-master1   NotReady   <none>   7s    v1.18.3
# 注：网络插件没部署，节点没有准备就绪 NotReady


# kubelet FLAG: 
# --add-dir-header="false"
# --address="0.0.0.0"
# --allowed-unsafe-sysctls="[]"
# --alsologtostderr="false"
# --anonymous-auth="true"
# --application-metrics-count-limit="100"
# --authentication-token-webhook="false"
# --authentication-token-webhook-cache-ttl="2m0s"
# --authorization-mode="AlwaysAllow"
# --authorization-webhook-cache-authorized-ttl="5m0s"
# --authorization-webhook-cache-unauthorized-ttl="30s"
# --azure-container-registry-config=""
# --boot-id-file="/proc/sys/kernel/random/boot_id"
# --bootstrap-kubeconfig="/opt/kubernetes/cfg/bootstrap.kubeconfig"
# --cert-dir="/opt/kubernetes/ssl"
# --cgroup-driver="cgroupfs"
# --cgroup-root=""
# --cgroups-per-qos="true"
# --client-ca-file=""
# --cloud-config=""
# --cloud-provider=""
# --cluster-dns="[]"
# --cluster-domain=""
# --cni-bin-dir="/opt/cni/bin"
# --cni-cache-dir="/var/lib/cni/cache"
# --cni-conf-dir="/etc/cni/net.d"
# --config="/opt/kubernetes/cfg/kubelet-config.yml"
# --container-hints="/etc/cadvisor/container_hints.json"
# --container-log-max-files="5"
# --container-log-max-size="10Mi"
# --container-runtime="docker"
# --container-runtime-endpoint="unix:///var/run/dockershim.sock"
# --containerd="/run/containerd/containerd.sock"
# --containerd-namespace="k8s.io"
# --contention-profiling="false"
# --cpu-cfs-quota="true"
# --cpu-cfs-quota-period="100ms"
# --cpu-manager-policy="none"
# --cpu-manager-policy-options=""
# --cpu-manager-reconcile-period="10s"
# --docker="unix:///var/run/docker.sock"
# --docker-endpoint="unix:///var/run/docker.sock"
# --docker-env-metadata-whitelist=""
# --docker-only="false"
# --docker-root="/var/lib/docker"
# --docker-tls="false"
# --docker-tls-ca="ca.pem"
# --docker-tls-cert="cert.pem"
# --docker-tls-key="key.pem"
# --dynamic-config-dir=""
# --enable-controller-attach-detach="true"
# --enable-debugging-handlers="true"
# --enable-load-reader="false"
# --enable-server="true"
# --enforce-node-allocatable="[pods]"
# --event-burst="10"
# --event-qps="5"
# --event-storage-age-limit="default=0"
# --event-storage-event-limit="default=0"
# --eviction-hard="imagefs.available<15%,memory.available<100Mi,nodefs.available<10%,nodefs.inodesFree<5%"
# --eviction-max-pod-grace-period="0"
# --eviction-minimum-reclaim=""
# --eviction-pressure-transition-period="5m0s"
# --eviction-soft=""
# --eviction-soft-grace-period=""
# --exit-on-lock-contention="false"
# --experimental-allocatable-ignore-eviction="false"
# --experimental-bootstrap-kubeconfig="/opt/kubernetes/cfg/bootstrap.kubeconfig"
# --experimental-check-node-capabilities-before-mount="false"
# --experimental-dockershim-root-directory="/var/lib/dockershim"
# --experimental-kernel-memcg-notification="false"
# --experimental-logging-sanitization="false"
# --experimental-mounter-path=""
# --fail-swap-on="true"
# --feature-gates=""
# --file-check-frequency="20s"
# --global-housekeeping-interval="1m0s"
# --hairpin-mode="promiscuous-bridge"
# --healthz-bind-address="127.0.0.1"
# --healthz-port="10248"
# --help="false"
# --hostname-override="k8shamasa"
# --housekeeping-interval="10s"
# --http-check-frequency="20s"
# --image-credential-provider-bin-dir=""
# --image-credential-provider-config=""
# --image-gc-high-threshold="85"
# --image-gc-low-threshold="80"
# --image-pull-progress-deadline="1m0s"
# --image-service-endpoint=""
# --iptables-drop-bit="15"
# --iptables-masquerade-bit="14"
# --keep-terminated-pod-volumes="false"
# --kernel-memcg-notification="false"
# --kube-api-burst="10"
# --kube-api-content-type="application/vnd.kubernetes.protobuf"
# --kube-api-qps="5"
# --kube-reserved=""
# --kube-reserved-cgroup=""
# --kubeconfig="/opt/kubernetes/cfg/kubelet.kubeconfig"
# --kubelet-cgroups=""
# --lock-file=""
# --log-backtrace-at=":0"
# --log-cadvisor-usage="false"
# --log-dir="/opt/kubernetes/logs"
# --log-file=""
# --log-file-max-size="1800"
# --log-flush-frequency="5s"
# --logging-format="text"
# --logtostderr="false"
# --machine-id-file="/etc/machine-id,/var/lib/dbus/machine-id"
# --make-iptables-util-chains="true"
# --manifest-url=""
# --manifest-url-header=""
# --master-service-namespace="default"
# --max-open-files="1000000"
# --max-pods="110"
# --maximum-dead-containers="-1"
# --maximum-dead-containers-per-container="1"
# --memory-manager-policy="None"
# --minimum-container-ttl-duration="0s"
# --minimum-image-ttl-duration="2m0s"
# --network-plugin="cni"
# --network-plugin-mtu="0"
# --node-ip=""
# --node-labels=""
# --node-status-max-images="50"
# --node-status-update-frequency="10s"
# --non-masquerade-cidr="10.0.0.0/8"
# --one-output="false"
# --oom-score-adj="-999"
# --pod-cidr=""
# --pod-infra-container-image="registry.king.cn:5000/pause:3.4.1"
# --pod-manifest-path=""
# --pod-max-pids="-1"
# --pods-per-core="0"
# --port="10250"
# --protect-kernel-defaults="false"
# --provider-id=""
# --qos-reserved=""
# --read-only-port="10255"
# --really-crash-for-testing="false"
# --register-node="true"
# --register-schedulable="true"
# --register-with-taints=""
# --registry-burst="10"
# --registry-qps="5"
# --reserved-cpus=""
# --reserved-memory=""
# --resolv-conf="/etc/resolv.conf"
# --root-dir="/var/lib/kubelet"
# --rotate-certificates="false"
# --rotate-server-certificates="false"
# --runonce="false"
# --runtime-cgroups=""
# --runtime-request-timeout="2m0s"
# --seccomp-default="false"
# --seccomp-profile-root="/var/lib/kubelet/seccomp"
# --serialize-image-pulls="true"
# --skip-headers="false"
# --skip-log-headers="false"
# --stderrthreshold="2"
# --storage-driver-buffer-duration="1m0s"
# --storage-driver-db="cadvisor"
# --storage-driver-host="localhost:8086"
# --storage-driver-password="root"
# --storage-driver-secure="false"
# --storage-driver-table="stats"
# --storage-driver-user="root"
# --streaming-connection-idle-timeout="4h0m0s"
# --sync-frequency="1m0s"
# --system-cgroups=""
# --system-reserved=""
# --system-reserved-cgroup=""
# --tls-cert-file=""
# --tls-cipher-suites="[]"
# --tls-min-version=""
# --tls-private-key-file=""
# --topology-manager-policy="none"
# --topology-manager-scope="container"
# --v="2"
# --version="false"
# --vmodule=""
# --volume-plugin-dir="/usr/libexec/kubernetes/kubelet-plugins/volume/exec/"
# --volume-stats-agg-period="1m0s"