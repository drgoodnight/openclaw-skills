# OpenClaw Skills by Cypherdoc

A collection of production-grade OpenClaw skills focused on **analytical depth** and **educational rigor**, built by a critical care physician who thinks in systems.

---

## What's Here

### 🩺 **claw-tutor** – Personal Document Tutoring System
Transforms your document library into an interactive teaching environment with semantic search, case-based discussions, MCQs, and spaced repetition learning.

**Architecture:**
- Semantic vector search via Qdrant + Ollama embeddings
- Multi-format document ingestion (PDF, DOCX, MD, TXT)
- Four learning modes: exploration, case discussion, MCQ testing, spaced repetition
- Stateful progress tracking per user

**Designed for:** Medical education materials, technical references, protocol libraries, any dense domain knowledge you need to actually retain.

**Status:** Production. Running on personal VPS with medical critical care protocols and DKA guidelines.

---

### 🔍 **pressure-framework** – Narrative & Information Operations Analysis
Six-phase analytical framework for detecting manufactured pressure patterns in social media and information ecosystems.

**Architecture:**
- SORAM: Social media sentiment mapping
- PRISM: Pressure/Reality/Influence/Sentiment/Momentum decomposition
- NARCS: Narrative arc structural analysis
- TRAP-N: Tactic/Reach/Authenticity/Persistence network mapping
- FATE: Factual/Assumptive/Tendentious/Emotive classification
- 6-Axis: Multi-dimensional position mapping

**Core principle:** *You don't predict events — you predict pressure.* The diagnostic question is always: Is this solving a problem, or teaching people to adapt to one?

**Status:** Production. Operational for real-time social media narrative analysis.

---

## Design Philosophy

These skills follow **architecture-first, not code-first** principles:

- **Clinical protocol structure** – Clear trigger conditions, step-by-step actions, error handling, escalation paths
- **Robust error handling** – Retry logic, graceful degradation, human-in-the-loop checkpoints
- **Domain-agnostic design** – Generalizable frameworks that scale beyond their initial use case
- **Production-ready** – Not demos. These run on real systems with real users.

Skills are **not coding exercises** – they're structured instructions that teach an intelligent agent how to execute complex workflows. Think of SKILL.md as a **procedure manual**, not a script.

---

## Installation

### Prerequisites
- OpenClaw installed and configured ([github.com/openclaw/openclaw](https://github.com/openclaw/openclaw))
- For **claw-tutor**: Qdrant, Ollama, pandoc, various document processors
- For **pressure-framework**: Standard bash utilities, jq

### Via ClawHub (when published)
```bash
clawhub install claw-tutor
clawhub install pressure-framework
```

### Manual Installation
```bash
# Clone to your OpenClaw skills directory
cd ~/.openclaw/skills
git clone https://github.com/drgoodnight/openclaw-skills
ln -s openclaw-skills/claw-tutor .
ln -s openclaw-skills/pressure-framework .
```

Configure in `openclaw.json`:
```json
{
  "skills": {
    "entries": {
      "claw-tutor": {
        "enabled": true,
        "env": {
          "QDRANT_URL": "http://localhost:6333",
          "OLLAMA_URL": "http://localhost:11434"
        }
      },
      "pressure-framework": {
        "enabled": true
      }
    }
  }
}
```

---

## Usage Patterns

### Claw-Tutor
```
/claw-tutor setup
/claw-tutor search "DKA management fluid resuscitation"
/claw-tutor case discuss septic shock
/claw-tutor test generate MCQs on vasopressor selection
/claw-tutor review show due items
```

### Pressure-Framework
```
/pressure-framework analyze <url or text>
/pressure-framework detect pressure patterns in recent AI safety discourse
```

---

## Deployment Notes

**Architecture decisions:**
- Both skills tested on Ubuntu VPS (atlas-01)
- Claw-tutor vector DB persistence via Qdrant collections
- Considering dedicated bot instances for isolated use cases (e.g., student-only tutoring access)

**Migration path:**
- Skills built on legacy OpenClaw config, migrated to current version
- Robust handling for API rate limits, malformed input, document processing errors
- Use temporary files for complex JSON payloads to avoid bash quoting hell

---

## Contributing

These skills are **production systems in active use**. If you're building something similar or want to extend these frameworks:

1. **Understand the system boundary first** – What dependencies? What failure modes? What's the blast radius?
2. **Test the SKILL.md by talking to it** – The agent reads natural language instructions. Write them like clinical protocols.
3. **Gate aggressively** – Use `metadata.openclaw.requires` to prevent broken states.
4. **Keep token budgets tight** – Every skill costs ~97 chars + field lengths in the agent's prompt.

PRs welcome for:
- Additional analytical phases for pressure-framework
- New learning modes for claw-tutor
- Cross-platform compatibility improvements
- Documentation of deployment patterns

---

## Acknowledgments

Built on the **OpenClaw** platform by the team at [openclaw.ai](https://openclaw.ai).

Analytical frameworks informed by years of critical care decision-making, systems thinking, and pattern recognition in high-stakes environments.

---

## License

MIT – use these however helps you think better.

---

*"A good skill is like a good protocol: clear enough that the person following it can act decisively, structured enough to handle the unexpected, and short enough that it actually gets read."*