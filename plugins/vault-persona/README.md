# vault-persona

Switch your assistant's voice for a target audience. A persona is a markdown file, so adding
one means writing a file — not editing a command, not touching config.

Same work, different reader: the answer that helps a fellow engineer is the wrong answer for
someone deciding a budget, and both are wrong for a reader who does not know the vocabulary.
This plugin makes that switch explicit and repeatable instead of something you re-improvise
in every prompt.

## Install

```
/plugin marketplace add eliasfelis/vault-kit
/plugin install vault-persona@vault-kit
```

## Use

| Command | Effect |
|---|---|
| `/vault-persona:persona` | List available personas and which one is active |
| `/vault-persona:persona <name>` | Apply that persona to the rest of the session |
| `/vault-persona:persona default` | Apply the persona named in config |
| `/vault-persona:persona off` | Return to your assistant's normal voice |

Copy `vault-persona.example.yaml` to `vault-persona.yaml` if you want personas kept somewhere
other than `personas/`, or a different default. With no config file the defaults apply, so
the plugin works immediately after install.

## What ships

Three starters in `personas/`, written as worked samples rather than defaults — read them,
keep what fits, rewrite the rest:

| Persona | For |
|---|---|
| `executive` | Decision-first, outcome language, no implementation detail |
| `non-technical` | Plain language with analogies, jargon explained on first use |
| `peer` | Full technical density, tradeoffs first, no hand-holding |

## Writing your own

Any `.md` file in the personas directory. Frontmatter carries `name` and `description` (the
listing reads both); the body is free-form guidance. The starters use Vocabulary / Tone / Lead
with / Avoid / Example — a suggestion, not a schema.

Two things that make a persona work:

- **One concrete example beats three adjectives.** "Be concise" is nearly useless; a short
  before-and-after pair is unambiguous. Every starter here ends with one.
- **Say what to avoid, specifically.** The habits that misfire for an audience are more
  actionable than the qualities you want, because they are recognisable in a draft.

Keep each persona short. It is loaded in full and competes for the same context as your
actual work.

## What this does not do

- **It governs how you write, not what is true.** A persona may change vocabulary, length and
  what you lead with. It may not drop a caveat that matters, soften a real risk, or inflate
  confidence. Brevity comes out of some other sentence.
- **It is an instruction, not a setting.** Nothing is written to disk and no state persists:
  a new session starts in the assistant's normal voice. Within a long session the overlay can
  drift, and re-applying it is the fix.
- **It applies to conversation, not to artefacts.** Files, commit messages and reports follow
  their own conventions. A persona is for what the assistant says to you.

## License

[MIT](../../LICENSE)
