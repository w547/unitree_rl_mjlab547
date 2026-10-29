#!/usr/bin/env bash
# 桌面双击入口：编译并运行，结束后保留窗口以便查看结果
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT" || exit 1

./scripts/run_mjlab.sh "$@"
status=$?

echo
if [[ $status -eq 0 ]]; then
    echo "运行结束。"
else
    echo "运行结束，退出码: $status"
fi
echo "日志目录: $ROOT/logs"
read -r -p "按回车键关闭窗口..." _

exit "$status"
