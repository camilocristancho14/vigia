# Set up Moonshot in Vigía

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

Vigía shows the money left on your Moonshot (Kimi Open Platform) API account: in US dollars on the international platform, in yuan on the China platform. The platform reports a balance and no allowance, so the balance is the reading. Any ring is Vigía's own estimate, not a figure Moonshot reported: **Ring measures** on the account's pane picks what it measures — **Since top-up** (the default), **My budget**, or **Balance only** for no ring.

This is the pay-as-you-go API. The Kimi Code subscription is a separate provider in Vigía.

## What you need

An API key from the Kimi Open Platform — the international console ([platform.moonshot.ai](https://platform.moonshot.ai)) or the China one. Either works; you don't pick which.

## Steps

1. Sign in to the platform's console and create an API key.
2. In Vigía: **Settings → Moonshot**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the account shows its balance.

Vigía asks the international platform first. If it refuses the key, Vigía asks the China platform, and remembers which one accepted it until Vigía quits.

## If it doesn't work

| Vigía says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from the platform's console. |
| That key was refused. Check it in Settings. | Neither platform accepted it. Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Moonshot sent something Vigía doesn't recognize. |

## What Vigía reads

Your key is stored encrypted on this Mac and sent only to Moonshot's own API (`api.moonshot.ai`, and `api.moonshot.cn` if the first refuses it) when Vigía checks your balance.
