# unitree_rl_mjlab 变更日志

记录 `unitree_rl_mjlab` 工程的代码、脚本与配置改动。构建运行日志保存在 `logs/`，不写入本文件。`unitree_rl_lab` 工程见 `unitree_rl_lab/CHANGELOG.md`。

## 写日志规则

1. 每条记录以 `## YYYY-MM-DD` 开头，日期下先写 1–2 句总结，句式：`因为 <需求/问题>，从 <原状态> 修改为 <新状态>。`
2. 总结之后依次写：背景、改动表、验证、已知限制（无内容可省略）。
3. 改动表固定四列：`类型 | 文件 | 说明`；类型只用 新增 / 修改 / 删除 / 生成。
4. 只记事实：改了什么、为什么改、怎么验证的；不写过程叙述，不重复背景。
5. `logs/` 下的构建运行日志属于产物，不写入本文件；配置项若只是运行期临时修改，需注明是否恢复。

## 2026-10-29

因为 sim2sim 启动阶段没有 lowcmd（脚本先起仿真器、3 s 后才起 g1_ctrl）以及 FSM 初始 Passive 的 kp=0 会让机器人无控倒地，从“启动阶段 ctrl=0 自由落体”修改为“g1_ctrl 先起等待 lowstate，仿真器用固定 PD 保持出生位姿直到收到 kp>0 的指令”。

### 背景

用户反馈仿真中机器人先站着、手垂下，随后整体摔倒。无 GUI 复现确认：`ctrl=0` 时 0.75 s 俯仰 0.96 rad、2.5 s 倒地；FSM 初始 Passive（kp=0、kd=3）同样不支撑；`run_mjlab.sh` 先起仿真器、`sleep 3` 后才起 `g1_ctrl`，这 3 s 内 `rt/lowcmd` 从未发布。策略本身正常：站立 pelvis≈0.784 m，指令 0.6 m/s 时 7.5 s 走 4.37 m。排查数据见 `doc/QA/2026-10-28_sim2sim站立后摔倒排查.md`。

### 改动

| 类型 | 文件 | 说明 |
|---|---|---|
| 修改 | `unitree_rl_mjlab/simulate/src/unitree_sdk2_bridge.h` | 新增启动保持：控制器接管前按 `ctrl = 500*(qpos0 - q) + 10*(0 - dq)` 把各关节稳在出生位姿（`qpos0` 经 `actuator_trnid` / `jnt_qposadr` 映射到关节）；收到任一 `kp>0` 的 lowcmd 后永久释放，恢复原 `tau + kp*(q_d - q) + kd*(dq_d - dq)`，并打印一行释放提示 |
| 修改 | `scripts/run_mjlab.sh` | 启动顺序改为 g1_ctrl 先起（停在 `Waiting for connection to robot...`）、仿真器后起；ctrl 启动 1 s 后做存活检查并打印日志；就绪提示补充键盘操作顺序（F+↑ 进 FixStand，G+J 进 Velocity） |

保持增益的取值：目标为 `mj_model->qpos0`，在 `scene_g1.xml` 实测 kp=200 时直腿位姿仍会下沉摔倒（踝 pitch 力矩上限左 50 / 右 25 N·m，撑不住约 219 N·m/rad 的倒立摆），kp=500/kd=10 可稳定 20 s。

### 验证

- `cmake --build unitree_rl_mjlab/simulate/build` 通过
- 用仓库自带 MuJoCo 3.3.6 无 GUI 复现（同一 `scene_g1.xml`、同一 `ctrl` 公式与 ctrlrange 限幅）：kp=500/kd=10 保持 20 s，pelvis z=0.791 m、俯仰 0.024 rad；施加 1.0 rad/s 俯仰扰动后 2 s 内回到 0.024 rad
- `bash -n scripts/run_mjlab.sh` 通过；实跑 `timeout -s INT 15 ./scripts/run_mjlab.sh --no-build`：g1_ctrl 先启动，仿真器起来后 `Connected to robot.`、四个状态初始化、`FSM: Start Passive`，日志 `logs/run_20261029_113301/`
- 按键接管后的完整闭环未在本机验证：验证时另一个 `run_lab.sh` 会话仍在运行，占用 `rt/lowcmd`，g1_ctrl 启动时报 `The other process is using the lowcmd channel, please close it first.`

### 已知限制

