# Kubernetes组件端口
# 组件	                端口	        参数	默认值	    协议	必须开启	说明
kube-apiserver	        安全端口	    --secure-port	    6443	HTTPS	    是	-
kube-apiserver	        非安全端口	    --insecure-port	    8080	HTTP	    否，0表示关闭	deprecated
kubelet	                健康检测端口    --healthz-port	    10248	HTTP	    否，0表示关闭	-
kube-proxy	            指标端口	    --metrics-port	    10249	HTTP	    否，0表示关闭	-
kubelet	                安全端口	    --port	            10250	HTTPS	    是	认证与授权
kube-scheduler	        非安全端口	    --insecure-port	    10251	HTTP	    否，0表示关闭	deprecated
kube-controller-manager	非安全端口	    --insecure-port	    10252	HTTP	    否，0表示关闭	deprecated
kubelet	                非安全端口	    --read-only-port	10255	HTTP	    否，0表示关闭	-
kube-proxy	            健康检测端口    --healthz-port	    10256	HTTP	    否，0表示关闭	-
kube-controller-manager	安全端口	    --secure-port	    10257	HTTPS	    否，0表示关闭	认证与授权
kube-scheduler	        安全端口	    --secure-port	    10259	HTTPS	    否，0表示关闭	认证与授权