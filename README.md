# VPS Auto Config

一个面向 `Ubuntu 22.04` / `Ubuntu 24.04` 的开源 `VPS` 首装脚本项目。  
它的目标不是做一套“大而全”的运维平台，而是提供一个**可重复执行、可交互选择、对高风险操作保持克制**的初始化脚本，让新机器在几分钟内具备基础可用性。

## 为什么做这个项目

很多 VPS 首装脚本都有两个常见问题：

- 全部逻辑塞在一个超长脚本里，后期难维护
- 默认直接改 `SSH`、防火墙、系统配置，容易把机器锁死

`VPS Auto Config` 想解决的是另一类需求：

- 新装 Ubuntu 之后，先把常用工具和基础配置补齐
- 每次运行时由用户自己选择要安装什么
- 能重复执行，尽量跳过已完成项
- 对 `SSH`、`UFW`、`swap` 这类高风险动作做额外确认

## 特性

- 基于 `Bash`，部署轻量，无需额外运行时
- `whiptail` 交互式菜单
- 模块化结构，方便继续扩展
- `curl + bootstrap` 启动方式
- 修改 `/etc` 配置前自动备份
- 尽量支持幂等（重复执行时跳过已完成项）
- 主要配置更新支持“有则改、无则加、相同则跳过”
- 聚焦“首装初始化”，不强行变成完整运维平台

## 支持范围

### 当前支持

- `Ubuntu 22.04`
- `Ubuntu 24.04`
- 纯命令行 `VPS`

### 当前已实现功能

#### 1. 系统工具

支持按需选择安装：

- `curl`
- `wget`
- `zip`
- `unzip`
- `vim`
- `nano`
- `tmux`
- `git`
- `htop`
- `btop`
- `tree`
- `lsof`
- `net-tools`
- `dnsutils`
- `traceroute`
- `rsync`

#### 2. 安全基线

- `UFW` 防火墙规则配置
- `Fail2ban` 安装与基础参数写入
- `SSH` 配置项选择：
  - `PubkeyAuthentication` 勾选控制
  - `PasswordAuthentication` 勾选控制
  - `PermitRootLogin` 支持 `yes / no / prohibit-password`
  - `Port` 单独修改
- 自动安全更新

#### 3. 系统配置

- `swapfile` 创建或重配
- `hostname` 设置
- 时区设置

#### 4. 运维辅助

- `MOTD` 主机摘要
- 少量通用 `alias`

## 非目标

当前版本**明确不做**这些事情：

- Docker / Compose 安装
- 完整 Web 服务栈（如 `Nginx`、`Caddy`、证书自动化）
- 分区型 `swap` 自动重配
- 默认强制修改 `SSH`

## 快速开始

### 方式一：本地仓库运行

```bash
git clone https://github.com/GlitterX/vps-auto-config.git
cd VPS-auto-config
sudo bash install.sh
```

### 方式二：通过 bootstrap 运行

请先使用 `root` 账号登录到服务器，再执行下面的命令。当前项目的远端启动方式按“已经是 root 登录会话”设计，不再额外包一层 `sudo`：

```bash
curl -fsSL https://raw.githubusercontent.com/GlitterX/vps-auto-config/main/bootstrap.sh \
  | env TERM=xterm bash
```

如果你使用的是 fork（派生仓库）或非默认分支，可以显式指定来源：

```bash
curl -fsSL https://raw.githubusercontent.com/GlitterX/vps-auto-config/main/bootstrap.sh \
  | env TERM=xterm BOOTSTRAP_GITHUB_REPO=GlitterX/vps-auto-config BOOTSTRAP_REF=main bash
```

也可以先下载后执行：

```bash
curl -fsSL https://raw.githubusercontent.com/GlitterX/vps-auto-config/main/bootstrap.sh -o /tmp/vps-bootstrap.sh
bash /tmp/vps-bootstrap.sh
```

如果你在远程终端里看到菜单把方向键显示成 `^[[B` 这类转义序列，通常表示当前 `TERM` 与服务器上的 `whiptail` / `terminfo` 不兼容。优先使用上面的 `env TERM=xterm bash` 写法；如果已经下载到本地文件，也可以这样执行：

```bash
env TERM=xterm bash /tmp/vps-bootstrap.sh
```

## 使用流程

脚本运行时会按下面的流程执行：

1. 检查当前用户是否为 `root`
2. 检查系统是否为 `Ubuntu 22.04 / 24.04`
3. 检查 `apt-get` 与 `whiptail`
4. 展示顶层功能组菜单
5. 展示本次执行计划预览
6. 对高风险操作进行二次确认
7. 执行安装与配置
8. 输出 `success / skip / failed` 汇总结果

## 项目结构

```text
bootstrap.sh
install.sh
lib/
├── apt.sh
├── backup.sh
├── detect.sh
├── log.sh
└── ui.sh
modules/
├── ops_helpers.sh
├── security.sh
├── system_config.sh
└── system_tools.sh
tests/
├── fixtures/
└── run.sh
```

### 结构说明

- `bootstrap.sh`
  - 对外启动入口，负责下载脚本包并执行安装脚本
- `install.sh`
  - 主流程入口，负责预检查、菜单、执行计划和汇总
- `lib/`
  - 公共函数，例如日志、检测、备份、APT、UI
- `modules/`
  - 各功能组的实现
- `tests/run.sh`
  - 轻量脚本级回归测试

## 测试

### 本地测试

运行轻量测试：

```bash
bash tests/run.sh
```

运行 Bash 语法检查：

```bash
find . -path './.git' -prune -o -path './.trellis' -prune -o -name '*.sh' -print | sort | xargs -I{} bash -n "{}"
```

### 真实环境验证

当前版本已经在真实 `Ubuntu 24.04` 服务器上做过一轮验证，覆盖了这些路径：

- 脚本级测试与 Bash 语法检查
- 工具安装（如 `tree`）
- `MOTD` 与 `alias`
- 自动安全更新
- `Fail2ban`
- `UFW`
- `swapfile`

为了避免锁死当前连接，`SSH` 端口和登录策略相关改动没有在在线会话里直接回归，建议始终先在测试机验证。

## 安全提示

这个项目会修改系统配置，请在使用前理解这些风险：

- `UFW`、`SSH`、`swap` 都属于高风险操作
- 建议先在可重建的测试机验证
- 不建议第一次就直接跑在生产机上
- 修改 `/etc` 前脚本会自动备份，但备份不等于完整回滚方案

## 路线图

计划中的后续方向包括：

- 补充更多 Bash 层测试
- 优化交互式菜单体验
- 增加模块计划生成相关测试
- 后续再评估 Docker / Web 服务模块

## 适合谁

这个项目更适合下面这些场景：

- 你经常新建 Ubuntu VPS
- 你希望首装步骤能复用，但不想把所有逻辑写死
- 你希望脚本尽量透明，而不是“一把梭”修改系统
- 你希望后续能自己继续扩展 Bash 模块

## License

本项目使用 [MIT License](./LICENSE)。
