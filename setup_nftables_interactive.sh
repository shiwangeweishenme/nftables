# === 删除规则功能 ===
while true; do
  echo "============================"
  echo "删除转发规则功能"
  echo "1. 删除 IPv4 转发规则"
  echo "2. 删除 IPv6 转发规则"
  echo "b. 返回"
  read -p "请选择要删除的规则类型 (1/2/b): " DELETE_OPTION

  if [ "$DELETE_OPTION" = "1" ]; then
    echo "🔧 当前 IPv4 转发规则如下："
    RULE_LIST=()
    INDEX=1
    # 获取所有规则和句柄
    nft list chain ip forward prerouting | grep -A 10 'chain prerouting' | while read -r LINE; do
      if [[ "$LINE" == *"dport"* ]]; then
        HANDLE=$(echo "$LINE" | grep -o 'handle [0-9]\+' | awk '{print $2}')
        DESC=$(echo "$LINE" | sed 's/ handle [0-9]\+//')
        RULE_LIST+=("$HANDLE:$DESC")
        echo "  $INDEX) $DESC"
        INDEX=$((INDEX + 1))
      fi
    done

    if [ ${#RULE_LIST[@]} -eq 0 ]; then
      echo "⚠️ 未找到 IPv4 转发规则。"
      continue
    fi

    read -p "请输入要删除的规则编号: " RULE_NUM
    RULE_NUM=$(echo "$RULE_NUM" | sed 's/[^0-9]*//g')

    if [ -z "$RULE_NUM" ] || [ "$RULE_NUM" -le 0 ] || [ "$RULE_NUM" -gt ${#RULE_LIST[@]} ]; then
      echo "❌ 无效编号，请输入有效的规则编号。"
      continue
    fi

    RULE_TO_DELETE="${RULE_LIST[$((RULE_NUM - 1))]}"
    HANDLE_TO_DELETE=$(echo "$RULE_TO_DELETE" | cut -d ':' -f 1)

    echo "正在删除规则: $RULE_TO_DELETE"
    nft delete rule ip forward prerouting handle "$HANDLE_TO_DELETE"
    if [ $? -eq 0 ]; then
      echo "✅ 规则已删除。"
    else
      echo "❌ 删除失败，请检查 handle 是否正确。"
    fi
  elif [ "$DELETE_OPTION" = "2" ]; then
    echo "🔧 当前 IPv6 转发规则如下："
    RULE_LIST=()
    INDEX=1
    # 获取所有规则和句柄
    nft list chain ip6 forward6 prerouting | grep -A 10 'chain prerouting' | while read -r LINE; do
      if [[ "$LINE" == *"dport"* ]]; then
        HANDLE=$(echo "$LINE" | grep -o 'handle [0-9]\+' | awk '{print $2}')
        DESC=$(echo "$LINE" | sed 's/ handle [0-9]\+//')
        RULE_LIST+=("$HANDLE:$DESC")
        echo "  $INDEX) $DESC"
        INDEX=$((INDEX + 1))
      fi
    done

    if [ ${#RULE_LIST[@]} -eq 0 ]; then
      echo "⚠️ 未找到 IPv6 转发规则。"
      continue
    fi

    read -p "请输入要删除的规则编号: " RULE_NUM
    RULE_NUM=$(echo "$RULE_NUM" | sed 's/[^0-9]*//g')

    if [ -z "$RULE_NUM" ] || [ "$RULE_NUM" -le 0 ] || [ "$RULE_NUM" -gt ${#RULE_LIST[@]} ]; then
      echo "❌ 无效编号，请输入有效的规则编号。"
      continue
    fi

    RULE_TO_DELETE="${RULE_LIST[$((RULE_NUM - 1))]}"
    HANDLE_TO_DELETE=$(echo "$RULE_TO_DELETE" | cut -d ':' -f 1)

    echo "正在删除规则: $RULE_TO_DELETE"
    nft delete rule ip6 forward6 prerouting handle "$HANDLE_TO_DELETE"
    if [ $? -eq 0 ]; then
      echo "✅ 规则已删除。"
    else
      echo "❌ 删除失败，请检查 handle 是否正确。"
    fi
  else
    break
  fi
done
