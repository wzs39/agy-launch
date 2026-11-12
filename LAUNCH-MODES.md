# agy 启动方式选择（direct / socks / mitm）

一个入口，四种启动方式，互不干扰。改这条链路的起因：2026-11-13 账号被
`violation of Terms of Service` 停用，而旧链路里没有任何地方能说"这次直连"。

## 文件

| 文件 | 作用 |
|---|---|
| `agy-launch.cmd` | 双击/命令行入口，只负责转交给 Python（菜单在 Python 里，见下方"为什么"） |
| `agy-run.py` | 四种模式的真正实现：`direct` / `socks` / `mitm` / `status` |
| `socks_forward.py` | SOCKS5 CONNECT 纯转发，不拆 TLS、不改响应体 |
| `selftest_socks.py` | 证明 socks 通道是端到端 TLS（对端证书是 Google 而不是 mitmproxy） |
| `selftest_launch.py` | 证明 `agy-run.py` 三种模式都能把参数转发给 agy |
| `agy_unlock_addon.py` | 旧的 MITM 改写插件，只在 `--mode mitm` 下使用 |

旧文件 `agy.cmd` / `agy-unlock.cmd` / `antigravity-gui-unlock.cmd` /
`mitm-ensure.cmd` 保持原样没动，但**不建议再用**：它们每次都会拉起
mitmdump、装 CA、`taskkill /IM mitmdump.exe`（会误杀机器上其它 mitmdump）。

## 用法

交互（推荐）：
```
agy-launch.cmd
```

非交互：
```bat
agy-run.py --mode direct --target cli -- -p "hello"
agy-run.py --mode socks  --target cli -- -p "hello"
agy-run.py --mode socks  --target cli --port 1080
agy-run.py --mode socks  --target gui
agy-run.py --mode mitm   --target cli -- -p "hello"
agy-run.py --mode status
```

`--` 之后的参数原样传给 agy。`--mode` 省略就是交互菜单。

## 四种模式

### direct — 什么都不挂
- 不设 `HTTP(S)_PROXY`，不起代理，不碰 CA
- 子进程环境里连继承来的 proxy 变量都清掉，所以"direct"是真的直连
- **出问题时第一个该试的就是它**

### socks — 只搬字节
- `socks_forward.py` 起在 `127.0.0.1:1080`，客户端用 `socks5h://`
- CONNECT 之后是裸 TCP 流：不解密、不看路径、不改 body
- 上游看到的 TLS ClientHello 就是 agy 自己的（Go `crypto/tls`），JA3 不变
- 对端证书是 `Google Trust Services` 而不是 mitmproxy —— `selftest_socks.py` 会验证这一点

### mitm — 改写响应体（仅诊断）
- 需要 `mitmdump` + `CurrentUser\Root` 里有 mitmproxy CA
- 会删 `ineligibleTiers`、把 `currentTier` 钉到 `standard-tier`、替换坏 quota 响应
- **这三件事都是服务端可见的**：客户端声称的 tier 与上游记录矛盾，TLS 指纹变成
  Python OpenSSL，响应头被重算。2026-11-13 的封禁就是这条路径的后果
- 只在一个不重要的诊断号上用，不要挂在主力号

### status — 一眼看全
```
[binaries]    四个文件和 mitmdump 在不在
[listeners]   socks 1080 / mitm 18080 是谁在听
[parent]      当前 shell 有没有被污染的 proxy 变量
[mitm CA]     CurrentUser\Root 里有几张某类证书
[autostart]   有没有计划任务会在背后把 mitmdump 拉起来
```

`[autostart]` 这一节不是装饰：本机实测存在 `\agy-mitm-keepalive`，它每 5 分钟
检查 18080 并重新拉起 mitmdump。意味着你选完 `direct`，几分钟后机器上又多了个
mitmdump。要真正回到干净状态：

```bat
schtasks /change /tn "\agy-mitm-keepalive" /disable
```

## 环境隔离

所有模式都遵守同一条：**proxy 变量只设在 agy 子进程上**。

- 不写 `setx`，不改用户/系统作用域
- 不改本 shell 的环境（`setlocal` + 逐子进程传 env）
- 不 `taskkill /IM` 任何东西（旧脚本会杀掉机器上所有 mitmdump）

所以 `--mode direct` 是一次性、无残留的动作：关掉 agy 就结束了。

## 为什么菜单在 Python 里而不是 .cmd 里

两个实测踩到的坑：

1. **.cmd 按控制台代码页解析**。本机 cp936，文件里写 UTF-8 中文提示，
   `echo` 行会被拆成零碎命令，控制台刷出一堆
   `'xxx' is not recognized as an internal or external command`。
   所以 `agy-launch.cmd` 是纯 ASCII。
2. **`set /p` 在重定向 stdin 下吞输入**。`echo 1| ...cmd` 只喂进第一行，
   后面的 `set /p` 读不到，菜单直接卡住或走默认值。

Python 的 `input()` 两个问题都没有，顺带还能用 `shlex` 正确切分带引号的参数，
所以菜单逻辑搬到 `agy-run.py` 的 `interactive()`，`.cmd` 只做转发。

## 换出口

`socks` 模式支持链到上游 SOCKS5，让上游做 DNS（避免本机解析泄漏）：

```bat
agy-run.py --mode socks --upstream socks5h://HOST:PORT --target cli -- -p "hi"
```

一个号配一个出口，不要多个 OAuth 身份共用同一个公网 IP。

## 自检

```bat
python selftest_socks.py     :: 端到端 TLS 未被拦截
python selftest_launch.py    :: 三种模式均能把参数转发给 agy（12 项）
```

`selftest_socks.py` 期望输出最后一行：
```
RESULT  passthrough confirmed (JA3 stays agy's own)
```