- 保持在收到 `kp>0` 之前有效；进入 FixStand 后完全交给控制器，FixStand 踝 kp=40 仍不足以静态自稳，需在约 1 s 内按 G+J 切到 Velocity（与真机行为一致）
- 同一 DDS 域内不能同时运行两个 lowcmd 发布者（如并行跑 `unitree_rl_lab` 的 sim2sim），否则报 lowcmd 通道被占用

## 2026-10-29

因为 `unitree_rl_lab` 工程新增了“编译并运行”入口，从“mjlab 的脚本与桌面入口使用通用名 `run_all` / `编译并运行`”修改为“统一加 `run_mjlab` / `unitree_rl_mjlab` 前缀，两个工程的入口可区分”。

### 改动

| 类型 | 文件 | 说明 |
|---|---|---|
| 修改 | `scripts/run_all.sh` → `scripts/run_mjlab.sh` | 重命名；帮助文本中的路径同步为 `run_mjlab.sh` |
| 修改 | `scripts/run_all_click.sh` → `scripts/run_mjlab_click.sh` | 重命名；内部调用改为 `./scripts/run_mjlab.sh` |
| 修改 | `编译并运行.desktop` → `unitree_rl_mjlab_编译并运行.desktop` | 重命名；`Name`、`Comment`、`Exec` 同步指向 `run_mjlab_click.sh` |
| 修改 | `scripts/build_all.sh` | 编译完成提示的运行入口改为 `run_mjlab.sh` |

脚本行为、`config.yaml`、仿真器与部署代码本次均未改动。

### 验证

- `bash -n` 通过（`run_mjlab.sh`、`run_mjlab_click.sh`）
- 桌面入口 `Exec` 指向 `scripts/run_mjlab_click.sh`，click 脚本调用 `./scripts/run_mjlab.sh`
- 重命名后未重跑 mjlab 仿真闭环，行为与 2026-10-28 记录一致；lab 侧实跑结果见 `CHANGELOG_unitree_rl_lab.md`

## 2026-10-28

因为需要确认双击启动能否跑通仿真，从“目录改名后脚本路径可能失效、GLFW 偶发初始化失败”修改为“双击即完成编译并启动 sim2sim，且显示初始化失败会自动重试并打印环境信息”。

### 背景

目录已改名为 `unitree_sdk2`、`unitree_rl_mjlab`，需要确认双击 `编译并运行.desktop` 能走完“终端 → 编译 → 仿真器 → g1_ctrl”的完整链路。

### 改动

| 类型 | 文件 | 说明 |
|---|---|---|
| 修改 | `scripts/build_all.sh` | 帮助文本中的 `unitree_rl_mjlab547` / `unitree_sdk2_547` 同步为改名后的路径，仅文案 |
| 修改 | `scripts/run_all.sh` | 启动仿真器前补 `XDG_RUNTIME_DIR`，`DISPLAY` 为空时从 `/tmp/.X11-unix/X*` 推断；遇到 `could not initialize GLFW` 自动重试，最多 3 次，并在失败时打印 `DISPLAY` / `WAYLAND_DISPLAY` / `XDG_SESSION_TYPE` |
| 修改 | `scripts/run_all.sh` | `DISPLAY` 也是启校验：不含冒号（如桌面启动偶发注入的 `wayland-0`）或为空时，统一校正为真实 X socket（`/tmp/.X11-unix/X*`）；启动仿真器时打印实际使用的 `DISPLAY` |

脚本逻辑、`config.yaml` 和部署代码本次未改动。

补 `DISPLAY` 回退和重试的原因：MuJoCo 用的是 X11 后端的 GLFW（`~/.local/deps/usr/lib/x86_64-linux-gnu/libglfw.so.3` 只链接 `libX11`），双击启动时偶发 `ERROR: could not initialize GLFW`；同一现象在 2026-10-22 也出现过一次，属于显示初始化抖动，不是编译或 DDS 问题。

### 验证

在桌面会话环境（`XDG_RUNTIME_DIR=/run/user/1001`、`DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus`）下用 `gio launch "./编译并运行.desktop"` 复现双击链路：

