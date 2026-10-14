# Sylvia

**Your library of thought.**

Sylvia is a reading, listening and knowledge system in development, with a long-term vision of working across all major operating systems. It brings books, highlights, audio moments, notes and questions into one lasting, searchable record—so what you learn stays with you, even after you remove the original files.

The full vision combines mobile, desktop and web clients with a **Docker-containerized service** that powers library hosting, content ingestion and background processing. Native iPhone/iPad development is the first step toward that broader system.

## Why Sylvia

What we're building:

- **Keep what matters.** Preserve quotes, notes, audio excerpts and reading history after removing a downloaded book or audiobook.
- **Capture without losing your place.** Save a passage or audio moment, add your thinking and return to reading or listening.
- **Keep the source close.** Connect each saved thought to its work, edition, chapter, page or timestamp, with a way back when the source is available.
- **Ask questions in context.** Explore a passage with an optional AI provider you choose. Keep the question, answer and supporting evidence together, with generated explanations clearly distinguished from quotations.
- **Own your library.** Read and listen offline without a mandatory account or server. Export your retained knowledge, and choose what context you share with AI.

## The long-term vision

**Your library across operating systems.** The goal is support across iOS/iPadOS, Android, macOS, Windows and Linux, with a web reader for browser access. Books and the knowledge you retain from them should remain portable as you move between devices and platforms.

**A Docker service to power the system.** A self-hostable, always-on service will provide shared infrastructure for the clients: hosting a large media library, collecting files and saved articles, refreshing feeds, indexing content and running background processing. It will deliver content to connected clients while the clients retain their own offline reading, listening and capture experience.

Local-first remains a core principle: the Docker service powers the connected system, while standalone use on one device remains possible without running a server.

## Design samples

Concept designs in **Marginalia**, Sylvia's visual language: warm paper, readable typography and distinct treatments for quotations, personal notes, audio and generated answers.

<table>
  <tr>
    <td align="center"><img src="Docs/Design/images/Reader.png" alt="Reader concept showing a highlighted passage and actions to highlight, annotate, look up or ask" width="250"><br><sub>Read and annotate</sub></td>
    <td align="center"><img src="Docs/Design/images/Player.png" alt="Audiobook player concept with playback controls and a saved audio excerpt" width="250"><br><sub>Listen and capture</sub></td>
    <td align="center"><img src="Docs/Design/images/Thoughts.png" alt="Thoughts concept bringing searchable quotations, notes, audio excerpts and generated answers together" width="250"><br><sub>Return to what you learned</sub></td>
  </tr>
</table>

[Explore the full design gallery](Docs/Design/README.md), including dark mode, iPad, the Mac companion and grayscale studies.

## Where we're headed

**First: native iOS V1.** EPUB/PDF reading, local audiobook playback, durable capture, optional contextual AI, a permanent reading and listening record, and a lightweight Mac companion for importing your files. English and DRM-free content come first.

**Beyond V1:** build out the Docker service, web reader and clients for additional operating systems, alongside saved articles, feeds and broader capture options. These long-term goals follow the first native release.

## Project status

Sylvia is in design and feasibility development; there is no released app yet. The main branch contains the product plans and concept designs. Native feasibility prototypes and their evidence are maintained separately on [m0-integrate](https://github.com/jevidon/sylvia/tree/m0-integrate).

- [Product brief](Docs/Sylvia_Product_Brief.md) — the problem, audience and product vision.
- [Implementation plan](Docs/Sylvia_v1_iOS_Implementation_Plan.md) — V1 scope, milestones, acceptance criteria and roadmap.
- [Companion vision](Docs/Sylvia_Companion_Vision_Architecture_Addendum.md) — the longer-term direction for learning beyond files stored in Sylvia.
