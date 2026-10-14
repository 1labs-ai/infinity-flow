# Infinity Flow: positioning and launch copy

## Positioning

**For** people who type all day (founders, PMs, developers, writers) **who** want voice dictation without sending their
voice to someone else's cloud or paying another subscription, **Infinity Flow is** a free, open-source macOS dictation app
that works in every app. **Unlike** subscription cloud dictation tools, it runs on your Mac by default, lets you bring your
own key when you want the cloud, and never loses a word.

**Tagline:** Speak anywhere. Keep your words.

**One-liner:** Free, open-source voice dictation for Mac. Private by default, no subscription, never loses a word.

## Message pillars (each answers a gap users reported)

| Pillar | Proof we can show | User pain it answers |
|---|---|---|
| **Private by default** | On-device transcription by default, no server, no account, no screenshots, and a privacy receipt in the app | Cloud-only dictation; a 2025 Reddit thread exposed screenshots of the active window sent to the cloud ([Voibe](https://www.getvoibe.com/resources/wispr-flow-review/), [Laxis](https://laxis.com/blog/wispr-flow/)) |
| **No subscription** | Free and unlimited on device. With your own key: Groq free tier, OpenAI about $0.003 per minute, and a cost meter in Settings | $12–15 a month and a free tier capped at about 2,000 words a week ([G2](https://www.g2.com/products/wispr-flow/pricing), [Voibe pricing](https://www.getvoibe.com/resources/wispr-flow-pricing/)) |
| **Never loses a word** | Recordings kept until transcribed, retry from History, paste confirmation that leaves the text on the clipboard | "Works when it works, about 60% of the time"; Trustpilot around 2.5–2.7 out of 5 ([Trustpilot](https://ca.trustpilot.com/review/wisprflow.ai)) |
| **Your words, not the AI's** | Off / Light / AI polish; a guard that rejects lost numbers; the original always in History | Smart Formatting drops or changes words and numbers ([Wispr docs](https://docs.wisprflow.ai/articles/6568835559-why-wispr-flow-sometimes-removes-or-changes-words-on-android-smart-formatting)) |
| **Native and light** | 2.4 MB app, about 28 MB of memory at idle (measured) | Electron app around 800 MB and 8–10 s startup reported on Windows ([Laxis](https://laxis.com/blog/wispr-flow/)) |

**Rules for copy:** claim only what's in the app and measured. In ads, say "subscription dictation apps" rather than
naming competitors. Keep competitor names to factual, sourced comparisons.

## Landing hero

> **Speak anywhere. Keep your words.**
> Hold fn, talk, let go. Your words appear in any app on your Mac. Free, open source, and private by default.
> [Download for Mac] [Star on GitHub]
>
> No subscription · No account · Runs on your Mac · Bring your own key for the cloud

## WhatsApp: developers

```
Hi all, we just open sourced *Infinity Flow*, a voice dictation app for Mac.

Hold fn, speak, release. Text lands in any app: Slack, Cursor, terminal, Gmail. Native Swift, around 28 MB memory, transcribes on device by default.

No subscription. Want cloud accuracy? Bring your own Groq or OpenAI key, or point it at a local server like LM Studio. Keys stay in your keychain, no backend.

We used REA to map how Wispr Flow behaves and then built our own clean implementation. MIT licensed, good first issues are up.

https://github.com/1labs-ai/infinity-flow
```

## WhatsApp: PMs

```
Hi all, sharing a fun one from 1Labs.

We read user reviews and comments on AI dictation apps, clustered the complaints (privacy, $15/month, lost dictations, AI changing your words) and built *Infinity Flow* around fixing exactly those.

Private by default, no subscription, never loses a word, and AI cleanup that can't change your numbers. Full feature map and research are in the repo, good reference for how to turn reviews into a roadmap.

https://github.com/1labs-ai/infinity-flow
```

## WhatsApp: founders

```
Hi all, we just launched *Infinity Flow* at 1Labs. Open source voice dictation for Mac, built AI-Native.

Same day: AI agents mapped the market leader, mined user reviews for gaps, built a native Mac app with tests, and shipped it open source. Free forever on device, bring your own key for the cloud.

If you want to build an app or an AI-Native product for your business, reach out to us at 1Labs AI-Native Studio.

Repo: https://github.com/1labs-ai/infinity-flow
Book a call: https://1labs.ai/book-call
```

## LinkedIn

```
We built a voice dictation app for Mac in a day. Then we open sourced it.

Meet *Infinity Flow*. Hold fn, speak, release. Your words land in any app.

How we decided what to build:

1. Mapped how the market leader works with REA, a reverse engineering tool, using AI agents.
2. Read user reviews and comments and clustered the complaints: privacy, $12–15/month subscriptions, lost dictations, AI that changes your words.
3. Built the fix for each one:
   - Private by default. Transcribes on your Mac. No account, no server, no screenshots.
   - No subscription. Bring your own key if you want the cloud. About $2/month for heavy use, or free on Groq's tier.
   - Never loses a word. Every recording kept, retry from history, paste confirmation.
   - Your words, not the AI's. Cleanup that can't drop your numbers, original always one click away.
4. Native Swift. Around 28 MB of memory.

MIT licensed. Good first issues are ready if you want to contribute.

This is how we do product development at 1Labs now. AI-Native from day one.

If you want to build an app or an AI-Native product for your business, reach out to us at 1Labs AI-Native Studio.

Repo and booking link in the comments.

#OpenSource #AINative #BuildInPublic #macOS #VoiceAI
```

First comment: `Repo: https://github.com/1labs-ai/infinity-flow` and `Book a call: https://1labs.ai/book-call`

## X thread

1. We open sourced Infinity Flow: hold fn, speak, and your words land in any Mac app. Free, private by default, no subscription. 🧵
2. We read reviews of AI dictation apps first. The top complaints were cloud-only privacy, $12–15/month, lost dictations, and AI rewriting your words.
3. So it transcribes on your Mac by default, with no account and no server. Want the cloud? Bring your own Groq or OpenAI key. Heavy use costs about $2/month, or nothing on Groq's free tier.
4. It never loses a word. Every recording is kept, failed ones retry from History, and if no app takes the paste, the text stays on your clipboard.
5. AI polish can't change your numbers, and the original is always one click away. Native Swift, about 28 MB of memory. MIT: github.com/1labs-ai/infinity-flow

## Product Hunt

- **Name:** Infinity Flow
- **Tagline:** Private voice dictation for Mac: no subscription, never loses a word
- **Description:** Hold fn, speak, release, and your words appear in any app. Infinity Flow transcribes on your Mac by default, lets you bring your own Groq or OpenAI key instead of paying a subscription, keeps every recording until it's transcribed, and never lets AI change your numbers. Native, 28 MB, open source.
- **First comment:** why we built it (the review research), what's on device vs. cloud, and the roadmap (dictionary, snippets, per-app styles).
