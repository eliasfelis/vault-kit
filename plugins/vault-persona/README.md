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

Nothing else to set up. The starters ship inside the plugin and are listed and activated from
there, so `/vault-persona:persona peer` works immediately after install — no config file, no
personas directory of your own, nothing copied.

## Use

| Command | Effect |
|---|---|
| `/vault-persona:persona` | List available personas and which one is active |
| `/vault-persona:persona <name>` | Apply that persona to the rest of the session |
| `/vault-persona:persona default` | Apply the configured default persona |
| `/vault-persona:persona off` | Return to your assistant's normal voice |

The listing merges your own personas directory with the starters shipped inside the plugin,
marking each row `user` or `starter`, and prints the directory it resolved.

`<name>` is the filename without `.md`, matched case-insensitively: `peer`, `Peer` and `PEER`
all resolve `peer.md`. Rules worth knowing before naming a file:

- **Your file wins.** A persona in your directory shadows a starter of the same name, and the
  starter is never loaded under that name.
- **`off` and `default` are reserved.** They are command arguments, so `off.md` and
  `default.md` can never be activated. The listing shows such a file as unreachable rather than
  offering it as available.
- **Same name, different case, same directory is an error.** With `Peer.md` beside `peer.md`,
  the command names them all and stops instead of guessing.
- **The name is not a path.** Names are letters, digits, spaces, hyphens and underscores;
  anything else — a dot, a slash, a leading separator — is rejected before resolution.

## What ships

The starters, in the plugin's own `personas/` directory, written as worked samples rather than
defaults — read them, keep what fits, rewrite the rest:

| Persona | For |
|---|---|
| `executive` | Decision-first, outcome language, no implementation detail |
| `non-technical` | Plain language with analogies, jargon explained on first use |
| `peer` | Full technical density, tradeoffs first, no hand-holding |

They live inside the plugin and are read-only — a reinstall regenerates that directory. To
change one, copy it into your own personas directory first, where it shadows the shipped
version:

```
cp "${CLAUDE_PLUGIN_ROOT}/personas/peer.md" personas/
```

`${CLAUDE_PLUGIN_ROOT}` resolves inside the plugin rather than in your own shell, so ask your
assistant to run that line — or take the expanded path from the listing, which prints it.

## Config (optional)

There is no config file until you want one. Create `vault-persona.yaml` at your project root to
override either key:

```yaml
paths:
  personas: "docs/voices"   # where your own persona files live
default: "executive"        # applied by `/vault-persona:persona default`
```

Omit a key to keep its built-in value. The built-ins are stated in the command spec
(`commands/persona.md`), which is their only home — this file deliberately does not repeat
them. Set `default: ""` if you would rather have no baseline and always name a persona
explicitly.

## Writing your own

Any `.md` file in your personas directory. Frontmatter carries `description`, the line the
listing prints; the name is the filename, not a frontmatter field. The body is free-form
guidance — the starters use Vocabulary / Tone / Lead with / Avoid / Example, a suggestion
rather than a schema.

What makes a persona work:

- **One concrete example beats three adjectives.** "Be concise" is nearly useless; a short
  before-and-after pair is unambiguous. Every starter here ends with one.
- **Say what to avoid, specifically.** The habits that misfire for an audience are more
  actionable than the qualities you want, because they are recognisable in a draft.

Close the file with the limits line the starters carry — voice only, no changing facts, machine
output verbatim. It is a reminder rather than a second rulebook: the full statement lives in
the command, and the reason a copy sits in every file is that the documented fix for a drifted
voice is re-reading the persona.

Keep each persona short. It is loaded in full and competes for the same context as your actual
work.

## Trust

A persona file is applied to your assistant as instructions. Read one before activating it, the
way you would read a script before running it — and in a shared repository, everyone with
commit access to the personas directory can shape how your assistant talks to you. The
command's limits hold regardless of what a file asks for: a persona sets voice, and an
instruction inside one that reaches beyond voice is declined and named rather than followed.
That is a boundary, not a sandbox.

## What this does not do

- **It governs how you write, not what is true.** A persona may change vocabulary, length and
  what you lead with. It may not drop a caveat that matters, soften a real risk, or inflate
  confidence. Brevity comes out of some other sentence.
- **It leaves machine-shaped output alone.** A ledger a consumer reads positionally, a status
  line whose prefix and counts are parsed, a JSON payload, quoted tool output — the overlay
  applies to the prose around such a block, never to the block. Where another command calls for
  output "verbatim", the persona yields.
- **It is an instruction, not a setting.** Nothing is written to disk and no state persists:
  a new session starts in the assistant's normal voice. Within a long session the overlay can
  drift, and re-applying it is the fix.
- **It applies to conversation, not to artefacts.** Files, commit messages and reports follow
  their own conventions. A persona is for what the assistant says to you.

## License

[MIT](../../LICENSE)
