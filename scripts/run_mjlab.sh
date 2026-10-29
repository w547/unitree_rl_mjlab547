#!/usr/bin/env bash
# 一键运行：编译后启动 MuJoCo 仿真器和 g1_ctrl
# 用法：./scripts/run_mjlab.sh [--no-build]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MJLAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$WS_ROOT/env.sh"

SIM_DIR="$MJLAB_ROOT/simulate"
SIM_BIN="$SIM_DIR/build/unitree_mujoco"
CTRL_BIN="$MJLAB_ROOT/deploy/robots/g1/build/g1_ctrl"
CONFIG="$SIM_DIR/config.yaml"
LOG_DIR="$MJLAB_ROOT/logs"
BUILD=1

usage() {
    cat <<'EOF'
用法: ./scripts/run_mjlab.sh [选项]

默认行为:
  先调用 scripts/build_all.sh 编译，然后启动 MuJoCo 仿真器和 g1_ctrl

选项:
  --no-build    跳过编译，直接运行已有产物
  -h, --help    显示帮助

说明:
  - g1_ctrl 先启动并等待 lowstate，仿真器随后启动；控制器接管前由仿真器用固定 PD 保持出生位姿
  - joystick_type: keyboard 时使用键盘手柄，操作前先点击 MuJoCo 窗口
  - 检测到 /dev/input/js* 时按正常手柄模式运行
  - 没有手柄且不是 keyboard 模式时，临时把 use_joystick 改为 0
  - 退出时会自动恢复 config.yaml 并关闭仿真器和控制器
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build)
            BUILD=0
            shift
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

if [[ "$BUILD" -eq 1 ]]; then
    "$MJLAB_ROOT/scripts/build_all.sh"
fi

for f in "$SIM_BIN" "$CTRL_BIN" "$CONFIG"; do
    if [[ ! -e "$f" ]]; then
        echo "[错误] 缺少文件: $f"
        echo "请先运行 ./scripts/build_all.sh"
        exit 1
    fi
done

RUN_LOG_DIR="$LOG_DIR/run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_LOG_DIR"
SIM_LOG="$RUN_LOG_DIR/sim.log"
CTRL_LOG="$RUN_LOG_DIR/ctrl.log"

HAS_JOY=0
JOY_DEV=""
for dev in /dev/input/js*; do
    if [[ -e "$dev" ]]; then
        HAS_JOY=1
        JOY_DEV="$dev"
        break
    fi
done

JOY_TYPE="$(sed -nE 's/^[[:space:]]*joystick_type[[:space:]]*:[[:space:]]*"?([A-Za-z_]+)"?.*/\1/p' "$CONFIG" | head -1)"

CONFIG_BAK="$(mktemp /tmp/unitree_sim_config.XXXXXX)"
cp "$CONFIG" "$CONFIG_BAK"

SIM_PID=""
CTRL_PID=""
TAIL_PID=""

cleanup() {
    local code="$1"
    trap - EXIT INT TERM HUP
    set +e

    if [[ -n "$TAIL_PID" ]]; then
        kill "$TAIL_PID" 2>/dev/null
    fi
    if [[ -n "$CTRL_PID" ]]; then
        kill "$CTRL_PID" 2>/dev/null
    fi
    if [[ -n "$SIM_PID" ]]; then
        kill "$SIM_PID" 2>/dev/null
    fi
    for pid in "$TAIL_PID" "$CTRL_PID" "$SIM_PID"; do
        if [[ -n "$pid" ]]; then
            wait "$pid" 2>/dev/null
        fi
    done

    if [[ -f "$CONFIG_BAK" ]]; then
        cp "$CONFIG_BAK" "$CONFIG"
        rm -f "$CONFIG_BAK"
    fi

    echo
    echo "运行结束。日志目录: $RUN_LOG_DIR"
    exit "$code"
}

trap 'cleanup $?' EXIT
trap 'cleanup 130' INT
trap 'cleanup 143' TERM
trap 'cleanup 129' HUP

if [[ "$JOY_TYPE" == "keyboard" ]]; then
    echo "[提示] 使用键盘手柄 (joystick_type: keyboard)，操作前先点击 MuJoCo 窗口"
