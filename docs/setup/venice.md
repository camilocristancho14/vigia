# Set up Venice in Vigía

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

Vigía shows the balance your Venice API key spends from — US dollars, or DIEM if your account spends DIEM. Venice reports a balance and no allowance, so the balance is the reading. For a dollar balance, any ring is Vigía's own estimate, not a figure Venice reported: **Ring measures** on the account's pane picks what it measures — **Since top-up** (the default), **My budget**, or **Balance only** for no ring. A DIEM balance has no ring.

## What you need

A Venice API key, from the API section of your settings at [venice.ai](https://venice.ai).

## Steps

1. Sign in at venice.ai and create an API key.
2. In Vigía: **Settings → Venice**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the account shows its balance.

## If it doesn't work

| Vigía says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from venice.ai. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Venice sent something Vigía doesn't recognize. |
| No limits reported. | Venice reported neither a dollar nor a DIEM balance. |

## What Vigía reads

Your key is stored encrypted on this Mac and sent only to Venice's own API (`api.venice.ai`) when Vigía checks your balance. Vigía doesn't show subscription credits from the Venice website.
