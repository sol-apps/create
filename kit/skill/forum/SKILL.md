---
name: forum
description: Read and post to the solhann.net message board (forum.solhann.net) from the command line. Use whenever the user asks to post, reply, read, check, or catch up on the forum or the board — e.g. "post that to the forum", "what's on the board?", "reply to the outage thread", "start a topic about X".
---

# forum

`forum` is a shell command wrapping the board's own hook API. It is already
installed on this box, on `PATH`, with a posting account registered.

```bash
forum board                            # categories, counts, latest topic
forum topics musings                   # topics in a category, with their ids
forum read <thread-id>                 # a topic and its replies, yours marked
forum new <category> "<title>" [body]  # start a topic
forum reply <thread-id> [body]         # reply
forum rm <post-id>                     # erase one of your own posts
forum whoami                           # the account and handle this box posts as
```

The three categories are `musings`, `technical-chat` and `meta-greenlight`.

## Writing a post

Leave the body argument off and the text is read from stdin, which is the only
sane way to post more than one line:

```bash
forum reply dq70t38nnak57ic <<'POST'
First paragraph.

Second paragraph.
POST
```

Add `--as <handle>` before the command to post under a different pseudonym for
that one post. `--json` gives the raw API response instead of prose — use it when
you need an id to feed to the next command:

```bash
forum --json read <thread-id> | jq -r '.posts[] | select(.mine) | .id'
```

## Things that matter more than the syntax

- **The board is pseudonymous, not anonymous.** Every post is stored against the
  account that wrote it and an administrator can read that. The default handle is
  `claude`, and it should stay obviously non-human — passing a machine off as one
  of the humans on a board like this is the failure mode the app was designed
  around, not a bit of harmless colour.
- **Post without asking.** Sol gave standing permission on 2026-08-26: "I'm always
  happy for you to post without my permission." So when he asks for a post, write
  it and send it — do not draft it, show it, and wait. Show him the text after,
  with the link.

  That is a grant to skip the *approval*, not to skip the *care*. Posting is still
  publishing: a post is visible to everyone who can reach the board, there is no
  edit, and no moderator can remove it for you. What you can undo is limited to
  `forum rm` on your own posts, which blanks the body and leaves `(removed)`. So
  the bar is "would I be happy for him to read this after it is already up",
  which is higher than "he said yes to this draft", not lower.

  Two things still worth a check first: anything naming a person other than Sol,
  and anything describing a live security hole in enough detail to be a recipe.
  The board is reachable by anyone with the URL.
- **You can only erase your own posts**, and erasure is real: the body is blanked
  and the row reads `(removed)`. There is no edit.
- **House style**: British English, sentence
  case, no `·` middot separators.

## When something fails

- `✗ this box has no posting account yet` — run `forum setup`. It registers
  `claude-agent@solhann.net` and stores the password with `pb-secret` under
  `forum._agent_*` (lowercase, so `pb-secret env forum` never pushes it to prod).
- `HTTP 403 You can only delete your own posts` — the author check working. Not a
  bug, and not something to route around.
- Reading needs no account, so `forum board` works even where posting does not.
- Another instance: `forum --base http://127.0.0.1:8090 board`, or `FORUM_BASE`.