elif [[ "$HAS_JOY" -eq 1 ]]; then
    echo "[提示] 检测到手柄: $JOY_DEV"
else
    echo "[提示] 未检测到手柄，临时使用 use_joystick: 0"
    echo "       仿真器和控制器可以连接，但 FSM 只能停在 Passive。"
    if grep -qE '^[[:space:]]*use_joystick[[:space:]]*:' "$CONFIG"; then
        sed -i -E 's/^([[:space:]]*)use_joystick[[:space:]]*:.*/\1use_joystick: 0/' "$CONFIG"
    else
        printf '\nuse_joystick: 0\n' >> "$CONFIG"
    fi
fi

# MuJoCo 的 GLFW 是 X11 后端，DISPLAY 必须形如 ":N" 或 "host:N"。
# 桌面启动的终端偶尔把 WAYLAND_DISPLAY 的值误当成 DISPLAY（如 "wayland-0"），
# 或干脆没有 DISPLAY，这里统一校正为真实存在的 X socket。
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${DISPLAY:-}" || "$DISPLAY" != *:* ]]; then
    for sock in /tmp/.X11-unix/X*; do
        [[ -S "$sock" ]] || continue
        export DISPLAY=":${sock##*X}"
        break
    done
fi

echo
echo "==> 启动 g1_ctrl --network=lo"
echo "    日志: $CTRL_LOG"
echo "    按 Ctrl+C 结束"
"$CTRL_BIN" --network=lo > "$CTRL_LOG" 2>&1 &
CTRL_PID=$!

tail -n +1 -F "$CTRL_LOG" &
TAIL_PID=$!

sleep 1
if ! kill -0 "$CTRL_PID" 2>/dev/null; then
    wait "$CTRL_PID" 2>/dev/null || true
    echo "[错误] g1_ctrl 启动失败，最近日志："
    tail -n 20 "$CTRL_LOG" || true
    exit 1
fi

echo
echo "==> 启动 MuJoCo 仿真器"
echo "    显示: DISPLAY=${DISPLAY:-<未设置>}"
echo "    日志: $SIM_LOG"

SIM_ATTEMPTS=3
for ((attempt = 1; attempt <= SIM_ATTEMPTS; attempt++)); do
    : > "$SIM_LOG"
    "$SIM_BIN" >> "$SIM_LOG" 2>&1 &
    SIM_PID=$!

    sleep 3
    if kill -0 "$SIM_PID" 2>/dev/null; then
        break
    fi

    wait "$SIM_PID" 2>/dev/null || true
    SIM_PID=""

    if grep -q "could not initialize GLFW" "$SIM_LOG" && [[ "$attempt" -lt "$SIM_ATTEMPTS" ]]; then
        echo "[提示] MuJoCo 显示初始化失败 (第 $attempt/$SIM_ATTEMPTS 次)，2 秒后重试"
        echo "       DISPLAY=${DISPLAY:-<未设置>} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<未设置>} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<未设置>}"
        sleep 2
        continue
    fi

    echo "[错误] 仿真器启动失败，最近日志："
    echo "       DISPLAY=${DISPLAY:-<未设置>} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<未设置>} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<未设置>}"
    tail -n 20 "$SIM_LOG" || true
    exit 1
done

echo
echo "==> 仿真与控制器已就绪"
echo "    控制器接管前，仿真器用固定 PD 把机器人稳在出生位姿"
echo "    点击 MuJoCo 窗口后：按住 F 再按 ↑ 进入 FixStand，随后按 G 再按 J 进入 Velocity"
echo "    按 Ctrl+C 结束"

CTRL_STATUS=0
while kill -0 "$SIM_PID" 2>/dev/null && kill -0 "$CTRL_PID" 2>/dev/null; do
    sleep 1
done

if ! kill -0 "$CTRL_PID" 2>/dev/null; then
    wait "$CTRL_PID" || CTRL_STATUS=$?
    echo
    echo "[提示] g1_ctrl 已退出，最近日志："
    tail -n 20 "$CTRL_LOG" || true
fi

if ! kill -0 "$SIM_PID" 2>/dev/null; then
    echo
    echo "[提示] 仿真器已退出，最近日志："
    tail -n 20 "$SIM_LOG" || true
fi

exit "$CTRL_STATUS"
