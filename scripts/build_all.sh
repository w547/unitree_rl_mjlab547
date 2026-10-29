#!/usr/bin/env bash
# 一键编译 Unitree 部署工程：unitree_sdk2 + g1_ctrl + MuJoCo 仿真器
# 用法：./scripts/build_all.sh [--clean] [--with-sdk] [-j N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MJLAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 复用工作区根目录的环境变量脚本
# shellcheck disable=SC1091
source "$WS_ROOT/env.sh"

SDK_DIR="$WS_ROOT/unitree_sdk2"
RL_DIR="$MJLAB_ROOT"
DEPLOY_DIR="$RL_DIR/deploy/robots/g1"
SIM_DIR="$RL_DIR/simulate"
DEPS="$HOME/.local/deps/usr"
SDK_CONFIG="$DEPS/lib/cmake/unitree_sdk2/unitree_sdk2Config.cmake"
LOG_DIR="$RL_DIR/logs"
JOBS="$(nproc 2>/dev/null || echo 4)"
FORCE_SDK=0
CLEAN=0

usage() {
    cat <<'EOF'
用法: ./scripts/build_all.sh [选项]

默认行为:
  - 如果已安装 unitree_sdk2，则跳过 SDK，只编译 g1_ctrl 和仿真器
  - 如果未安装 SDK，则先编译并安装 SDK，再编译其余两个

选项:
  --clean       删除部署工程和仿真器的 build 目录后重新编译
  --with-sdk    强制重新编译并安装 unitree_sdk2
  -j, --jobs N  指定并行编译线程数，默认使用 nproc
  -h, --help    显示帮助

产物:
  deploy/robots/g1/build/g1_ctrl
  simulate/build/unitree_mujoco
  simulate/build/jstest
  ../unitree_sdk2/build/                       （仅在编译 SDK 时）
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN=1
            shift
            ;;
        --with-sdk)
            FORCE_SDK=1
            shift
            ;;
        -j|--jobs)
            JOBS="${2:-}"
            if [[ ! "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
                echo "[错误] --jobs 需要一个正整数" >&2
                exit 2
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[错误] 未知参数: $1" >&2
            usage
            exit 2
            ;;
    esac
done

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/build_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

trap 'echo; echo "[失败] 编译中断，日志: $LOG"; exit 1' ERR

need_dir() {
    if [[ ! -d "$1" ]]; then
        echo "[错误] 目录不存在: $1"
        exit 1
    fi
}

if ! command -v cmake >/dev/null 2>&1; then
    echo "[错误] 找不到 cmake。请确认 $DEPS/bin 已加入 PATH。"
    exit 1
fi

need_dir "$SDK_DIR"
need_dir "$DEPLOY_DIR"
need_dir "$SIM_DIR"

echo "============================================================"
echo " Unitree 部署工程编译"
echo " 项目根目录: $MJLAB_ROOT"
echo " 依赖前缀:   $DEPS"
echo " 并行线程:   $JOBS"
echo " 日志文件:   $LOG"
echo "============================================================"

build_sdk() {
    echo
    echo "==> [1/3] 编译并安装 unitree_sdk2"
    if [[ "$CLEAN" -eq 1 ]]; then
        rm -rf "$SDK_DIR/build"
    fi
    cmake -S "$SDK_DIR" -B "$SDK_DIR/build" \
        -DCMAKE_INSTALL_PREFIX="$DEPS" \
        -DBUILD_EXAMPLES=OFF
    cmake --build "$SDK_DIR/build" --parallel "$JOBS"
    cmake --install "$SDK_DIR/build"
}

build_deploy() {
    echo
    echo "==> [2/3] 编译部署工程 g1_ctrl"
    if [[ "$CLEAN" -eq 1 ]]; then
        rm -rf "$DEPLOY_DIR/build"
    fi
    cmake -S "$DEPLOY_DIR" -B "$DEPLOY_DIR/build" \
        -DCMAKE_PREFIX_PATH="$DEPS"
    cmake --build "$DEPLOY_DIR/build" --parallel "$JOBS"
    if [[ ! -x "$DEPLOY_DIR/build/g1_ctrl" ]]; then
        echo "[错误] 未生成 $DEPLOY_DIR/build/g1_ctrl"
        exit 1
    fi
}

build_sim() {
    echo
    echo "==> [3/3] 编译 MuJoCo 仿真器"
    if [[ "$CLEAN" -eq 1 ]]; then
        rm -rf "$SIM_DIR/build"
    fi
    cmake -S "$SIM_DIR" -B "$SIM_DIR/build" \
        -DCMAKE_PREFIX_PATH="$DEPS"
    cmake --build "$SIM_DIR/build" --parallel "$JOBS"
    for bin in unitree_mujoco jstest; do
        if [[ ! -x "$SIM_DIR/build/$bin" ]]; then
            echo "[错误] 未生成 $SIM_DIR/build/$bin"
            exit 1
        fi
    done
}

if [[ "$FORCE_SDK" -eq 1 ]]; then
    build_sdk
elif [[ -f "$SDK_CONFIG" ]]; then
    echo
    echo "==> [1/3] 已检测到 unitree_sdk2，跳过（需要重编请加 --with-sdk）"
else
    build_sdk
fi

build_deploy
build_sim

echo
echo "============================================================"
echo " 编译完成"
echo "============================================================"
echo " SDK 安装前缀: $DEPS"
echo " 部署程序:     $DEPLOY_DIR/build/g1_ctrl"
echo " 仿真器:       $SIM_DIR/build/unitree_mujoco"
echo " 手柄测试:     $SIM_DIR/build/jstest"
echo " 编译日志:     $LOG"
echo " 运行:         $MJLAB_ROOT/scripts/run_mjlab.sh"
