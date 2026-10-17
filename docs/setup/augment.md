# Set up Augment Code in Vigía

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

Vigía shows how much of your Augment Code credit allowance is used this billing cycle, and when the cycle ends.

## What you need

An Augment Code account, signed in at [app.augmentcode.com](https://app.augmentcode.com) in your browser. Vigía reads that browser session; there's no API key for this.

## Steps

1. Sign in at [app.augmentcode.com](https://app.augmentcode.com) in your browser.
2. In Vigía: **Settings → Augment Code**. Turn on **Show in panel**. Under **Read from browser**, pick your browser (or leave it on Automatic) and click **Read**.
   - Chrome, Edge, Brave, Arc and Vivaldi keep their cookies in the login keychain, so macOS may ask once for permission.
   - Safari needs Full Disk Access for Vigía, in System Settings → Privacy & Security.
3. Within a few seconds the ring appears, and the account's pane shows the credits used and when they reset.

## If it doesn't work

| Vigía says | What to do |
|---|---|
| No session found. Sign in at app.augmentcode.com first. | Sign in in that browser, then click **Read** again. |
| Read a browser session in Settings. | Click **Read** under **Read from browser**. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in again at app.augmentcode.com, then click **Read** again. Vigía can't renew a browser login on its own. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Augment sent something Vigía doesn't recognize, or it didn't state how many credits the cycle has — Vigía doesn't guess the allowance. |

## What Vigía reads

Vigía keeps only Augment's session cookies from your browser, stores them encrypted on this Mac, and sends them only to `app.augmentcode.com` when it checks your usage. It reads your credit figures, your plan's name and the cycle's end date; it doesn't change anything on the account, and it doesn't keep the session alive on its own.
