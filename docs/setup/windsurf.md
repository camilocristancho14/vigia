# Set up Windsurf in Vigía

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

Vigía shows your Windsurf plan's daily and weekly quota, each as the percentage Windsurf reports, and when each resets.

> **Using Devin?** Windsurf now belongs to Cognition, and the Devin app is the former Windsurf editor. If you use the Devin app or app.devin.ai, set up **Devin** in Vigía instead — it needs nothing pasted. This Windsurf entry reads windsurf.com's own page, for accounts still managed there.

## What you need

A Windsurf account, signed in at [windsurf.com](https://windsurf.com) in Chrome, Edge, Brave or another Chromium browser. Windsurf keeps its sign-in in the page's storage rather than in a cookie, which Safari and Firefox don't let Vigía read.

## Steps

1. Open [windsurf.com/profile](https://windsurf.com/profile) and make sure you're signed in.
2. In Vigía: **Settings → Windsurf**. Turn on **Show in panel**. Under **Connection**, pick the browser you signed in with (or leave it on **Automatic**) and click **Read**.
3. Within a few seconds the ring appears, and the account's pane lists the daily and weekly quota.

## If it doesn't work

| Vigía says | What to do |
|---|---|
| Read a browser session in Settings. | Click **Read** in the Windsurf pane. |
| No session found. Sign in at windsurf.com first. | Sign in at windsurf.com in a Chromium browser, then click **Read** again. |
| The browser session expired. Sign in on the website, then read it again in Settings. | windsurf.com signed you out. Sign in again, then click **Read** again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Windsurf sent something Vigía doesn't recognize, or the plan has no quota. A quota that is fully spent may also be missing — Windsurf doesn't send a figure of zero. |

## What Vigía reads

The session Vigía reads is stored encrypted on this Mac and sent only to windsurf.com when Vigía checks your usage. Vigía reads your plan's name and the two quota figures; it doesn't read anything else on the account or change it. Signing out of windsurf.com ends that session.
