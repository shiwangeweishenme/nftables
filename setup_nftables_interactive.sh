#!/bin/bash

echo "=============================="
echo "🔥 nftables 多端口转发脚本 🔥"
echo "支持 IPv4 / IPv6，添加 / 删除规则"
echo "=============================="

echo "请选择操作："
echo "1. 添加转发规则"
echo "2. 删除转发规则"
read -p "请输入数字 (1/2): " ACTION

if [ "$ACTION" = "1" ]; then
  # === 添加规则逻辑 ===
  IPV4_RULES=""
  IPV6_RULES=""
  ENABLE_IPV6="no"

  echo "👉 开启内核转发配置..."
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -p

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

  echo "👉 启动 nftables 服务..."
  systemctl enable nftables
  systemctl start nftables

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

  echo "👉 正在加载 nftables 规则..."
  nft -f "$NFT_CONFIG"

  echo "✅ 当前 nftables 规则如下："
  nft list ruleset
  echo "✅ 所有端口转发设置完成！"

elif [ "$ACTION" = "2" ]; then
  # === 删除规则逻辑 ===
  echo "=== 删除转发规则 ==="
  echo "1. 删除 IPv4 转发规则"
  echo "2. 删除 IPv6 转发规则"
  echo "3. 删除所有转发规则"
  read -p "请选择要删除的类型 (1/2/3): " DELETE_OPTION

  case $DELETE_OPTION in
    1)
      echo "🔧 当前 IPv4 转发规则如下："
      nft list chain ip forward prerouting | nl
      read -p "请输入要删除的规则编号: " RULE_NUM
      HANDLE=$(nft list chain ip forward prerouting | sed -n "${RULE_NUM}p" | grep -o 'handle [0-9]\+' | awk '{print $2}')
      if [ -n "$HANDLE" ]; then
        nft delete rule ip forward prerouting handle $HANDLE
        echo "✅ 规则已删除。"
      else
        echo "❌ 无法识别该编号，请检查输入是否正确。"
      fi
      ;;
    2)
      echo "🔧 当前 IPv6 转发规则如下："
      nft list chain ip6 forward6 prerouting | nl
      read -p "请输入要删除的规则编号: " RULE_NUM
      HANDLE=$(nft list chain ip6 forward6 prerouting | sed -n "${RULE_NUM}p" | grep -o 'handle [0-9]\+' | awk '{print $2}')
      if [ -n "$HANDLE" ]; then
        nft delete rule ip6 forward6 prerouting handle $HANDLE
        echo "✅ 规则已删除。"
      else
        echo "❌ 无法识别该编号，请检查输入是否正确。"
      fi
      ;;
    3)
      echo "🚨 删除所有转发规则..."
      nft flush ruleset
      echo "✅ 所有规则已清除。"
      ;;
    *)
      echo "❌ 无效选项！"
      ;;
  esac

  echo "✅ 当前 nftables 规则如下："
  nft list ruleset
else
  echo "❌ 无效输入，请输入 1 或 2。"
  exit 1
fi
