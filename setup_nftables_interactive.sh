#!/bin/bash

echo "=============================="
echo "🔥 nftables 多端口转发脚本 🔥"
echo "支持 IPv4 / IPv6，添加 / 修改 / 删除规则"
echo "=============================="

while true; do
  echo "请选择操作："
  echo "1. 添加转发规则"
  echo "2. 修改转发规则"
  echo "3. 删除转发规则"
  echo "b. 返回上一级"
  read -p "请输入数字 (1/2/3/b): " ACTION

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

      # 添加合并的规则（TCP 和 UDP 作为一个规则）
      IPV4_RULES+="
          tcp dport $LOCAL_PORT dnat to $REMOTE_IPV4:$REMOTE_PORT
          udp dport $LOCAL_PORT dnat to $REMOTE_IPV4:$REMOTE_PORT
      "

      read -p "是否继续添加 IPv4 转发规则？(y/n): " CONTINUE_IPV4
      [[ "$CONTINUE_IPV4" != "y" ]] && break
    done

    read -p "是否需要添加 IPv6 转发规则？(y/n): " ENABLE_IPV6

    if [ "$ENABLE_IPV6" = "y" ]; then
      echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
      echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
      sysctl -p

      while true; do
        read -p "请输入本地监听端口（IPv6）: " LOCAL_PORT6
        read -p "请输入目标服务器 IPv6 地址（格式如 2001:db8::1）: " REMOTE_IPV6
        read -p "请输入目标服务器 IPv6 端口: " REMOTE_PORT6

        # 自动为 IPv6 地址加上中括号
        REMOTE_IPV6="[$REMOTE_IPV6]"

        # 添加合并的规则（TCP 和 UDP 作为一个规则）
        IPV6_RULES+="
            tcp dport $LOCAL_PORT6 dnat to $REMOTE_IPV6:$REMOTE_PORT6
            udp dport $LOCAL_PORT6 dnat to $REMOTE_IPV6:$REMOTE_PORT6
        "

        POSTROUTING_IPV6+="
            ip6 daddr $REMOTE_IPV6 masquerade
        "

        read -p "是否继续添加 IPv6 转发规则？(y/n): " CONTINUE_IPV6
        [[ "$CONTINUE_IPV6" != "y" ]] && break
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

    if [ "$ENABLE_IPV6" = "y" ]; then
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

  elif [ "$ACTION" = "3" ]; then
    # === 删除规则逻辑 ===
    while true; do
      echo "=== 删除转发规则 ==="
      echo "1. 删除 IPv4 转发规则"
      echo "2. 删除 IPv6 转发规则"
      echo "b. 返回上一级"
      read -p "请选择要删除的类型 (1/2/b): " DELETE_OPTION

      if [ "$DELETE_OPTION" = "1" ]; then
        echo "🔧 当前 IPv4 转发规则如下："
        RULE_LIST=()
        INDEX=1
        while read -r LINE; do
          HANDLE=$(echo "$LINE" | grep -o 'handle [0-9]\+' | awk '{print $2}')
          DESC=$(echo "$LINE" | sed 's/ handle [0-9]\+//')
          if [[ "$DESC" == *"dport"* ]]; then
            RULE_LIST+=("$HANDLE:$DESC")
            echo "  $INDEX) $DESC"
            INDEX=$((INDEX + 1))
          fi
        done < <(nft list chain ip forward prerouting)

        if [ ${#RULE_LIST[@]} -eq 0 ]; then
          echo "⚠️ 未找到 IPv4 转发规则。"
          exit 1
        fi

        read -p "请输入要删除的规则编号: " RULE_NUM
        # 清除输入中的非数字字符
        RULE_NUM=$(echo "$RULE_NUM" | sed 's/[^0-9]*//g')

        if [ -z "$RULE_NUM" ] || [ "$RULE_NUM" -le 0 ] || [ "$RULE_NUM" -gt ${#RULE_LIST[@]} ]; then
          echo "❌ 无效编号，请输入有效的规则编号。"
          continue
        fi

        RULE_TO_DELETE="${RULE_LIST[$((RULE_NUM - 1))]}"
        HANDLE_TO_DELETE=$(echo "$RULE_TO_DELETE" | cut -d ':' -f 1)

        # 删除选中的规则
        nft delete rule ip forward prerouting handle "$HANDLE_TO_DELETE"
        echo "✅ 规则已删除。"
      elif [ "$DELETE_OPTION" = "2" ]; then
        echo "🔧 当前 IPv6 转发规则如下："
        RULE_LIST=()
        INDEX=1
        while read -r LINE; do
          HANDLE=$(echo "$LINE" | grep -o 'handle [0-9]\+' | awk '{print $2}')
          DESC=$(echo "$LINE" | sed 's/ handle [0-9]\+//')
          if [[ "$DESC" == *"dport"* ]]; then
            RULE_LIST+=("$HANDLE:$DESC")
            echo "  $INDEX) $DESC"
            INDEX=$((INDEX + 1))
          fi
        done < <(nft list chain ip6 forward6 prerouting)

        if [ ${#RULE_LIST[@]} -eq 0 ]; then
          echo "⚠️ 未找到 IPv6 转发规则。"
          exit 1
        fi

        read -p "请输入要删除的规则编号: " RULE_NUM
        # 清除输入中的非数字字符
        RULE_NUM=$(echo "$RULE_NUM" | sed 's/[^0-9]*//g')

        if [ -z "$RULE_NUM" ] || [ "$RULE_NUM" -le 0 ] || [ "$RULE_NUM" -gt ${#RULE_LIST[@]} ]; then
          echo "❌ 无效编号，请输入有效的规则编号。"
          continue
        fi

        RULE_TO_DELETE="${RULE_LIST[$((RULE_NUM - 1))]}"
        HANDLE_TO_DELETE=$(echo "$RULE_TO_DELETE" | cut -d ':' -f 1)

        # 删除选中的规则
        nft delete rule ip6 forward6 prerouting handle "$HANDLE_TO_DELETE"
        echo "✅ 规则已删除。"
      else
        break
      fi
    done
  fi
done
