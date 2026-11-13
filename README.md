# agy-launch

给 [Antigravity CLI](https://antigravity.google) 的一个显式启动器：**由你选择这次
走不走代理，以及走哪种代理**，并把选择写进命令行而不是藏在某个批处理里。

起因很具体：2026-11-13 一个账号被 `This service has been disabled in this account
for violation of Terms of Service` 停用。复盘时发现老链路有个结构性问题 —— 每条
启动路径都自带一份代理逻辑，`agy.cmd`、`agy-unlock.cmd`、
`antigravity-gui-unlock.cmd` 各自起 mitmdump、各自装 CA、各自
`taskkill /IM mitmdump.exe`，而**没有任何地方能说「这次直连」**。于是每次出问题
第一件事都是改批处理文件，改完还容易忘。

这个仓库把那件事变成一个参数。

## 文件

| 文件 | 作用 |
|---|---|
| `agy.cmd` | **可选**：替换 PATH 里的旧包装器，让 `agy` 默认直连（`agy launch` 开菜单） |
| `agy-launch.cmd` | 双击/命令行入口，纯 ASCII，只负责转交给 Python |
| `agy-run.py` | 四种模式的实现 + 交互菜单（`interactive()`） |
| `socks_forward.py` | SOCKS5 CONNECT 纯转发，不拆 TLS、不改响应体 |
| `selftest_socks.py` | 证明 socks 通道是端到端 TLS |
| `selftest_launch.py` | 证明三种模式都能把参数转发给 agy |

### `agy` 这个名字归谁

`agy.cmd` 只在一种情况下有用：你的 PATH 里 `agy` 当前解析到的是那个**无条件启动
mitmdump 的旧包装器**。实测本机就是如此：

```
> where agy
C:\Users\qwe\.dsh\agy-unlock\agy.cmd     <- PATH 顺序在前，命中它
C:\Users\qwe\AppData\Local\agy\bin\agy.exe
```

因为 `.dsh\agy-unlock` 排在 `AppData\Local\agy\bin` 前面，敲 `agy` 等于走 MITM。
替换之后：

```bat
agy                        :: direct，无代理
agy -p "hello"             :: direct，参数原样转发
agy --mode socks -p "hi"   :: 显式模式
agy launch                 :: 交互菜单
```

替换前留一份原件 `agy.cmd.old`，随时可以改回去。若你的 PATH 里没有那个旧脚本，
这个文件用不上 —— 直接 `agy.exe` 或 `agy-launch.cmd` 即可。

**还有一个坑**：即便换掉了包装器，机器上仍可能有计划任务定期把 mitmdump 拉起来。
`--mode status` 的 `[autostart]` 会列出这些任务及其 Enabled/Disabled 状态；本机
实测有三条（`\agy-mitm-keepalive`、`\DSH-AgyUnlockProxy`、
`\AntigravityArmor-Divert-Watchdog`），全部需要 disable 才能保证「direct」不被
后台进程悄悄改写。

---

## 四种模式

| 模式 | 代理 | 需要 CA | 改响应体 | TLS 指纹 | 用途 |
|---|---|---|---|---|---|
| `direct` | 无 | 否 | 否 | agy 原生 Go | 默认；出问题先试 |
| `socks` | SOCKS5 纯转发 | 否 | 否 | agy 原生 Go | 要固定出口 |
| `mitm` | HTTP MITM | 是 | **是** | Python OpenSSL | 仅诊断 |
| `status` | — | — | — | — | 看清现状 |

### direct

真直连，不只是不设变量：

```python
env = os.environ.copy()
# Strip any inherited proxy so --mode direct really means direct.
for key in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy"):
    env.pop(key, None)
```

proxy 变量只设在 agy 子进程上 —— 不 `setx`，不改用户/系统作用域，不改当前 shell。
关掉 agy 就结束了，零残留。

### socks

`socks_forward.py` 起在 `127.0.0.1:1080`，CONNECT 之后只是搬字节：

```python
await asyncio.gather(_pipe(creader, swriter), _pipe(sreader, cwriter))
```

不解密、不看路径、不改 body。上游看到的 TLS ClientHello 就是 agy 自己的。
`selftest_socks.py` 会验证这一点 —— 对端证书签发者必须是
`Google Trust Services`，而不是 mitmproxy。

### mitm

旧的响应体重写路径，保留但隔离。它会删 `ineligibleTiers`、把 `currentTier` 钉到
`standard-tier`、替换坏 quota 响应。**这三件事服务端都看得见**：客户端声称的 tier
与上游记录矛盾，TLS 指纹变成 Python OpenSSL，响应头被重算。

只在一个不重要的诊断号上用。仓库里**不含**该插件，需要时自己提供
`agy_unlock_addon.py` 并放到同目录。

### status

```
[binaries]    文件和 mitmdump 在不在
[listeners]   socks 1080 / mitm 18080 是谁在听
[parent]      当前 shell 有没有被污染的 proxy 变量
[mitm CA]     CurrentUser\Root 里有几张某类证书
[autostart]   有没有计划任务会在背后把 mitmdump 拉起来
```

最后那节不是装饰。本机实测存在 `\agy-mitm-keepalive`，每 5 分钟检查 18080，
没人在听就重启 mitmdump。意味着你选完 `direct`，几分钟后机器上又多了个 mitmdump。

```bat
schtasks /change /tn "\agy-mitm-keepalive" /disable
```

---

## 用法

交互：

```bat
agy-launch.cmd
```

非交互：

```bat
agy-run.py --mode direct --target cli -- -p "hello"
agy-run.py --mode socks  --target cli -- -p "hello"
agy-run.py --mode socks  --target gui
agy-run.py --mode mitm   --target cli -- -p "hello"
agy-run.py --mode status
```

`--` 之后的参数原样传给 agy。省略 `--mode` 进入菜单。

### 换出口

```bat
agy-run.py --mode socks --upstream socks5h://HOST:PORT --target cli -- -p "hi"
```

`socks5h` 而不是 `socks5` —— 客户端把 DNS 交给代理，本机解析不泄漏。
GUI 那条分支单独处理：Chromium 不认 `socks5h://` 这个别名，只认 `socks5://`。

---

## 为什么菜单在 Python 里而不是 .cmd 里

两个实测踩到的坑：

1. **.cmd 按控制台代码页解析**。本机 cp936，文件里写 UTF-8 中文提示，行会被
   拆成零碎命令：

   ```
   't' is not recognized as an internal or external command
   'ocks' is not recognized as an internal or external command
   '样传给' is not recognized as an internal or external command
   ```

2. **`set /p` 在重定向 stdin 下吞输入**。`echo 1| ...cmd` 只喂进第一行，后面的
   `set /p` 读不到，菜单卡住或直接走默认值。

Python 的 `input()` 两个问题都没有，还能用 `shlex` 正确切分带引号的参数。
所以菜单逻辑在 `agy-run.py` 的 `interactive()`，`.cmd` 只做纯 ASCII 转发。

---

## 自检

```bat
python selftest_socks.py     :: 端到端 TLS 未被拦截
python selftest_launch.py    :: 三种模式都能把参数转发给 agy
```

`selftest_socks.py` 期望最后一行：

```
RESULT  passthrough confirmed (JA3 stays agy's own)
```

实际输出：

```
ok    socks5 listener on 127.0.0.1:2237
ok    CONNECT cloudcode-pa.googleapis.com:443 accepted
ok    TLS established, cipher=TLS_AES_256_GCM_SHA384
      peer CN=upload.video.google.com
      issuer O=Google Trust Services
ok    peer certificate is not a mitm certificate -> TLS is end-to-end
```

`selftest_launch.py` 12 项：

```
ok    status exits 0
ok    status reports [binaries]
ok    status reports [listeners]
ok    status reports [mitm CA
ok    status reports [autostart]
ok    status finds agy.exe
ok    direct exits 0
ok    direct prints the agy version
ok    direct says no proxy env
ok    socks exits 0
ok    socks prints the agy version
ok    socks reports the socks5h proxy

12/12 checks passed
```

---

## 依赖

- Python 3.9+（只用标准库：`argparse` / `asyncio` / `subprocess` / `socket` / `ssl`）
- `agy.exe`，默认路径 `%LOCALAPPDATA%\agy\bin\agy.exe`
- 可选：`Antigravity.exe`（GUI 目标）、`mitmdump`（仅 `--mode mitm`）

## 兼容性

路径按默认安装位置推导（`LOCALAPPDATA`），换机器无需改动。若装到别处，改
`agy-run.py` 顶部的 `AGY_EXE` / `GUI_EXE` 两行。

## 相关文档

- [`LAUNCH-MODES.md`](LAUNCH-MODES.md) — 中文操作说明与设计理由
- [`CHANGELOG.md`](CHANGELOG.md) — 版本记录，含开发过程中修掉的四个真实 bug

## License

MIT
