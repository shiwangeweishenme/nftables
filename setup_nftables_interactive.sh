#!/bin/bash

echo "=============================="
echo "🔥 nftables 多端口转发脚本 🔥"
echo "支持 IPv4 / IPv6，批量添加或删除规则"
echo "=============================="

# 让用户选择添加或删除规则
while true; do
    read -p "请选择操作 (1添加端口转发/2删除端口转发): " OPERATION
    if [ "$OPERATION" = "1" ] || [ "$OPERATION" = "2" ]; then
        break
    else
        echo "输入无效，请输入 1 或 2。"
    fi
done

if [ "$OPERATION" = "1" ]; then
    # 清空变量
    IPV4_RULES=""
    IPV6_RULES=""
    POSTROUTING_IPV6=""
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
else
    # === 删除规则功能 ===
    NFT_CONFIG="/etc/nftables.conf"
    source <(grep -E '^IPV4_RULES|^IPV6_RULES|^POSTROUTING_IPV6|^ENABLE_IPV6' "$NFT_CONFIG")

    while true; do
        echo "--- 删除规则功能 ---"
        read -p "是否要删除规则？(yes/no): " DELETE_RULE
        if [ "$DELETE_RULE" != "yes" ]; then
            break
        fi

        read -p "要删除的规则是 IPv4 还是 IPv6？(ipv4/ipv6): " RULE_TYPE
        if [ "$RULE_TYPE" = "ipv4" ]; then
            # 从配置文件中提取 IPv4 规则
            ipv4_rules=$(grep -E 'tcp dport|udp dport' <<< "$(cat "$NFT_CONFIG")")
            if [ -z "$ipv4_rules" ]; then
                echo "没有可用的 IPv4 规则。"
                continue
            fi
            echo "当前 IPv4 规则如下："
            IFS=$'\n'
            rules=($(echo "$ipv4_rules"))
            for i in "${!rules[@]}"; do
                echo "$((i + 1)). ${rules[$i]}"
            done
            while true; do
                read -p "请输入要删除规则的编号: " RULE_NUMBER
                if [[ "$RULE_NUMBER" =~ ^[0-9]+$ ]] && [ "$RULE_NUMBER" -ge 1 ] && [ "$RULE_NUMBER" -le "${#rules[@]}" ]; then
                    rule_to_delete="${rules[$((RULE_NUMBER - 1))]}"
                    IPV4_RULES=$(echo "$IPV4_RULES" | grep -v "$rule_to_delete")
                    break
                else
                    echo "输入无效，请输入有效的规则编号。"
                fi
            done
        elif [ "$RULE_TYPE" = "ipv6" ]; then
            # 从配置文件中提取 IPv6 规则
            ipv6_rules=$(grep -E 'tcp dport|udp dport' <<< "$(cat "$NFT_CONFIG")" | grep -A1 'table ip6 forward6')
            if [ -z "$ipv6_rules" ]; then
                echo "没有可用的 IPv6 规则。"
                continue
            fi
            echo "当前 IPv6 规则如下："
            IFS=$'\n'
            rules=($(echo "$ipv6_rules"))
            for i in "${!rules[@]}"; do
                echo "$((i + 1)). ${rules[$i]}"
            done
            while true; do
                read -p "请输入要删除规则的编号: " RULE_NUMBER
                if [[ "$RULE_NUMBER" =~ ^[0-9]+$ ]] && [ "$RULE_NUMBER" -ge 1 ] && [ "$RULE_NUMBER" -le "${#rules[@]}" ]; then
                    rule_to_delete="${rules[$((RULE_NUMBER - 1))]}"
                    IPV6_RULES=$(echo "$IPV6_RULES" | grep -v "$rule_to_delete")
                    POSTROUTING_IPV6=$(echo "$POSTROUTING_IPV6" | grep -v "$rule_to_delete" | grep -v "$(echo "$rule_to_delete" | awk '{print $NF}' | cut -d: -f1)")
                    break
                else
                    echo "输入无效，请输入有效的规则编号。"
                fi
            done
        else
            echo "输入无效，请输入 ipv4 或 ipv6。"
            continue
        fi

        # 重新生成配置文件
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

        # 重新加载规则
        echo "👉 正在重新加载 nftables 规则..."
        nft -f "$NFT_CONFIG"

        # 显示更新后的规则
        echo "✅ 更新后的 nftables 规则如下："
        nft list ruleset
    done
fi

echo "✅ 所有操作完成！"    
