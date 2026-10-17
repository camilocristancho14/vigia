# Set up Cursor in Vigía

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

Vigía shows Cursor's two usage pools — "Cursor Models" (Composer and Cursor's own models) and "Other Models" (everything else) — plus, if your plan has them, an extra-spend limit and a credit balance. On a plan with a weekly usage limit, such as Premium, Vigía shows that weekly limit in place of the two pools.

## What you need

A Cursor account, signed in to the Cursor editor on this Mac. There is nothing to install beyond Cursor itself.

## Steps

1. Open Cursor and sign in with your Cursor account, if you have not already.
2. In Vigía, go to Settings → Cursor and turn on "Show in panel". There is nothing to paste — Vigía builds its request from the sign-in Cursor's editor already stored locally.
3. Success looks like a ring for Cursor on the Vigía panel, filled in with the "Cursor Models" and "Other Models" pools, or with the weekly limit on a weekly plan.

Cursor does not support adding a second account in Vigía: usage always comes from whichever account this Mac's Cursor editor is signed in to. Note that Grok Bot is a separate Vigía provider — it is billed to the same Cursor account but has its own ring and its own sign-in.

## If it doesn't work

| Message Vigía shows | What to do |
|---|---|
| Sign in to Cursor to see usage. | Open Cursor and sign in, then click Retry. |
| Cursor's saved login was refused. Open Cursor to renew it. | Open Cursor and use it for a moment — it renews its own login automatically — then click Retry. |

## What Vigía reads

Vigía reads Cursor's own sign-in token from the editor's local database on this Mac (the same one Cursor itself uses) and sends it only to Cursor, to build the request that asks for your usage summary. Vigía does not store a Cursor credential of its own, and does not read your browser's cookies to get it.
