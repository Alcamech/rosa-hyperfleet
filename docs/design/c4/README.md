# ROSA Seaplane C4 model

A [C4 model](https://c4model.com/) of a single, self-contained ROSA Seaplane region, authored as
code with the [Structurizr DSL](https://docs.structurizr.com/dsl). There is **one model** (the C4
best practice) split across several files for maintainability.

This is a fresh start at **System Context** level: ROSA Seaplane as a single box, its people, and
the external systems it talks to. Container, component, dynamic and deployment views were removed
and will be rebuilt incrementally on top of this.

## Layout

```
workspace.dsl                 # top-level: wires the model + views together
model/
  people-external.dsl         # people (End User, SRE) + external systems
  relationships.dsl           # relationships (currently System Context level)
views/
  structure.dsl                # System Context view
  styles.dsl                   # element + relationship styling (incl. tags not yet used)
```

## The current view

| View            | What it shows                                                 |
| --------------- | -------------------------------------------------------------- |
| `SystemContext` | Seaplane as one system, its people and the external systems |

As the model grows, containers go back into `model/` (likely split one file per AWS account, as
before) and new views go into `views/`, following the same `!include` pattern.

## Rendering

The model is the single source of truth; diagrams are generated from it. Everything runs in
containers, so the only host dependency is a container engine (podman by default; override with
`make ENGINE=docker ...`). No JDK, Node or local Chrome required.

```bash
make            # export PlantUML from the DSL, then render every view to SVG
make png        # also render PNGs
make export     # DSL -> one structurizr-<View>.puml per view (no images)
make mermaid    # export Mermaid (.mmd) for embedding one view into a markdown doc
make lite       # serve interactive Structurizr Lite at http://localhost:8080
make clean      # remove generated .puml / .mmd / .svg / .png
```

**Why PlantUML, not Mermaid.** Rendering is PlantUML + Graphviz, which gives proper nested C4 group
boxes and legible edges once the model grows past a handful of elements. Mermaid auto-layout
produces an unreadable hairball for a model of any size, so it is kept only as the opt-in
`make mermaid` target for embedding a single small view into a markdown ADR (the repo's
Mermaid-for-diagrams convention). SVG is the default because it is zoomable.

Notes for anyone editing the DSL: nested `group` blocks require the `structurizr.groupSeparator`
model property (already set, multi-line), hierarchical identifiers forbid dots inside an id (the dot
is the hierarchy separator), and no `theme` is referenced because the hosted theme CDN is being
retired.