- 自动拉起 `gnome-terminal-server` 和 `run_all_click.sh`
- 编译日志 `logs/build_20261028_170500.log`，退出码 0
- 仿真器日志 `logs/run_20261028_170501/sim.log`：MuJoCo 3.3.6 启动，打印键盘手柄键位提示
- 控制器日志 `logs/run_20261028_170501/ctrl.log`：`Connected to robot.`、四个状态初始化、`FSM: Start Passive`
- 发送 SIGINT 后清理正常：无残留 `unitree_mujoco` / `g1_ctrl`，`config.yaml` 保持 `use_joystick: 1`、`joystick_type: "keyboard"`
- `env -u DISPLAY` 下 `./scripts/run_all.sh --no-build` 能自动回退到 `DISPLAY=:0` 并正常启动仿真闭环
- `DISPLAY=:99` 下验证重试逻辑：打印 3 次 `MuJoCo 显示初始化失败`、附 `DISPLAY` 信息后以退出码 1 结束，无残留进程
- 用户双击时曾出现一次 `ERROR: could not initialize GLFW`；随后用同一桌面入口复测正常启动（`logs/run_20261028_172048`）
- 用户再次双击复现失败，日志显示终端把 `WAYLAND_DISPLAY` 误注入为 `DISPLAY=wayland-0`；加入校验后用 `DISPLAY=wayland-0` 复测：自动校正为 `:0` 并正常启动；再用真实桌面入口复测启动成功、`sim.log` 无 GLFW 报错、`FSM: Start Passive`（`logs/run_20261028_172916`）

## 2026-10-26

因为无物理手柄时 FSM 只能停在 Passive，从“仅支持 xbox/switch 输入”修改为“新增键盘手柄（`joystick_type: keyboard`），可走通 FixStand → Velocity → Mimic 全链路”。

### 背景

当前环境没有物理手柄，`/dev/input/js0` 不存在。`use_joystick: 1` 时仿真器在 `XBoxJoystick` 构造阶段直接 `Joystick open failed` 退出；改 `use_joystick: 0` 虽能建立 DDS 连接，但不会发布 `rt/wirelesscontroller`，部署端 FSM 只能停在 Passive，无法验证 FixStand、Velocity 和 Mimic，闭环走不通。

目标是只改仿真器输入层，让键盘模拟 Unitree 无线手柄；部署工程 `g1_ctrl` 的 FSM、观测和策略代码保持完全不变。物理手柄仍然可用，通过 `joystick_type` 切换。

### 改动

| 类型 | 文件 | 说明 |
|---|---|---|
| 新增 | `unitree_rl_mjlab/simulate/src/physics_joystick.h` 中的 `KeyboardJoystick` | 继承 `UnitreeJoystick`，从 GLFW 按键状态生成 `lx/ly/rx`、A/B/X/Y、方向键、LB/RB、LT/RT；按键状态用 `std::atomic` 保存，供 1 kHz 桥接线程读取 |
| 修改 | `unitree_rl_mjlab/simulate/src/physics_joystick.h` | 键盘模式把 LT/RT 的 `smooth` 设为 1，按下即生效，避免 LT/RT + 动作键的 `on_pressed` 被平滑错过 |
| 修改 | `unitree_rl_mjlab/simulate/src/main.cc` | `user_key_cb` 记录按下/松开到 `KeyboardJoystick`；窗口失焦时清空按键；启动时打印键位提示 |
| 修改 | `unitree_rl_mjlab/simulate/src/unitree_sdk2_bridge.h` | `joystick_type` 增加 `keyboard` 分支；错误提示列出 xbox/switch/keyboard |
| 修改 | `unitree_rl_mjlab/simulate/config.yaml` | 默认 `joystick_type: "keyboard"`；`joystick_device` 仅 xbox/switch 使用 |
| 修改 | `scripts/build_all.sh`、`scripts/run_all.sh`、`env.sh` | 修正目录改名后遗留的 `unitree_sdk2_547` / `unitree_rl_mjlab547` 路径 |
| 修改 | `scripts/run_all.sh` | `joystick_type: keyboard` 时不再因缺少 `/dev/input/js*` 临时关闭 `use_joystick` |

部署工程 `unitree_rl_mjlab/deploy`、SDK 和算法训练部分均未改动。

### 键位

| 键盘 | 手柄 | 说明 |
|---|---|---|
| `W` / `S` | 左摇杆 上/下 | 前进 / 后退（`ly`） |
| `A` / `D` | 左摇杆 左/右 | 左移 / 右移（`lx`） |
| `Q` / `E` | 右摇杆 左/右 | 左转 / 右转（`rx`） |
| `↑` `↓` `←` `→` | 十字键 | up / down / left / right |
| `J` `K` `U` `I` | A / B / X / Y | 功能键 |
| `F` / `G` | LT / RT（L2 / R2） | 组合键，建议先按住 |
| `R` / `T` | LB / RB（L1 / R1） | 组合键，建议先按住 |
| `Enter` / `M` | Start / Back | 预留 |

