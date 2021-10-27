#!/bin/bash
# -----------------自签证书颁发机构（CA）
mkdir -p /opt/ansible/appFileMake/k8s/ca_tls/{etcd,k8s}
cd /opt/ansible/appFileMake/k8s/ca_tls/k8s
# 自签CA：
cat > ca-config.json << EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
         "expiry": "87600h",
         "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ]
      }
    }
  }
}
EOF

cat > ca-csr.json << EOF
{
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "HangZhou",
            "ST": "ZheJiang",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
# 生成ca.pem和ca-key.pem文件
cfssl gencert -initca ca-csr.json | cfssljson -bare ca -

# --------------使用自签CA签发kube-apiserver HTTPS证书
# 创建证书申请文件：
if [ $?==0 ]
then
cat > server-csr.json << EOF
{
    "CN": "kubernetes",
    "hosts": [
      "10.0.0.1",
      "127.0.0.1",
      "192.168.1.12",
      "192.168.1.35",
      "192.168.1.37",
      "192.168.1.38",
      "192.168.1.36",
      "192.168.1.39",
      "kubernetes",
      "kubernetes.default",
      "kubernetes.default.svc",
      "kubernetes.default.svc.cluster",
      "kubernetes.default.svc.cluster.local"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "HangZhou",
            "ST": "ZheJiang",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
fi

# 注：hosts字段中IP，为所有etcd节点IP，可预留扩容IP(多填)
# host中IP为需连接apiserver的IP，应包括master集群的所有IP，和负载均衡LB的所有IP和VIP
# “CN”：Common Name，etcd 从证书中提取该字段作为请求的用户名 (User Name)；浏览器使用该字段验证网站是否合法； 
# “O”：Organization，etcd 从证书中提取该字段作为请求用户所属的组 (Group)；
# 根证书文件: ca.pem
# 根证书私钥: ca-key.pem
# 根证书申请文件: ca.csr

# 生成证书：生成server.pem和server-key.pem文件
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes server-csr.json | cfssljson -bare server
if [ $?==0 ]
then
	echo "证书已成功创建，可进行下一步"
else
	echo "证书创建失败，请检查"
fi