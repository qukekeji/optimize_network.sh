#!/bin/bash

# 检查是否安装了 ethtool
if ! command -v ethtool &> /dev/null; then
  echo "ethtool 未安装。正在安装 ethtool..."
  if [ -f /etc/debian_version ]; then
    sudo apt update
    sudo apt install -y ethtool
  elif [ -f /etc/redhat-release ]; then
    sudo yum install -y ethtool
  else
    echo "未知的操作系统，请手动安装 ethtool。"
    exit 1
  fi
else
  echo "ethtool 已安装。"
fi

# 获取网络接口名称
NET_INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')

# 检查网络接口是否存在
if [ -z "$NET_INTERFACE" ]; then
  echo "没有找到默认的网络接口。"
  exit 1
fi

# 获取最大队列大小
MAX_RX=$(ethtool -g "$NET_INTERFACE" | grep 'RX:' | awk 'NR==1{print $2}')
MAX_TX=$(ethtool -g "$NET_INTERFACE" | grep 'TX:' | awk 'NR==1{print $2}')

if [ -z "$MAX_RX" ] || [ -z "$MAX_TX" ]; then
  echo "无法获取最大队列大小。请确保网络接口支持队列大小调整。"
  exit 1
fi

# 调整队列大小到最大值
sudo ethtool -G "$NET_INTERFACE" rx "$MAX_RX" tx "$MAX_TX"

# 清空 /etc/sysctl.conf 文件中的参数
sudo truncate -s 0 /etc/sysctl.conf

# 设置 BBR 拥塞控制和其他网络参数
sudo tee -a /etc/sysctl.conf <<EOF

# 启用 BBR 拥塞控制
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# 调整 TCP 缓冲区
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# 网络稳定性和性能优化
vm.swappiness=10
fs.file-max=2097152
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=60
net.ipv4.ip_local_port_range="1024 65535"
net.ipv4.tcp_max_syn_backlog=262144
net.ipv4.tcp_max_tw_buckets=262144
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.core.somaxconn=262144
net.core.netdev_max_backlog=262144
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_rmem="8192 262144 536870912"
net.ipv4.tcp_wmem="4096 16384 536870912"
net.core.optmem_max=25165824

# 调整网络设备队列
net.core.netdev_max_backlog=$MAX_RX
EOF

# 应用 sysctl 配置
sudo sysctl -p

# 验证配置
echo "验证配置:"
sysctl net.ipv4.tcp_congestion_control
ethtool -g "$NET_INTERFACE"

echo "网络优化完成。"