G1 当前 FSM 组合：

- Passive → FixStand：`F` + `↑`
- FixStand → Velocity：`G` + `J`
- Velocity / Mimic → Passive：`F` + `K`
- Velocity → Mimic：`T` + `J`
- Mimic → Velocity：`G` + `J`

操作前先点击 MuJoCo 窗口获取焦点；先按住 LT/RT/LB/RB，再按动作键。物理手柄到手后把 `joystick_type` 改回 `"xbox"` 或 `"switch"` 即可。

### 验证

- `./scripts/build_all.sh -j 20` 编译通过，产物为 `g1_ctrl`、`unitree_mujoco`、`jstest`
- 独立单元测试验证 `KeyboardJoystick` 的摇杆、方向键、A/B、LB、LT 映射
- `./scripts/run_all.sh --no-build` 启动后仿真器不再报 `Joystick open failed`，`g1_ctrl` 正常连接并 `FSM: Start Passive`
- 键盘实测 FSM 迁移：Passive → FixStand → Velocity → Mimic_Dance1_subject2 → Velocity → Passive
- 实测 `rt/lowstate` 的 `wireless_remote` 在 `F + ↑` 时为 `0x1020`（L2 + up）
- 实测 Velocity 下按住 `W` 机器人位置发生变化，说明速度指令进入策略并驱动仿真

### 已知限制

- 键盘事件只在 MuJoCo 窗口聚焦时有效，窗口失焦会清空按键状态
- 键盘没有模拟模拟量，摇杆只有 -1/0/+1 三档，速度变化不如物理摇杆细腻
- 动作键的 `on_pressed` 是单帧触发，建议按键保持 0.3–0.5 s 以上；先按住扳机键再按动作键

## 2026-10-22

因为编译与运行步骤分散在命令行，从“手工多步编译、再手动分终端启动”修改为“一键脚本加桌面双击入口，编译后直接拉起 MuJoCo 与 g1_ctrl 闭环”。

### 背景

机器人预计下周到货。到货前需要完成“无真机可做”的部署工程复现。原先 SDK、`g1_ctrl`、MuJoCo 仿真器的编译分散在命令行中，依赖手动导出环境变量，步骤容易遗漏。目标是把编译整理成可点击、可重复执行的一键流程，同时保留命令行参数以便按需重编。

### 改动

| 类型 | 文件 | 说明 |
|---|---|---|
| 新增 | `scripts/build_all.sh` | 合并 `unitree_sdk2`、`g1_ctrl`、MuJoCo 仿真器三个构建任务；SDK 已安装时默认跳过；支持 `--clean`、`--with-sdk`、`-j N`；日志写入 `logs/` |
| 新增 | `scripts/build_all_click.sh` | 双击入口；调用 `build_all.sh`，结束后保留终端窗口以便查看结果 |
| 新增 | `编译全部工程.desktop` | GNOME 桌面启动器；`Terminal=true`；已设置可执行权限和 `metadata::trusted` |
| 修改 | `unitree_rl_mjlab547` 的 git remote | 由 `https://ghproxy.net/...` 改为 `https://gh-proxy.com/...`，用于绕过 GitHub 直连超时；不涉及源码 |
| 生成 | `logs/build_*.log` | 编译脚本运行日志，属于运行产物，不纳入源码变更 |

未修改 `unitree_sdk2_547` 和 `unitree_rl_mjlab547` 的上游源码。`env.sh` 是已有文件，构建脚本直接复用，未做改动。

验证用的临时文件 `/tmp/simtest/config.yaml` 仅用于确认 `use_joystick: 0` 时的行为，已删除，未进入项目。

### 验证

- `bash -n` 语法检查通过
- `./scripts/build_all.sh --help` 正常输出
- `./scripts/build_all.sh --clean` 完整清理重编通过，退出码 0
- 双击入口脚本测试通过
- 生成产物：
  - `unitree_rl_mjlab547/deploy/robots/g1/build/g1_ctrl`
  - `unitree_rl_mjlab547/simulate/build/unitree_mujoco`
  - `unitree_rl_mjlab547/simulate/build/jstest`

### 已知限制

- 当前没有 `/dev/input/js0` 手柄。`use_joystick: 1` 时仿真器会因 `Joystick open failed` 退出；改为 `0` 可以建立 DDS 连接，但 FSM 只能停在 Passive，无法验证 FixStand、Velocity 和跳舞。
- 构建脚本只解决编译问题；无真机闭环验证仍需要手柄。

