#!/usr/bin/env bash
# 桌面双击入口：调用 build_all.sh，结束后保留窗口以便查看结果
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT" || exit 1

./scripts/build_all.sh "$@"
status=$?

echo
if [[ $status -eq 0 ]]; then
    echo "编译完成。"
else
    echo "编译失败，退出码: $status"
fi
echo "日志目录: $ROOT/logs"
read -r -p "按回车键关闭窗口..." _

exit "$status"
