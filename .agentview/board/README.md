# Agent View — Session Board bridge

This folder bridges Claude Code agents and the Agent View **Session Board**.
It is written/read by both the extension and your agents.

## Read what the user pointed at
`selection.json` (also at `$AGENTVIEW_BOARD_DIR/selection.json`) holds the
board objects the user selected for you — an episode's prompt, a plan, a
commit, a model note, an evidence chip. They are the *referent* of the user's
instruction: treat "this" in their message as meaning these objects.

## Notify the user of a result
Write `inbox/<id>.json` and the user gets a notification. Write it
**atomically** (a bare write can be read half-finished):

```sh
echo '{ ... }' > inbox/result-1.json.tmp
mv inbox/result-1.json.tmp inbox/result-1.json
```

Intent shape:

```json
{ "type": "result", "title": "short title", "body": "markdown body" }
```

Your session's own work needs no posting — the Session Board materializes it
live from the transcript (plans, commits, evidence, notes).
