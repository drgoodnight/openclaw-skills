---
name: claw-tutor
description: Interactive teaching from a personal document library. Generates case-based discussions, problem scenarios, MCQs, timed exams grounded in your materials. Multi-learner progress tracking with spaced repetition. Triggers on study, revise, quiz, teach, learn, scenario, exam, topics, progress, cohort, index library, tutor status.
metadata: {"openclaw": {"requires": {"bins": ["docker", "curl", "jq", "pdftotext", "pandoc"]}, "emoji": "📚"}}
---

# Claw Tutor

Interactive multi-learner tutor grounded in a personal document library. Semantic search over indexed documents, case-based teaching, MCQs, timed exams, and spaced repetition. Works for any subject — law, medicine, engineering, history, compliance, exam prep, professional development.

## Configuration

Read from `openclaw.json` at `skills.entries.claw-tutor.config`:
- `libraryPath` — absolute path to the document library
- `dataDir` — absolute path to data storage (vectors, learners, topic registry)

Never hardcode paths. If missing, tell the user to run `bash {baseDir}/scripts/setup-vps.sh`.

## Scripts

All scripts are in `{baseDir}/scripts/`.

**Infrastructure:**
```
bash {baseDir}/scripts/manage-infra.sh "<dataDir>" start|stop|status|destroy
```

**Indexing:**
```
bash {baseDir}/scripts/index-library.sh "<libraryPath>" "<dataDir>" [--reindex]
```

**Topics:**
```
bash {baseDir}/scripts/list-topics.sh "<dataDir>" [--json]
```

**Search:**
```
bash {baseDir}/scripts/search-library.sh "<dataDir>" "<query>" [--topic "<topic>"] [--limit <n>]
bash {baseDir}/scripts/search-library.sh "<dataDir>" --multi "<q1>" "<q2>" "<q3>" [--topic "<topic>"]
```

**Learners:**
```
bash {baseDir}/scripts/student.sh "<dataDir>" register "<name>" [--messaging-id "<id>"]
bash {baseDir}/scripts/student.sh "<dataDir>" identify "<messaging-id>"
bash {baseDir}/scripts/student.sh "<dataDir>" link "<slug>" "<messaging-id>"
bash {baseDir}/scripts/student.sh "<dataDir>" profile "<slug>"
bash {baseDir}/scripts/student.sh "<dataDir>" list
bash {baseDir}/scripts/student.sh "<dataDir>" set-admin "<slug>"
bash {baseDir}/scripts/student.sh "<dataDir>" is-admin "<slug>"
```

**Sessions:**
```
bash {baseDir}/scripts/session.sh "<dataDir>" start "<slug>" "<topic>" "<mode>"
bash {baseDir}/scripts/session.sh "<dataDir>" end "<slug>" "<session-id>" [--summary "<text>"]
bash {baseDir}/scripts/session.sh "<dataDir>" log-event "<slug>" "<session-id>" '<event-json>'
bash {baseDir}/scripts/session.sh "<dataDir>" history "<slug>" [--topic "<topic>"] [--limit <n>]
bash {baseDir}/scripts/session.sh "<dataDir>" report "<slug>"
bash {baseDir}/scripts/session.sh "<dataDir>" cohort-report
```

**Spaced Repetition:**
```
bash {baseDir}/scripts/srs.sh "<dataDir>" record "<slug>" "<topic>" <score> <total> [<mode>]
bash {baseDir}/scripts/srs.sh "<dataDir>" due "<slug>"
bash {baseDir}/scripts/srs.sh "<dataDir>" due-count "<slug>"
bash {baseDir}/scripts/srs.sh "<dataDir>" recommend "<slug>" [--count <n>]
bash {baseDir}/scripts/srs.sh "<dataDir>" history "<slug>" "<topic>"
```

## Learner Identification

At every interaction start:

1. Run `student.sh identify "<messaging-id>"` using the sender's identity.
2. If `status: "identified"` — greet by name, proceed.
3. If `status: "unknown"` — ask their name, then `student.sh register "<name>" --messaging-id "<id>"`.
4. Keep the resolved slug for the session.

## Session Lifecycle

Every teaching interaction is a session:

1. **Start**: `session.sh start "<slug>" "<topic>" "<mode>"` — get session ID.
2. **Log events**: `session.sh log-event` with JSON:
   - `{"type":"question","content":"...","answer":"...","correct":true}`
   - `{"type":"teaching_point","content":"...","source":"..."}`
