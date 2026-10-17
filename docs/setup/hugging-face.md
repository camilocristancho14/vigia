# Set up Hugging Face in Vigía

> Adapted for Vigía from the [Pulse](https://github.com/qunqin24/Pulse) documentation (Apache-2.0). Links into `qunqin24/Pulse` point at upstream pages that Vigía does not copy.

Vigía shows your Hugging Face account's ZeroGPU quota: how much of the GPU time included for ZeroGPU Spaces is used, and when it resets.

## What you need

A Hugging Face access token. Either paste one, or sign in with the Hugging Face command-line tool (`hf auth login`) on this Mac and Vigía uses the token it saved. A read token is enough.

## Steps

1. Either run `hf auth login` in a terminal, or create a token at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens).
2. In Vigía: **Settings → Hugging Face**. Turn on **Show in panel**. If you created a token, paste it into **API key** under **Connection** and click **Save**. A pasted token is used before the saved one.
3. Within a few seconds the ring appears, and the account's pane shows the quota and when it resets.

## If it doesn't work

| Vigía says | What to do |
|---|---|
| Add an API key in Settings. | Paste a token, or run `hf auth login`. |
| That key was refused. Check it in Settings. | The pasted token was refused. Create a fresh one and paste it again. |
| The saved login has expired. Sign in again with the service's own app or tool. | The token `hf auth login` saved was refused. Run `hf auth login` again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Hugging Face sent something Vigía doesn't recognize. |
| No limits reported. | The account has no ZeroGPU quota. |

## What Vigía reads

A pasted token is stored encrypted on this Mac. Otherwise Vigía reads the token in `~/.cache/huggingface/token` each time it checks, without changing it. Either way the token is sent only to Hugging Face (`huggingface.co`).

Vigía doesn't show Inference Providers charges or your prepaid credit balance yet.
