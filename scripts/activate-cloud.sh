#!/bin/bash
# 激活云端模型的快速脚本
# 用法：./activate-cloud.sh kimi sk-xxxxxxxxxxxxx

set -e

ALIAS=$1
KEY=$2

if [ -z "$ALIAS" ] || [ -z "$KEY" ]; then
    echo "用法: $0 <cloud-alias> <api-key>"
    echo
    echo "可用云端别名："
    echo "  kimi         - Moonshot Kimi (KIMI_API_KEY)"
    echo "  deepseek     - DeepSeek V4 Pro (DEEPSEEK_API_KEY)"
    echo "  gemini       - Google Gemini (GEMINI_API_KEY)"
    echo "  qwen         - Alibaba Qwen (QWEN_API_KEY)"
    echo "  fable        - Anthropic Fable 5 (ANTHROPIC_API_KEY)"
    echo
    echo "示例: $0 kimi sk-xxxxxxxxxxxxx"
    exit 1
fi

# 映射别名到环境变量
case "$ALIAS" in
    kimi)
        ENV_VAR="KIMI_API_KEY"
        ;;
    deepseek)
        ENV_VAR="DEEPSEEK_API_KEY"
        ;;
    gemini)
        ENV_VAR="GEMINI_API_KEY"
        ;;
    qwen)
        ENV_VAR="QWEN_API_KEY"
        ;;
    fable)
        ENV_VAR="ANTHROPIC_API_KEY"
        ;;
    *)
        echo "错误: 未知别名 '$ALIAS'"
        exit 1
        ;;
esac

echo "正在激活 $ALIAS (设置 $ENV_VAR)..."

# 创建 systemd override 来注入环境变量
sudo mkdir -p /etc/systemd/system/llama-swap.service.d
cat << EOF | sudo tee /etc/systemd/system/llama-swap.service.d/cloud-$ALIAS.conf
[Service]
Environment="$ENV_VAR=$KEY"
EOF

echo "✓ 已创建 /etc/systemd/system/llama-swap.service.d/cloud-$ALIAS.conf"

# 重载并重启
sudo systemctl daemon-reload
echo "正在重启 llama-swap..."
sudo systemctl restart llama-swap

# 等待服务就绪
echo "等待服务就绪..."
for i in $(seq 1 20); do
    if curl -sf -m2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
        echo "✓ llama-swap 已就绪"
        break
    fi
    sleep 2
done

echo
echo "=========================================="
echo "云端模型 cloud-$ALIAS-k3 已激活！"
echo "=========================================="
echo
echo "测试命令："
echo "curl http://127.0.0.1:8080/v1/chat/completions \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"model\":\"cloud-$ALIAS-k3\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}'"
echo
echo "或在 Open WebUI (http://127.0.0.1:3000) 选择 cloud-$ALIAS-k3 模型"