### 追加：编译后运行

需求：编译完成后直接启动 MuJoCo 仿真器和 `g1_ctrl`，避免编译完还要手动开两个终端。

改动：

| 类型 | 文件 | 说明 |
|---|---|---|
| 新增 | `scripts/run_all.sh` | 默认先调用 `build_all.sh`，再启动 `unitree_mujoco` 和 `g1_ctrl --network=lo`；支持 `--no-build`；自动检测手柄；无手柄时临时把 `use_joystick` 改为 `0`，退出时恢复 |
| 新增 | `scripts/run_all_click.sh` | 双击入口；运行结束后保留终端窗口 |
| 新增 | `编译并运行.desktop` | GNOME 桌面启动器；`Terminal=true`；已设置可执行权限和 `metadata::trusted` |
| 修改 | `scripts/build_all.sh` | 编译完成提示中增加 `run_all.sh` 入口，不改变编译行为 |

运行脚本本身不修改上游源码；`simulate/config.yaml` 仅在运行期间临时修改，`EXIT/INT/TERM/HUP` 时自动恢复。运行日志写入 `logs/run_YYYYmmdd_HHMMSS/`，包含 `sim.log` 和 `ctrl.log`。

验证：

- `bash -n` 语法检查通过
- `./scripts/run_all.sh --help` 正常输出
- 无手柄环境下用 `--no-build` 实测：仿真器启动，`g1_ctrl` 输出 `Connected to robot.`、四个状态初始化完成、`FSM: Start Passive`
- 退出后 `config.yaml` 的 `use_joystick` 恢复为 `1`，无残留 `unitree_mujoco`/`g1_ctrl` 进程

补充说明：没有手柄时只能验证连接、配置、策略加载和 Passive；FixStand、Velocity、跳舞仍需手柄触发。

## 2026-10-29

因为要把工程纳入 Git 版本管理、将散落在工作区根目录的文件收进对应工程，从「运行/编译脚本、日志、.desktop 入口、变更日志放在 robot_rl 工作区根目录」修改为「全部移入 `unitree_rl_mjlab` 工程内，脚本按新位置自适应路径」。

### 改动

| 类型 | 文件 | 说明 |
|---|---|---|
| 移动 | `scripts/build_all.sh` | 从工作区 `scripts/` 移入本工程 `scripts/`；`ROOT` 拆为 `MJLAB_ROOT`（工程根）与 `WS_ROOT`（工作区根），`env.sh` 与 `unitree_sdk2` 走 `WS_ROOT`，产物与日志走 `MJLAB_ROOT`，usage 产物路径同步更新 |
| 移动 | `scripts/build_all_click.sh` | 从工作区 `scripts/` 移入本工程，内部相对调用不变 |
| 移动 | `scripts/run_mjlab.sh` | 从工作区 `scripts/` 移入本工程；`SIM_DIR`/`CTRL_BIN`/`LOG_DIR` 改为相对 `MJLAB_ROOT`，`build_all.sh` 调用路径同步更新 |
| 移动 | `scripts/run_mjlab_click.sh` | 从工作区 `scripts/` 移入本工程，内部相对调用不变 |
| 移动 | `unitree_rl_mjlab_编译并运行.desktop`、`编译全部工程.desktop` | 移入本工程根目录，`Exec`/`Path` 更新为本工程 `scripts/` 与工程根 |
| 移动 | `CHANGELOG_unitree_rl_mjlab.md` | 重命名并移入本工程根目录 `CHANGELOG.md` |
| 移动 | `logs/run_*`、`logs/build_*.log`、`MUJOCO_LOG.TXT` | 工作区 `logs/` 下 26 个运行日志目录、24 份编译日志与 MuJoCo 错误日志移入本工程 `logs/`（`.gitignore` 已含 `logs`、`MUJOCO_LOG.TXT`，不进入版本库） |
| 移动 | `doc/QA/`（4 份） | 工作区 `QA/` 下按主题归入本工程：部署编译产物关系、无手柄键盘控制说法核对、键盘控制 G1 仿真闭环、sim2sim 摔倒排查；本工程 CHANGELOG 中引用路径同步更新 |

### 验证

- `bash -n` 语法检查通过；`deploy/robots/g1`、`simulate`、`logs/` 路径均存在。

### 已知限制

- 未实际重跑编译与仿真，仅做了路径与语法静态校验。
