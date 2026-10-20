# Renders the Structurizr C4 model to readable diagrams.
#
# Fully containerized: the only host dependency is a container engine
# (podman by default; override with `make ENGINE=docker ...`). No JDK, no
# Node, no local Chrome required.
#
# Default rendering is PlantUML + Graphviz, which gives proper nested C4
# group boxes and legible edges. Mermaid auto-layout produces an unreadable
# hairball for a model this size, so it is kept only as an opt-in target for
# embedding a single view into a markdown ADR (the repo's markdown convention).
#
#   make            # export PlantUML from the DSL, then render every view to SVG
#   make svg        # same as `make all` (scalable, zoomable - best for reading)
#   make png        # also render PNGs
#   make mermaid    # export Mermaid (.mmd) for embedding a view into a markdown doc
#   make lite       # serve interactive Structurizr Lite at http://localhost:8080
#   make clean      # remove generated .puml / .mmd / .svg / .png

C4_DIR          := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
WORKSPACE       := workspace.dsl
ENGINE          ?= podman
STRUCTURIZR_IMG ?= docker.io/structurizr/structurizr
PLANTUML_IMG    ?= docker.io/plantuml/plantuml
MERMAID_IMG     ?= docker.io/minlag/mermaid-cli

STRUCTURIZR_RUN := $(ENGINE) run --rm -v "$(C4_DIR):/usr/local/structurizr" $(STRUCTURIZR_IMG)
PLANTUML_RUN    := $(ENGINE) run --rm -v "$(C4_DIR):/work" -w /work $(PLANTUML_IMG)
MERMAID_RUN     := $(ENGINE) run --rm -v "$(C4_DIR):/data" $(MERMAID_IMG)

.PHONY: all export svg png mermaid lite clean

## all: export PlantUML from the DSL and render every view to SVG
all: svg

## export: DSL -> one PlantUML file per view (structurizr-<View>.puml)
export:
	$(STRUCTURIZR_RUN) export -workspace $(WORKSPACE) -format plantuml
	@rm -f $(C4_DIR)/structurizr-*-key.puml

## svg: render every exported view to SVG (runs export first)
svg: export
	@for f in $(C4_DIR)/structurizr-*.puml; do \
		b=$$(basename "$$f" .puml); \
		echo "svg  $$b"; \
		$(PLANTUML_RUN) -tsvg "$$b.puml"; \
	done

## png: render every exported view to PNG (runs export first)
png: export
	@for f in $(C4_DIR)/structurizr-*.puml; do \
		b=$$(basename "$$f" .puml); \
		echo "png  $$b"; \
		$(PLANTUML_RUN) -tpng "$$b.puml"; \
	done

## mermaid: export Mermaid (.mmd) for embedding a single view into a markdown doc
mermaid:
	$(STRUCTURIZR_RUN) export -workspace $(WORKSPACE) -format mermaid

## lite: serve the interactive Structurizr Lite UI (Ctrl-C to stop)
# The old structurizr/lite image is deprecated (its entrypoint only prints a
# notice and exits); Lite now lives in the consolidated image as `... local`.
lite:
	$(ENGINE) run -it --rm -p 8080:8080 -v "$(C4_DIR):/usr/local/structurizr" $(STRUCTURIZR_IMG) local

## clean: remove generated PlantUML, Mermaid, and image files
clean:
	rm -f $(C4_DIR)/structurizr-*.puml $(C4_DIR)/structurizr-*.mmd \
		$(C4_DIR)/structurizr-*.svg $(C4_DIR)/structurizr-*.png
