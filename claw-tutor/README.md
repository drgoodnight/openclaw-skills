# 📚 claw-tutor

An interactive teaching skill for [OpenClaw](https://openclaw.ai) that turns any personal document library into a multi-learner tutoring system with semantic search, case-based discussions, MCQs, timed exams, and spaced repetition.

Feed it medical textbooks and it becomes a clinical tutor. Feed it law casebooks and it becomes a bar prep coach. Feed it AWS documentation and it becomes a cloud certification trainer. The teaching adapts to whatever's in the library.

## What It Does

**Teaching modes:**
- **Case-Based Discussion** — staged, interactive problem walkthroughs grounded in your documents. Presents a realistic situation, withholds key details, probes reasoning, evolves the scenario, then debriefs with source citations.
- **Problem Scenario** — time-pressured, decision-forcing simulations with distractors, ambiguity, and consequences.
- **MCQs** — exam-quality multiple choice (A–E) with immediate feedback, source references, and distractor explanations. Wait-for-answer before revealing.
- **Exam Mode** — timed MCQ sets with no feedback until the end. Simulates real exam conditions.
- **Topic Overview** — structured summary of what's in the library on a given topic.

**Multi-learner support:**
- Automatic identification by messaging platform identity (WhatsApp, Telegram, etc.)
- Named profiles with cross-platform identity linking
- Per-learner progress tracking, score history, and session logs
- Admin role for cohort management and aggregate reporting

**Spaced repetition (SM-2):**
- Tracks performance per topic with adaptive review intervals
- Proactively suggests topics due for review
- Recommends what to study next based on: overdue → weak → unstudied

**Document handling:**
- Indexes PDF, EPUB, PPTX, DOCX, DOC, ODT, RTF, HTML, CSV, TSV, Markdown, plain text, reStructuredText, Org-mode, and LaTeX
- Paragraph-aware chunking with table format stripping
- Semantic search via local embeddings (Ollama + nomic-embed-text)
- Vector storage in Qdrant
- Image/diagram detection — flags sources with visual content the agent can't display

## Architecture

```
Your Documents  →  index-library.sh  →  Ollama (embeddings)  →  Qdrant (vectors)
                                                                       ↓
    Agent  ←  SKILL.md (protocol)  ←  search-library.sh  ←────────────┘
                                                                       
    Learner progress  →  student.sh / session.sh / srs.sh  →  JSON files per learner
```

Everything runs locally. No data leaves your machine.

## Requirements

- Linux VPS (Ubuntu 20.04+ / Debian 11+)
- Docker
- Ollama
- System packages: `curl`, `jq`, `bc`, `poppler-utils` (pdftotext), `pandoc`
- ~1–2 GB RAM minimum (4+ GB if also running the OpenClaw gateway + LLM)

## Installation

### 1. Copy the skill to your VPS

```bash
scp -r claw-tutor user@your-vps:~/claw-tutor
```

### 2. Run the setup script

```bash
ssh user@your-vps
bash ~/claw-tutor/scripts/setup-vps.sh
```

The setup script is interactive and idempotent (safe to re-run). It will:

- Install all system dependencies
- Install Docker and pull the Qdrant image
- Install Ollama and pull the embedding model
- Copy the skill into `~/.openclaw/skills/claw-tutor/`
- Configure `openclaw.json` (with diff preview and backup)
- Register you as admin with your messaging ID

### 3. Upload your documents

```bash
scp ~/path/to/your/documents/* user@your-vps:~/documents/teaching-library/
```

Organise by topic using folders:

```
teaching-library/
├── Contract Law/
│   ├── casebook-ch1.pdf
│   └── offer-acceptance-notes.docx
├── Tort Law/
│   ├── negligence-overview.pdf
│   └── duty-of-care.pptx
└── legal-reasoning-guide.epub
```

**Topic derivation:**
- Files in a subfolder → topic = folder name (`Contract Law/` → "Contract Law")
- Files at root level → topic = filename without extension
- Nested subfolders use the top-level folder name

### 4. Index the library

```bash
bash ~/.openclaw/skills/claw-tutor/scripts/index-library.sh \
  ~/documents/teaching-library \
  ~/.openclaw/claw-tutor-data
```

Run this via SSH, not through the agent — indexing takes a few minutes and the agent's exec timeout will kill it.

To rebuild the index after adding new documents:

```bash
bash ~/.openclaw/skills/claw-tutor/scripts/index-library.sh \
  ~/documents/teaching-library \
  ~/.openclaw/claw-tutor-data \
  --reindex
```

### 5. Verify

Message your agent on Telegram/WhatsApp:

```
tutor status
```

```
what topics do you have?
```

## Usage

Talk to your agent naturally. Examples:

| What you say | What happens |
|---|---|
| `what topics do you have?` | Lists indexed topics with source counts |
| `teach me about contract law` | Case-based discussion on contract law |
| `quiz me on negligence` | 5 interactive MCQs on negligence |
| `exam mode - 10 questions on tort law` | Timed exam, no feedback until the end |
| `give me a scenario on offer and acceptance` | Decision-forcing problem simulation |
| `overview of my library` | Summary of all topics and coverage |
| `what should I study next?` | SRS-based recommendation |
| `what's due for review?` | Topics due for spaced repetition |
| `how am I doing on contract law?` | Score history and trend |
| `show my progress` | Overall progress report |
| `register student Alice` | Register a new learner |
| `cohort report` | Admin view of all learners (admin only) |
| `index my library` | Re-index documents (run via SSH instead) |
| `tutor status` | Infrastructure and index health check |

## File Structure

```
claw-tutor/
├── SKILL.md                        # Agent protocol
├── README.md                       # This file
└── scripts/
    ├── index-library.sh            # Extract, chunk, embed, store
    ├── embed-and-store.sh          # Batch embedding engine
    ├── search-library.sh           # Semantic search (single + multi-query)
    ├── list-topics.sh              # Topic listing
    ├── student.sh                  # Learner management + admin roles
    ├── session.sh                  # Session logging
    ├── srs.sh                      # Spaced repetition (SM-2)
    ├── manage-infra.sh             # Qdrant Docker lifecycle
    └── setup-vps.sh                # One-shot VPS setup
```

## Data Layout

```
~/.openclaw/claw-tutor-data/
├── qdrant-storage/                 # Vector database (Docker volume)
├── topic-registry.json             # Indexed topics and sources
└── students/
    ├── _identity-map.json          # Messaging ID → learner slug
    ├── _admin.json                 # Admin list
    ├── dr-smith/
    │   ├── profile.json            # Name, registration date, preferences
    │   ├── sessions.json           # Timestamped session log
    │   ├── scores.json             # Topic → score history
    │   └── srs-queue.json          # Spaced repetition schedule
    └── alice/
        └── ...
```

The knowledge base (vectors, topic registry) is shared. Progress data is per-learner.

## Configuration

In `~/.openclaw/openclaw.json`:

```jsonc
{
  "skills": {
    "entries": {
      "claw-tutor": {
        "enabled": true,
        "config": {
          "libraryPath": "/home/user/documents/teaching-library",
          "dataDir": "/home/user/.openclaw/claw-tutor-data"
        }
      }
    }
  }
}
```

## Supported File Types

| Format | Extensions | Extraction |
|---|---|---|
| PDF | `.pdf` | pdftotext |
| EPUB | `.epub` | pandoc |
| PowerPoint | `.pptx` | pandoc |
| Word (new) | `.docx` | pandoc |
| Word (old) | `.doc` | pandoc |
| LibreOffice Writer | `.odt` | pandoc |
| Rich Text | `.rtf` | pandoc |
| HTML | `.html`, `.htm` | pandoc |
| CSV / TSV | `.csv`, `.tsv` | direct |
| reStructuredText | `.rst` | pandoc |
| Org-mode | `.org` | pandoc |
| LaTeX | `.tex`, `.latex` | pandoc |
| Markdown | `.md` | direct |
| Plain text | `.txt` | direct |

## License

MIT
