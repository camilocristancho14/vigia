# Set up xKiro in Vigía

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

xKiro (xkiro.com — not AWS's Kiro) is an API service. Vigía shows your plan's spend windows (5-hour and weekly), the daily free-token allowance, and your pay-as-you-go wallet balance.

## What you need

An xKiro account and an API key.

## Steps

1. Sign in at [xkiro.com](https://xkiro.com) and create an API key.
2. In Vigía: **Settings → xKiro**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears. The account's pane lists each window and when it resets, and the wallet balance.

## If it doesn't work

| Vigía says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from xkiro.com. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | xKiro sent something Vigía doesn't recognize, or reported no allowance and no wallet. |

## What Vigía reads

Your key is stored encrypted on this Mac and sent only to xKiro's own API (`api.xkiro.com`). xKiro documents the usage request as free: it uses no tokens and counts against no limit.
