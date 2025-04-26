#!/bin/bash

set -e

INSTALL_PATH="/usr/local/bin/nft-port-forward.sh"

echo "📦 安装 nftables 端口转发管理脚本..."

# 写入脚本内容
cat > "$INSTALL_PATH" << 'EOF'
#!/bin/bash

# === 健壮性检查 ===

if [[ -z "$BASH_VERSION" ]]; then
  echo "❌ 本脚本必须使用 bash 执行。请用以下方式运行："
  echo "   bash \$0"
  exit 1
fi

if ! command -v nft >/dev/null 2>&1; then
  echo "❌ 未找到 'nft' 命令，请先安装 nftables。"
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "❌ 当前系统不支持 systemctl，请手动管理 nftables。"
  exit 1
fi

NFT_CONFIG="/etc/nftables.conf"
TMP_EXPORT="/tmp/current_rules.nft"

if ! touch "$NFT_CONFIG" 2>/dev/null; then
  echo "❌ 无法写入 $NFT_CONFIG，请使用 root 权限运行脚本。"
  exit 1
fi

# === 彩色输出定义 ===
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=============================="
echo -e "🔥 nftables 端口转发 🔥"
echo -e "==============================${NC}"

echo -e "${BLUE}请选择操作类型：${NC}"
echo -e "1) 添加转发规则"
echo -e "2) 删除转发规则"
echo -e "3) 恢复系统默认设置"
read -p "请输入操作类型（1/2/3）： " ACTION

if [[ "$ACTION" == "1" ]]; then
  IPV4_RULES=""
  ENABLE_IPV6="n"

  echo -e "${BLUE}👉 正在开启内核转发...${NC}"
  sysctl -w net.ipv4.ip_forward=1 > /dev/null
  grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

  echo -e "${YELLOW}🔧 添加 IPv4 转发规则:${NC}"
  while true; do
    read -p "请输入本地监听端口（IPv4）: " LOCAL_PORT
    read -p "请输入目标服务器 IPv4 地址: " REMOTE_IPV4
    read -p "请输入目标服务器 IPv4 端口: " REMOTE_PORT

    IPV4_RULES+="
        tcp dport $LOCAL_PORT dnat to $REMOTE_IPV4:$REMOTE_PORT
        udp dport $LOCAL_PORT dnat to $REMOTE_IPV4:$REMOTE_PORT
    "

    read -p "是否继续添加 IPv4 转发规则？(y/n): " CONTINUE_IPV4
    [[ "$CONTINUE_IPV4" != "y" ]] && break
  done

  read -p "是否需要添加 IPv6 转发规则？(y/n): " ENABLE_IPV6
  if [[ "$ENABLE_IPV6" == "y" ]]; then
    echo -e "${YELLOW}🔧 添加 IPv6 转发规则:${NC}"
    IPV6_RULES=""
    POSTROUTING_IPV6="masquerade"

    while true; do
      read -p "请输入本地监听端口（IPv6）: " LOCAL_PORT6
      read -p "请输入目标服务器 IPv6 地址: " REMOTE_IPV6
      read -p "请输入目标服务器 IPv6 端口: " REMOTE_PORT6

      IPV6_RULES+="
        tcp dport $LOCAL_PORT6 dnat to [$REMOTE_IPV6]:$REMOTE_PORT6
        udp dport $LOCAL_PORT6 dnat to [$REMOTE_IPV6]:$REMOTE_PORT6
      "

      read -p "是否继续添加 IPv6 转发规则？(y/n): " CONTINUE_IPV6
      [[ "$CONTINUE_IPV6" != "y" ]] && break
    done
  fi

  echo -e "${BLUE}👉 启动 nftables 服务...${NC}"
  systemctl enable nftables > /dev/null
  systemctl start nftables

  echo -e "${BLUE}👉 生成配置文件：${NFT_CONFIG}${NC}"
  cat > "$NFT_CONFIG" <<EOF_CONF
#!/usr/sbin/nft -f

flush ruleset

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
EOF_CONF

  if [[ "$ENABLE_IPV6" == "y" ]]; then
    cat >> "$NFT_CONFIG" <<EOF_IPV6

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
EOF_IPV6
  fi

  echo -e "${BLUE}👉 加载 nftables 规则中...${NC}"
  nft -f "$NFT_CONFIG"

  echo -e "${GREEN}✅ 当前 nftables 规则如下：${NC}"
  nft list ruleset
  echo -e "${GREEN}✅ 所有端口转发设置完成！${NC}"
fi

if [[ "$ACTION" == "2" ]]; then
  echo -e "${BLUE}👉 正在读取当前转发规则...${NC}"
  nft list ruleset > "$TMP_EXPORT"
  TMP_MODIFIED="/tmp/modified_rules.nft"
  cp "$TMP_EXPORT" "$TMP_MODIFIED"

  MAP_IPV4=()
  MAP_IPV6=()
  INDEX_IPV4=0
  INDEX_IPV6=0

  echo -e "${YELLOW}📋 当前 IPv4 转发规则:${NC}"
  while IFS= read -r line; do
    if [[ "$line" =~ table\ ip\  ]]; then inside_ipv4=1; fi
    if [[ "$line" =~ table\ ip6\  ]]; then inside_ipv4=0; fi
    if [[ "$inside_ipv4" == 1 && "$line" =~ dport ]]; then
      MAP_IPV4+=("$line")
      echo -e "ipv4-$((INDEX_IPV4 + 1))) ${MAP_IPV4[$INDEX_IPV4]}"
      ((INDEX_IPV4++))
    fi
  done < "$TMP_EXPORT"

  echo -e "\n${YELLOW}📋 当前 IPv6 转发规则:${NC}"
  inside_ipv4=0
  while IFS= read -r line; do
    if [[ "$line" =~ table\ ip6\  ]]; then inside_ipv6=1; fi
    if [[ "$line" =~ table\ ip\  ]]; then inside_ipv6=0;_
