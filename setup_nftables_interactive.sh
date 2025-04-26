#!/bin/bash

# 检查是否有 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "此脚本需要以 root 权限运行。"
    exit 1
fi

# 询问是否开启内核转发
read -p "是否开启内核转发？(y/n): " enable_ip_forward
if [ "$enable_ip_forward" == "y" ]; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf  # 开启 IPv6 转发
    sysctl -p
    echo "内核转发已开启，包括 IPv6 转发。"
else
    echo "未开启内核转发。"
fi

# 询问是否安装 nftables
read -p "是否安装 nftables？(y/n): " install_nftables
if [ "$install_nftables" == "y" ]; then
    if [ -f "/etc/debian_version" ]; then
        apt install nftables -y
    elif [ -f "/etc/redhat-release" ]; then
        yum install nftables -y
    else
        echo "不支持的 Linux 发行版，跳过安装。"
    fi
    systemctl enable nftables
    systemctl start nftables
    echo "nftables 已安装并启动。"
else
    echo "跳过 nftables 安装。"
fi

# 询问是否创建或编辑 nftables 配置文件
read -p "是否创建或编辑 nftables 配置文件？(y/n): " create_edit_config
if [ "$create_edit_config" == "y" ]; then
    echo "请输入转发规则配置文件的路径（默认 /etc/nftables.conf）："
    read config_file
    config_file=${config_file:-/etc/nftables.conf}
    
    # 创建/编辑配置文件
    cat <<EOF > $config_file
#!/usr/sbin/nft -f

flush ruleset

# 创建一个名为 "foward" 的表，用于转发流量
table ip foward {

    # 在 prerouting 链中配置 DNAT（目的地址转换）
    chain prerouting {
        type nat hook prerouting priority 0; policy accept;
EOF

    # 询问用户是否需要添加端口转发规则
    read -p "是否添加端口转发规则？(y/n): " add_ports
    while [ "$add_ports" == "y" ]; do
        read -p "请输入源端口号（例如：2222）: " source_port
        read -p "请输入目标 IP 地址（例如：6.6.6.6）: " target_ip
        read -p "请输入目标端口号（例如：6666）: " target_port
        
        echo "tcp dport $source_port dnat to $target_ip:$target_port" >> $config_file
        echo "udp dport $source_port dnat to $target_ip:$target_port" >> $config_file

        # 询问是否继续添加规则
        read -p "是否继续添加端口转发规则？(y/n): " add_ports
    done

    # 结束 ipv4 的 prerouting 配置
    cat <<EOF >> $config_file
    }

    # 在 postrouting 链中配置 SNAT（源地址转换）
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;

        masquerade
    }
}

# IPv6 支持

table ip6 foward {

    # 在 prerouting 链中配置 DNAT（目的地址转换）
    chain prerouting {
        type nat hook prerouting priority 0; policy accept;
EOF

    # 询问用户是否需要添加 IPv6 端口转发规则
    read -p "是否添加 IPv6 端口转发规则？(y/n): " add_ipv6_ports
    while [ "$add_ipv6_ports" == "y" ]; do
        read -p "请输入源端口号（例如：2222）: " source_port
        read -p "请输入目标 IPv6 地址（例如：2001:db8::1）: " target_ip
        read -p "请输入目标端口号（例如：6666）: " target_port
        
        echo "tcp dport $source_port dnat to $target_ip:$target_port" >> $config_file
        echo "udp dport $source_port dnat to $target_ip:$target_port" >> $config_file

        # 询问是否继续添加规则
        read -p "是否继续添加 IPv6 端口转发规则？(y/n): " add_ipv6_ports
    done

    # 结束 ipv6 的 prerouting 配置
    cat <<EOF >> $config_file
    }

    # 在 postrouting 链中配置 SNAT（源地址转换）
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;

        masquerade
    }
}
EOF

    echo "配置文件已更新。"

    # 加载 nftables 配置
    nft -f $config_file
    echo "nftables 配置已加载。"
else
    echo "未创建或编辑 nftables 配置文件。"
fi

# 询问是否查看当前的 nftables 规则
read -p "是否查看当前的 nftables 规则？(y/n): " view_rules
if [ "$view_rules" == "y" ]; then
    nft list ruleset
fi

echo "脚本执行完毕。"
