# Set up Synthetic in Vigía

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

Vigía shows your Synthetic quotas: the rolling 5-hour allowance, the weekly token allowance, and the hourly search allowance, each as the share Synthetic reports used.

## What you need

A Synthetic account with a subscription, and an API key from it.

## Steps

1. Sign in at [synthetic.new](https://synthetic.new) and create an API key (Synthetic's [API guide](https://dev.synthetic.new/docs/api/getting-started) shows where).
2. In Vigía: **Settings → Synthetic**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists each allowance. The hourly search allowance shows when it resets; the 5-hour and weekly allowances refill a slice at a time, so they show no single reset.

## If it doesn't work

| Vigía says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from synthetic.new. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Synthetic sent something Vigía doesn't recognize, or the account has no quotas right now. |

## What Vigía reads

Your key is stored encrypted on this Mac and sent only to Synthetic's own API (`api.synthetic.new`) when Vigía checks your usage. Asking for your quotas doesn't use any of them.
