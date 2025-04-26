#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=============================="
echo -e "🔥 nftables 端口转发 🔥"
echo -e "==============================${NC}"

# 配置文件路径
NFT_CONFIG="/etc/nftables.conf"
TMP_EXPORT="/tmp/current_rules.nft"

# === 操作模式选择 ===
echo -e "${BLUE}请选择操作类型：${NC}"
echo -e "1) 添加转发规则"
echo -e "2) 删除转发规则"
echo -e "3) 恢复系统默认设置"
read -p "请输入操作类型（1/2/3）： " ACTION

# === 添加转发规则 ===
if [[ "$ACTION" == "1" ]]; then
  # === 初始化变量 ===
  IPV4_RULES=""
  ENABLE_IPV6="n"  # 默认不启用 IPv6 转发

  # === 启用内核转发 ===
  echo -e "${BLUE}👉 正在开启内核转发...${NC}"
  sysctl -w net.ipv4.ip_forward=1 > /dev/null
  grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

  # === 添加 IPv4 转发规则 ===
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

  # === 是否启用 IPv6 ===
  read -p "是否需要添加 IPv6 转发规则？(y/n): " ENABLE_IPV6

  # === 启动 nftables 服务 ===
  echo -e "${BLUE}👉 启动 nftables 服务...${NC}"
  systemctl enable nftables > /dev/null
  systemctl start nftables

  # === 写入配置文件 ===
  echo -e "${BLUE}👉 生成配置文件：${NFT_CONFIG}${NC}"
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

  # === 如果启用了 IPv6，则添加 IPv6 转发部分 ===
  if [[ "$ENABLE_IPV6" == "y" ]]; then
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
  echo -e "${BLUE}👉 加载 nftables 规则中...${NC}"
  nft -f "$NFT_CONFIG"

  # === 显示当前规则 ===
  echo -e "${GREEN}✅ 当前 nftables 规则如下：${NC}"
  nft list ruleset

  echo -e "${GREEN}✅ 所有端口转发设置完成！${NC}"
fi

# === 删除转发规则 ===
if [[ "$ACTION" == "2" ]]; then
  echo -e "${BLUE}👉 导出当前规则到 ${TMP_EXPORT}${NC}"
  nft list ruleset > "$TMP_EXPORT"

  echo -e "\n📝 请手动编辑该文件删除不需要的规则："
  echo -e "   ${YELLOW}sudo nano $TMP_EXPORT${NC}"
  echo -e "\n🔁 编辑完成后使用以下命令重新加载规则："
  echo -e "   ${GREEN}sudo nft -f $TMP_EXPORT${NC}"
  echo -e "\n💡 如需覆盖原配置并自动加载："
  echo -e "   ${GREEN}sudo cp $TMP_EXPORT $NFT_CONFIG${NC}"
  exit 0
fi

# === 恢复系统默认设置 ===
if [[ "$ACTION" == "3" ]]; then
  echo -e "${RED}⚠️ 正在恢复系统默认设置...${NC}"

  # 清空现有 nftables 规则
  echo -e "${BLUE}👉 清空现有 nftables 规则...${NC}"
  nft flush ruleset

  # 恢复默认配置
  echo -e "${BLUE}👉 恢复默认 nftables 配置...${NC}"
  echo -e "# 默认 nftables 配置\n\nflush ruleset" > "$NFT_CONFIG"

  # 恢复内核转发设置为默认关闭
  echo -e "${BLUE}👉 禁用 IPv4 内核转发...${NC}"
  sysctl -w net.ipv4.ip_forward=0 > /dev/null
  sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf

  # 恢复 IPv6 内核转发设置
  echo -e "${BLUE}👉 禁用 IPv6 内核转发...${NC}"
  sysctl -w net.ipv6.conf.all.forwarding=0 > /dev/null
  sysctl -w net.ipv6.conf.default.forwarding=0 > /dev/null
  sed -i '/net.ipv6.conf.all.forwarding=1/d' /etc/sysctl.conf
  sed -i '/net.ipv6.conf.default.forwarding=1/d' /etc/sysctl.conf

  # 重启 nftables 服务以应用新的配置
  echo -e "${BLUE}👉 重新加载 nftables 配置...${NC}"
  nft -f "$NFT_CONFIG"

  # 显示当前规则
  echo -e "${GREEN}✅ 系统已恢复为默认 nftables 配置！${NC}"
  nft list ruleset
fi
