# Developer integrations / 开发者集成

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

Open **Vigía Settings → Developer integrations → Export integration files…**. Choose a folder; Vigía creates `Vigía Integrations` inside it. The kit contains a Raycast extension and scripts for tmux, sketchybar and a shell prompt. From a source checkout, the same files are in [`Integrations/`](../Integrations/).

在 **Vigía 设置 → 开发者集成 → 导出集成文件…** 中选择目录，即可获得 `Vigía Integrations` 文件夹。下方示例假定导出到了「下载」目录；其他位置请替换路径。Raycast 扩展通过本地导入安装，终端脚本需要 `jq`。

Every integration runs **`Vigia --json`**, which reads the cache without fetching providers or opening credentials. Keep Vigía running to update it. The output contains only accounts enabled on the rail. Missing figures stay missing; inferred figures carry `≈`; older readings remain explicitly dated. JSON contract: [json-output.md](json-output.md).

集成只读取缓存，不额外请求服务商。请保持 Vigía 运行；无读数显示 `—`，推算百分比显示 `≈`，脚本默认将至少 30 分钟前的读数标为 `(old)`。Raycast 会显示读数时间、所有限额及重置时间。

## Raycast

Requires Raycast and Node.js 22.18+ (or a current LTS). The local extension uses Raycast's own API; it is not automatically installed into Raycast by exporting the kit.

```bash
cd "$HOME/Downloads/Vigía Integrations/raycast"
npm ci
npm run dev
```

Once Raycast registers the extension, search for **Show AI Usage**. Search by provider or account label, inspect all limits and reset times in the detail pane, and press Return to open that account in Vigía. **⌘R reloads the cache**; it does not request new provider data. The action menu also copies an account link or a dated usage summary.

在 Raycast 搜索 **Show AI Usage**，可按服务商或账户名称筛选。回车直达对应账户设置；**⌘R 仅读取最新缓存**，不会强制请求服务商。

If Vigía is installed outside `/Applications`, set the extension's **Vigía Executable** preference to the full path ending in `Vigia.app/Contents/MacOS/Vigia`. Enter a plain path, without shell quotes. An unreadable executable or malformed report shows an error with a retry action; an empty cache offers Vigía Settings.

## Shell and tmux

Install `jq` if needed (`brew install jq`), then try:

```bash
/bin/bash "$HOME/Downloads/Vigía Integrations/vigia-status.sh"
VIGIA_ACCOUNT=claudeCode /bin/bash "$HOME/Downloads/Vigía Integrations/vigia-status.sh"
```

Example: `Claude Code: 42% used · Codex: 81% used (old)`.

Environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `VIGIA_BIN` | `/Applications/Vigia.app/Contents/MacOS/Vigia`, then `~/Applications` | Executable path, passed as one argument |
| `VIGIA_ACCOUNT` | All enabled accounts | Exact account id, including an added account's `#slot` |
| `VIGIA_MAX_AGE` | `1800` | Seconds before appending `(old)` |

Find account ids with the command copied from Settings:

```bash
/Applications/Vigia.app/Contents/MacOS/Vigia --json | jq -r '.accounts[] | [.id, .label] | @tsv'
```

Add to `~/.tmux.conf`:

```tmux
set -g status-interval 60
set -g status-right '#(VIGIA_ACCOUNT=claudeCode /bin/bash "$HOME/Downloads/Vigía Integrations/vigia-status.sh" --tmux)'
```

Reload with `tmux source-file ~/.tmux.conf`. `--tmux` escapes `#` in account labels so labels cannot become tmux formatting. The script removes control characters and uses the reported display percentage, including the distinction between `99%` and exhausted.

For zsh, a `precmd` hook can put the same summary in the right prompt:

```zsh
function vigia_precmd() {
  local value
  value=$(VIGIA_ACCOUNT=claudeCode /bin/bash "$HOME/Downloads/Vigía Integrations/vigia-status.sh") || value='Vigía —'
  RPROMPT="${value//\%/%%}"
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd vigia_precmd
```

This sets `RPROMPT`; incorporate it into an existing prompt configuration if you already use one. Remove the hook with `add-zsh-hook -d precmd vigia_precmd`.

## sketchybar

Keep `vigia-sketchybar.sh` beside `vigia-status.sh`. Add to `sketchybarrc`:

```bash
sketchybar --add item vigia right \
  --set vigia update_freq=60 \
    script="VIGIA_ACCOUNT=claudeCode /bin/bash \"$HOME/Downloads/Vigía Integrations/vigia-sketchybar.sh\"" \
    click_script="open 'vigia://account/claudeCode'"
```

The plugin uses sketchybar's `NAME` variable. A failed cache read replaces the label with `Vigía —`, rather than leaving an old figure unmarked. Change `VIGIA_ACCOUNT` and the click link together for another account. Remove the item with `sketchybar --remove vigia`.

## Account links

Copy an account link or its `open` command from **Developer integrations** in Settings:

```bash
open 'vigia://settings'
open 'vigia://integrations'
open 'vigia://account/codex'
open 'vigia://account/claudeCode%23YOUR-SLOT'
```

`%23` is the encoded `#` in an added account id. Use the copied link or the JSON `settingsURL` field instead of composing it by hand. Links select an existing account, clear the sidebar search, and open the settings window. They do not create accounts, change settings, or run a refresh/login command. A removed or unknown account does not create a pane. Query strings, fragments and unsupported routes are rejected.

The `vigia` URL scheme is registered by the **app bundle**, so install/open the bundled app for macOS to discover it. A bare `swift run Pulse` executable cannot register that scheme. Routing implementation: [architecture.md](https://github.com/qunqin24/Pulse/blob/main/Docs/architecture.md).

## Development checks

From `Integrations/raycast`, run `npm ci`, then `npm run build`, `npm run typecheck`, and `npm test`. Tests cover parsing, gaps, balance-only accounts, inferred figures, age, encoded links, and the actual shell formatter (requires `jq`). `ray build` compiles without opening Raycast; host UI interaction is a separate manual check.