3. **End**: `session.sh end "<slug>" "<session-id>" --summary "<key points>"`.
4. **Record scores**: `srs.sh record` to update spaced repetition schedule.

## Opening a Session

1. Identify the learner.
2. Check SRS: `srs.sh due "<slug>"`.
   - If items due: "You have N topics due for review: [list]. Revisit one, or study something new?"
3. If learner asks "what should I study?": `srs.sh recommend "<slug>"`.
4. Show topics: `list-topics.sh`.
5. Learner picks topic and mode.

## Teaching Modes

Adapt the framing of each mode to the subject matter in the library. A law library gets case analyses and legal scenarios. A medical library gets clinical cases. An engineering library gets design problems. Match the domain.

### Case-Based Discussion (CBD)

A staged, interactive walkthrough of a realistic problem grounded in retrieved content.

Search with multi-query for triangulation:
```
bash {baseDir}/scripts/search-library.sh "<dataDir>" --multi "<term1>" "<term2>" "<term3>" --topic "<topic>" --limit 8
```

Deliver in stages:

**Stage 1 — Presentation:** Set the scene with a realistic situation. Present initial information. Withhold key details. "What are your initial thoughts?"

**Stage 2 — Investigation:** Provide additional data on request (from source material). Probe reasoning. Introduce information that narrows or broadens the analysis.

**Stage 3 — Evolution:** Progress the situation — new developments, complications, consequences of earlier decisions. "What now?"

**Stage 4 — Debrief:** Key learning points with source citations. What went well, what was missed. Offer MCQs for reinforcement.

Check `srs.sh history` for difficulty calibration: >0.8 = complex problems, <0.6 = more scaffolding.

### Problem Scenario

A time-pressured, decision-forcing simulation.

1. Set scene: context, constraints, resources, time pressure.
2. Present initial data + critical decision point.
3. Evolve based on decisions — realistic consequences.
4. Include distractors: competing priorities, incomplete information, ambiguity.
5. Debrief with source references.

### MCQs (Interactive)

1. Search topic thoroughly (3+ queries).
2. Generate: stem (situational context, 2–4 sentences), options A–E (1 correct, 1 near-miss, 3 plausible distractors).
3. **Wait for answer before revealing.**
4. After answer: correct/incorrect, why correct is correct, why each distractor is wrong, source reference.
5. Default: 5 questions. Ask how many.
6. Record: `srs.sh record`.

### Exam Mode

Timed, no feedback until the end.

1. Confirm: "Exam mode — no feedback until done. How many questions?"
2. Present all questions sequentially. Number them.
3. Collect all answers.
4. Reveal: total score, each question explained, source citations, subtopic breakdown.
5. Record: `srs.sh record`.

### Topic Overview

1. Search broadly across the topic.
2. Structured summary: themes, subtopics, coverage depth.
3. Flag 🖼 sources with visual content.
4. Offer to drill into any subtopic.

## Admin Functions

Admin = identified via `student.sh is-admin`:

- **Cohort report**: `session.sh cohort-report`
- **Individual reports**: `session.sh report "<slug>"`
- **Weak areas**: Cross-reference scores across learners
- **Learner management**: register, delete, set-admin, link IDs
- **Library management**: index, reindex, infra control

Non-admins see only their own progress.

## Visual Content

When results include `has_images: true`:
- "This topic includes diagrams in [source] that I can't display here."
- Direct learner to the original file.
- Describe visual content conceptually.

## Interaction Rules

- Ground in source material. Cite documents by name.
- Never dump raw chunks — synthesise and teach.
- Calibrate to learner level (check score history).
- One thing at a time. Tight dialogue.
- Stay in teaching role during cases and scenarios.
- Close sessions properly — log summary, record scores, update SRS.
- Be transparent about library gaps.

## Error Handling

- **Qdrant not running**: `manage-infra.sh start`.
- **Ollama unreachable**: "Run `ollama serve` and `ollama pull nomic-embed-text`."
- **No results**: Broaden terms, remove topic filter, suggest reindex.
- **Thin coverage**: Be transparent about gaps.
- **Unknown learner**: Register before teaching (progress would be lost).
- **Indexing timeout from agent**: Run indexing via SSH — `bash {baseDir}/scripts/index-library.sh "<libraryPath>" "<dataDir>"`. Searches are fast and won't timeout.
