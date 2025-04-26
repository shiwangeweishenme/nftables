#!/bin/bash

echo "=============================="
echo "🔥 nftables 多端口转发脚本 🔥"
echo "支持 IPv4 / IPv6，批量添加规则"
echo "=============================="

# 清空变量
IPV4_RULES=""
IPV6_RULES=""
ENABLE_IPV6="no"

# === 开启内核转发设置 ===
echo "👉 开启内核转发配置..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# === 输入多个 IPv4 转发规则 ===
echo "🔧 开始添加 IPv4 转发规则："

while true; do
  read -p "请输入本地监听端口（IPv4）: " LOCAL_PORT
  read -p "请输入目标服务器 IPv4 地址: " REMOTE_IPV4
  read -p "请输入目标服务器 IPv4 端口: " REMOTE_PORT

  IPV4_RULES+="
        tcp dport $LOCAL_PORT dnat to $REMOTE_IPV4:$REMOTE_PORT
        udp dport $LOCAL_PORT dnat to $REMOTE_IPV4:$REMOTE_PORT
  "

  read -p "是否继续添加 IPv4 转发规则？(yes/no): " CONTINUE_IPV4
  [[ "$CONTINUE_IPV4" != "yes" ]] && break
done

# === 是否启用 IPv6 ===
read -p "是否需要添加 IPv6 转发规则？(yes/no): " ENABLE_IPV6

if [ "$ENABLE_IPV6" = "yes" ]; then
  echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
  echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
  sysctl -p

  while true; do
    read -p "请输入本地监听端口（IPv6）: " LOCAL_PORT6
    read -p "请输入目标服务器 IPv6 地址（格式如 [2001:db8::1]）: " REMOTE_IPV6
    read -p "请输入目标服务器 IPv6 端口: " REMOTE_PORT6

    IPV6_RULES+="
        tcp dport $LOCAL_PORT6 dnat to $REMOTE_IPV6:$REMOTE_PORT6
        udp dport $LOCAL_PORT6 dnat to $REMOTE_IPV6:$REMOTE_PORT6
    "

    POSTROUTING_IPV6+="
        ip6 daddr $REMOTE_IPV6 masquerade
    "

    read -p "是否继续添加 IPv6 转发规则？(yes/no): " CONTINUE_IPV6
    [[ "$CONTINUE_IPV6" != "yes" ]] && break
  done
fi

# === 启用 nftables 服务 ===
echo "👉 启动 nftables 服务..."
systemctl enable nftables
systemctl start nftables

# === 写入配置文件 ===
NFT_CONFIG="/etc/nftables.conf"

echo "👉 正在生成 nftables 配置文件..."

cat > "$NFT_CONFIG" <<EOF
#!/usr/sbin/nft -f

flush ruleset

# IPv4 转发表
table ip forward {
    chain prerouting {
        type nat hook prerouting priority 0;
        policy accept;
$IPV4_RULES
    }

    chain postrouting {
        type nat hook postrouting priority 100;
        policy accept;

        masquerade
    }
}
EOF

# === 如果启用了 IPv6，写入 IPv6 表 ===
if [ "$ENABLE_IPV6" = "yes" ]; then
cat >> "$NFT_CONFIG" <<EOF

# IPv6 转发表
table ip6 forward6 {
    chain prerouting {
        type nat hook prerouting priority -100;
        policy accept;
$IPV6_RULES
    }

    chain postrouting {
        type nat hook postrouting priority 100;
        policy accept;
$POSTROUTING_IPV6
    }
}
EOF
fi

# === 加载规则 ===
echo "👉 正在加载 nftables 规则..."
nft -f "$NFT_CONFIG"

# === 显示当前规则 ===
echo "✅ 当前 nftables 规则如下："
nft list ruleset

echo "✅ 所有端口转发设置完成！"
