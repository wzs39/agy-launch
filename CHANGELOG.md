# Changelog

## 1.1.0 — 2026-11-13

把「直接敲 `agy`」这件事也收进来，并堵住后台自愈。

### 新增

- `agy.cmd` — 可选 PATH 垫片，替换那个无条件起 mitmdump 的旧包装器；`agy` 现在
  默认直连，`agy launch` 才开菜单，缺 Python 时回落真 exe 而**不会**回落到 MITM。
- `[autostart]` 现在读 `schtasks /query /v` 的 *Task To Run* 列，不再按任务名猜。
  之前只匹配 `mitm`，漏掉了真正每 10 分钟拉起代理的 `\DSH-AgyUnlockProxy`，
  status 却显示「none」。同时列出 Startup 文件夹里可能自启的快捷方式。

### 修复

- `schtasks` 输出按控制台代码页（cp936）编码，用 `text=True` 读会在某个
  `0xaa` 字节上抛 `UnicodeDecodeError`，整个查询被吞掉 → status 误报「无自启任务」。
  改为 `capture_output` 拿 bytes，按 `locale.getpreferredencoding()` 解码且
  `errors="replace"`。
- 端口健康检查（`port_open`）会连接后立刻断开，不发送任何 SOCKS 字节；此前
  `handle()` 把这种 EOF 当错误记进 `socks-forward.log`，每 10 分钟一条噪声把真正
  的故障淹掉。现在 greeting 阶段的 `IncompleteReadError` 静默返回。

### 环境处置（本机，非仓库内容）

三条自愈任务全部 Disabled，其中 `\DSH-AgyUnlockProxy` 需要 UAC 提权才能改；
运行中的 mitmdump 已停，18080 / 1080 已释放。这些内容**不随仓库分发**。

## 1.0.0 — 2026-11-13

首个可发布版本。起因是一次账号停用（`This service has been disabled in this
account for violation of Terms of Service`），复盘发现老链路的根本问题不是某个
参数错了，而是**没有任何地方能声明「这次直连」**。

### 新增

- `agy-run.py` — 单一入口，四种模式：`direct` / `socks` / `mitm` / `status`。
  proxy 环境只设在 agy 子进程上，不写用户作用域、不改当前 shell。
- `socks_forward.py` — SOCKS5 CONNECT 纯转发。CONNECT 之后只搬字节，不解密、
  不看路径、不改响应体，上游看到的 TLS ClientHello 就是 agy 自己的 Go
  `crypto/tls`。
- `agy-run.py` 交互菜单（`interactive()`）— 菜单在 Python 里而不是 `.cmd` 里，原因见
  README「为什么菜单在 Python 里」。
- `status` 五段输出：binaries / listeners / parent proxy env / mitm CA /
  **autostart**。最后一节查计划任务，因为 `\agy-mitm-keepalive` 会在你选完
  `direct` 之后五分钟把 mitmdump 重新拉起来。
- `selftest_socks.py` — 用真实 TLS 握手证明通道端到端（对端证书必须由
  `Google Trust Services` 签发，而不是 mitmproxy）。
- `selftest_launch.py` — 12 项断言，覆盖三种模式的参数转发与 status 输出。

### 修复（开发过程中实测出来的）

- `asyncio.start_server` 回调写成 `lambda` 返回协程 → 协程不会被 await，客户端
  收到空连接。改 `functools.partial(handle, upstream=upstream)`。
- `decode("idna", "replace")` → `idna` 编解码器不接受 `errors=` 参数，抛
  `UnicodeError: Unsupported error handling: replace`。域名域改
  `decode("ascii", "replace")`，punycode 本就以 ASCII 传输。
- 异常处理器静默吞错 → 客户端只看到 `short read`，服务端日志空白，无法区分 DNS
  失败与解码异常。新增 `_report()`，每次失败落一行。
- `.cmd` 里的 UTF-8 中文被按控制台代码页（cp936）拆成零碎命令；`set /p` 在重定向
  stdin 下只吃第一行。菜单整体搬进 Python。

### 设计取舍

- **不提供 `agy_unlock_addon.py`**。响应体重写（删 `ineligibleTiers`、钉
  `currentTier`）是本次封禁的直接原因：客户端声称的 tier 与上游记录矛盾，
  服务端可见。`--mode mitm` 保留为接口，插件由使用者自行提供。
- **不 `taskkill /IM`**。老脚本会杀掉机器上所有 mitmdump，包括其它工具的。
  新入口只 terminate 自己启动的 PID。
- **`socks5h` 而不是 `socks5`**，让客户端把 DNS 交给代理；GUI 分支单独用
  `socks5://`，因为 Chromium 不认那个别名。
