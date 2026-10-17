# Set up Poe in Vigía

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

Vigía shows your Poe point balance. Poe reports a balance only — no allowance and no period — so there is no ring, just the balance on the account's pane.

## What you need

A Poe account and an API key.

## Steps

1. Open [poe.com/api/keys](https://poe.com/api/keys) and copy your API key.
2. In Vigía: **Settings → Poe**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the point balance appears on the account's pane.

## If it doesn't work

| Vigía says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from poe.com/api/keys. |
| That key was refused. Check it in Settings. | Copy the key again from poe.com/api/keys, or create a new one. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Poe sent something Vigía doesn't recognize. |

## What Vigía reads

Your key is stored encrypted on this Mac and sent only to Poe's own API (`api.poe.com`) when Vigía checks your balance. Your points history isn't read.
