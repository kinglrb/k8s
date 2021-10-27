#!/bin/bash
systemctl stop firewalld 
if [ $?==0 ]
then
	systemctl disable firewalld
else
    echo "防火墙未关闭，退出"
	exit 0
fi
 
# 关闭selinux 
sed -i 's/enforcing/disabled/' /etc/selinux/config  # 永久
# setenforce 0  # 临时 
 
# 关闭swap 
# swapoff -a  # 临时 
sed -ri 's/.*swap.*/#&/' /etc/fstab    # 永久
 
# 根据规划设置主机名
hostIp=`ip addr|grep 192.168.1|awk -F " " '{ print $2 }'|awk -F "/" '{ print $1 }'`
echo $hostIp
case $hostIp in
    192.168.1.35)  hostnamectl set-hostname k8sHAmasA
    ;;
    192.168.1.36)  hostnamectl set-hostname k8sHAmasB
    ;;
    192.168.1.37)  hostnamectl set-hostname k8sHAnode1
    ;;
    192.168.1.38)  hostnamectl set-hostname k8sHAnode2
    ;;
    *)  echo '  未规划参数，请核查   '
    ;;
esac

# 在master添加hosts 
cat >> /etc/hosts << EOF
192.168.1.35 k8sHAmasA
192.168.1.36 k8sHAmasB
192.168.1.37 k8sHAnode1
192.168.1.38 k8sHAnode2
EOF

# 将桥接的IPv4流量传递到iptables的链 
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system  # 生效 
 
# 时间同步 
yum install ntpdate -y
if [ $?==0 ]
then
	ntpdate time.windows.com
fi