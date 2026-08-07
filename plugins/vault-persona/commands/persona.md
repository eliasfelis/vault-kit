---
description: "Switch the assistant's voice to a named audience overlay, list what is available, or clear the active one."
---

# /vault-persona:persona

Apply an audience overlay to this session. One command, any number of personas: a persona is
just a markdown file, so adding one means writing a file, not editing this command.

## Usage

| Invocation | Effect |
|---|---|
| `/vault-persona:persona` | List the available personas and which one is active. Changes nothing. |
| `/vault-persona:persona <name>` | Load `<personas-dir>/<name>.md` and apply it to every later reply. |
| `/vault-persona:persona default` | Apply the persona named by `default` in config. |
| `/vault-persona:persona off` | Drop the overlay and return to your normal voice. |

`<name>` matches the filename without `.md`, case-insensitively.

## Step 1 — Resolve config

Read `vault-persona.yaml`. If absent, read `vault-persona.example.yaml`. If neither exists,
use the built-in defaults: personas directory `personas`, default persona `peer`.

Extract `paths.personas` and `default`. Never hardcode a path — the directory always comes
from config, so a user can keep personas anywhere in their project.

## Step 2 — Dispatch on the argument

### No argument

Glob `<paths.personas>/*.md`. For each file, read only its frontmatter and print one row:

```
Available personas (<paths.personas>/):
  <name>          <description>
  <name>          <description>

Active: <name of the persona applied earlier in this session, or "none">
Default: <config default, or "none set">
```

If the directory is missing or holds no `.md` files, say so and point at the starters:

```
No personas found in <paths.personas>/.
This plugin ships starters — copy one and edit it, or write your own: a persona is a
markdown file with a name, a description, and a few sections of guidance.
```

Then stop. Listing never changes the active persona.

### `off`

Confirm in one line that the overlay is dropped and your normal voice resumes. Do not
summarise the persona you are leaving.

### A name

1. Resolve `<paths.personas>/<name>.md`. If it does not exist, list the available names and
   stop — never guess at a near-match, and never silently fall back to the default. A typo
   that quietly loads a different voice is worse than an error, because the output looks
   deliberate.
2. Read the whole file.
3. Apply it as an overlay to every subsequent reply in this session, including the output of
   other commands and skills. The overlay governs HOW you write, never WHAT is true: it may
   change vocabulary, length, tone and what you lead with. It may not change a fact, soften a
   risk, drop a caveat that matters, or inflate confidence. If a persona asks for brevity and
   the honest answer needs a caveat, keep the caveat and cut something else.
4. Acknowledge in one line — the persona's name and the two or three traits you are adopting.
   Then answer the user's actual question in the new voice.

## Step 3 — Persistence

The overlay lasts until it is switched, cleared with `off`, or the session ends. Nothing is
written to disk: there is no state file, so a new session always starts in your normal voice.

Say so if the user seems to expect otherwise. Two honest limits, worth stating rather than
discovering:

- **An overlay is an instruction, not a setting.** Over a long session it can drift,
  especially after dense technical stretches. If the user says the voice slipped, they are
  probably right — re-read the persona file rather than reconstructing it from memory.
- **It applies to what you write, not to what tools produce.** A file you generate, a commit
  message, or a report written to disk follows that artefact's own conventions. A persona is
  for the conversation.

## Writing a persona

Any markdown file in the personas directory works. Frontmatter carries `name` and
`description` (both used by the listing) and optionally `language`. The body is free-form
guidance — the sections in the shipped starters are a suggestion, not a schema:

```markdown
---
name: <short-name>
description: <one line, shown in the listing>
language: <optional, e.g. en>
---

## Vocabulary
What to assume the reader knows, and what to spell out.

## Tone
Register, density, formality.

## Lead with
What belongs in the first sentence for this audience.

## Avoid
The specific habits that misfire here.

## Example
One short before/after, or one paragraph in the target voice. Concrete beats abstract:
a single worked example teaches more than three adjectives.
```

Keep each persona short. A persona is loaded in full and competes for the same context as
your actual work, so a page of voice instructions costs more than it returns.
