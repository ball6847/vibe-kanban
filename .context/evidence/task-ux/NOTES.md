# Evidence — the local task UX, driven by the `agent-browser` CLI

`./check.sh` section 8 replays every step below in a real browser (session
`vibe-goal-check`, `--args "--no-sandbox"`), asserts the DOM and the API, and writes these
screenshots into this directory. They are committed, so a run that later breaks shows up as
a changed image.

| Screenshot | Claim it proves |
| --- | --- |
| `01-board.png` | the project board renders the seeded task card |
| `02-task-detail-panel.png` | clicking a card selects the task (URL becomes `/projects/<projectId>/issues/<taskId>`) and opens the detail panel, which survives a reload and closes on `Escape` |
| `03-create-from-task.png` | the panel's workspace action opens the create flow prefilled from the task |
| `04-task-detail-workspace.png` | the panel shows the task's single linked workspace with its open action |
| `05-board-with-status.png` | the board after the flow, with the card in its automated status |

Assertions that ride along with the screenshots: editing the title and the description in the
panel persists (`GET /api/tasks?project_id=`), the created workspace carries the task id, a
second create does not duplicate it (1:1), the task's status advances by itself to
`inprogress`, `/` and `c` focus the filter and the new-task input, filtering narrows the board
to the matching card, and a bulk move advances two selected tasks.

Fixtures (repo, project, task, workspace) are created and deleted by the gate on every run.
