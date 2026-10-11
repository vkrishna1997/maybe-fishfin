import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import { sankey, sankeyLinkHorizontal } from "d3-sankey";

// Connects to data-controller="sankey-chart"
export default class extends Controller {
  static values = {
    data: Object,
    nodeWidth: { type: Number, default: 15 },
    nodePadding: { type: Number, default: 20 },
    currencySymbol: { type: String, default: "$" },
    transactionsUrl: { type: String, default: "" },
    period: { type: String, default: "" },
    frame: { type: String, default: "" },
    defaultClassification: { type: String, default: "" }
  };

  connect() {
    this.selection = null;
    this.#buildTooltip();
    this.resizeObserver = new ResizeObserver(() => this.#draw());
    this.resizeObserver.observe(this.element);
    this.#draw();
    this.#applyDefaultSelection();
  }

  disconnect() {
    this.resizeObserver?.disconnect();
    this.tooltip?.remove();
  }

  // Floating tooltip shown while hovering nodes/flows (Monarch-style).
  #buildTooltip() {
    if (getComputedStyle(this.element).position === "static") {
      this.element.style.position = "relative";
    }
    this.tooltip = document.createElement("div");
    this.tooltip.className =
      "pointer-events-none absolute z-20 hidden rounded-md bg-gray-700 fg-inverse text-xs font-medium px-2.5 py-1.5 shadow-lg whitespace-nowrap";
    this.element.appendChild(this.tooltip);
  }

  #showTooltip(html, event) {
    if (!this.tooltip) return;
    this.tooltip.innerHTML = html;
    this.tooltip.classList.remove("hidden");
    this.#moveTooltip(event);
  }

  #moveTooltip(event) {
    if (!this.tooltip) return;
    const rect = this.element.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    const offset = 14;
    const tipWidth = this.tooltip.offsetWidth;
    const tipHeight = this.tooltip.offsetHeight;
    const left = Math.min(Math.max(0, x + offset), rect.width - tipWidth);
    const top = Math.min(Math.max(0, y - tipHeight - offset / 2), rect.height - tipHeight);
    this.tooltip.style.left = `${left}px`;
    this.tooltip.style.top = `${top}px`;
  }

  #hideTooltip() {
    this.tooltip?.classList.add("hidden");
  }

  #money(value) {
    return (
      this.currencySymbolValue +
      Number.parseFloat(value).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })
    );
  }

  #draw() {
    const { nodes = [], links = [] } = this.dataValue || {};

    if (!nodes.length || !links.length) return;

    // Clear previous SVG
    d3.select(this.element).selectAll("svg").remove();

    const width = this.element.clientWidth || 600;
    const height = this.element.clientHeight || 400;

    const svg = d3
      .select(this.element)
      .append("svg")
      .attr("width", width)
      .attr("height", height);

    const sankeyGenerator = sankey()
      .nodeWidth(this.nodeWidthValue)
      .nodePadding(this.nodePaddingValue)
      .extent([
        [16, 16],
        [width - 16, height - 16],
      ]);

    const sankeyData = sankeyGenerator({
      nodes: nodes.map((d) => Object.assign({}, d)),
      links: links.map((d) => Object.assign({}, d)),
    });

    // Define gradients for links
    const defs = svg.append("defs");

    sankeyData.links.forEach((link, i) => {
      const gradientId = `link-gradient-${link.source.index}-${link.target.index}-${i}`;

      const getStopColorWithOpacity = (nodeColorInput, opacity = 0.5) => {
        let colorStr = nodeColorInput || "var(--color-gray-400)";
        if (colorStr === "var(--color-success)") {
          colorStr = "#10A861"; // Hex for --color-green-600
        }
        // Add other CSS var to hex mappings here if needed

        if (colorStr.startsWith("var(--")) { // Unmapped CSS var, use as is (likely solid)
          return colorStr;
        }

        const d3Color = d3.color(colorStr);
        return d3Color ? d3Color.copy({ opacity: opacity }) : "var(--color-gray-400)";
      };

      const sourceStopColor = getStopColorWithOpacity(link.source.color);
      const targetStopColor = getStopColorWithOpacity(link.target.color);

      const gradient = defs.append("linearGradient")
        .attr("id", gradientId)
        .attr("gradientUnits", "userSpaceOnUse")
        .attr("x1", link.source.x1)
        .attr("x2", link.target.x0);

      gradient.append("stop")
        .attr("offset", "0%")
        .attr("stop-color", sourceStopColor);

      gradient.append("stop")
        .attr("offset", "100%")
        .attr("stop-color", targetStopColor);
    });

    // Draw links
    const linkPaths = svg
      .append("g")
      .attr("fill", "none")
      .selectAll("path")
      .data(sankeyData.links)
      .join("path")
      .attr("d", (d) => {
        const sourceX = d.source.x1;
        const targetX = d.target.x0;
        const path = d3.linkHorizontal()({
          source: [sourceX, d.y0],
          target: [targetX, d.y1]
        });
        return path;
      })
      .attr("stroke", (d, i) => `url(#link-gradient-${d.source.index}-${d.target.index}-${i})`)
      .attr("stroke-width", (d) => Math.max(1, d.width))
      .attr("stroke-opacity", 1);

    this.linkPaths = linkPaths;

    linkPaths
      .on("mousemove", (event, d) => {
        this.#emphasizeLink(d);
        this.#showTooltip(
          `${nodes[d.source.index].name} &rarr; ${nodes[d.target.index].name}<br><span class="font-mono">${this.#money(d.value)}</span> &middot; ${d.percentage}%`,
          event
        );
      })
      .on("mouseleave", () => {
        this.#hideTooltip();
        this.#resetEmphasis();
      });

    // A flow is clickable: expense flows drill into a category, income flows
    // (into the central Cash Flow node) select the income classification.
    if (this.interactive) {
      linkPaths
        .filter((d) => d.target.category_name || d.target.classification)
        .style("cursor", "pointer")
        .on("click", (event, d) => this.#onNodeClick(d.target));
    }

    // Draw nodes
    const node = svg
      .append("g")
      .selectAll("g")
      .data(sankeyData.nodes)
      .join("g");

    this.nodeSel = node;

    const cornerRadius = 8;

    node.append("path")
      .attr("d", (d) => {
        const x0 = d.x0;
        const y0 = d.y0;
        const x1 = d.x1;
        const y1 = d.y1;
        const h = y1 - y0;
        // const w = x1 - x0; // Not directly used in path string, but good for context

        // Dynamic corner radius based on node height, maxed at 8
        const effectiveCornerRadius = Math.max(0, Math.min(cornerRadius, h / 2));

        const isSourceNode = d.sourceLinks && d.sourceLinks.length > 0 && (!d.targetLinks || d.targetLinks.length === 0);
        const isTargetNode = d.targetLinks && d.targetLinks.length > 0 && (!d.sourceLinks || d.sourceLinks.length === 0);

        if (isSourceNode) { // Round left corners, flat right for "Total Income"
          if (h < effectiveCornerRadius * 2) {
            return `M ${x0},${y0} L ${x1},${y0} L ${x1},${y1} L ${x0},${y1} Z`;
          }
          return `M ${x0 + effectiveCornerRadius},${y0}
                  L ${x1},${y0}
                  L ${x1},${y1}
                  L ${x0 + effectiveCornerRadius},${y1}
                  Q ${x0},${y1} ${x0},${y1 - effectiveCornerRadius}
                  L ${x0},${y0 + effectiveCornerRadius}
                  Q ${x0},${y0} ${x0 + effectiveCornerRadius},${y0} Z`;
        }

        if (isTargetNode) { // Flat left corners, round right for Categories/Surplus
          if (h < effectiveCornerRadius * 2) {
            return `M ${x0},${y0} L ${x1},${y0} L ${x1},${y1} L ${x0},${y1} Z`;
          }
          return `M ${x0},${y0}
                  L ${x1 - effectiveCornerRadius},${y0}
                  Q ${x1},${y0} ${x1},${y0 + effectiveCornerRadius}
                  L ${x1},${y1 - effectiveCornerRadius}
                  Q ${x1},${y1} ${x1 - effectiveCornerRadius},${y1}
                  L ${x0},${y1} Z`;
        }

        // Fallback for intermediate nodes (e.g., "Cash Flow") - draw as a simple sharp-cornered rectangle
        return `M ${x0},${y0} L ${x1},${y0} L ${x1},${y1} L ${x0},${y1} Z`;
      })
      .attr("fill", (d) => d.color || "var(--color-gray-400)")
      .attr("stroke", (d) => {
        // If a node has an explicit color assigned (even if it's a gray variable),
        // it gets no stroke. Only truly un-colored nodes (falling back to default fill)
        // would get a stroke, but our current data structure assigns colors to all nodes.
        if (d.color) {
          return "none";
        }
        return "var(--color-gray-500)"; // Fallback, likely unused with current data
      });

    // Hover any node to trace its connected flows and show its total.
    node
      .on("mousemove", (event, d) => {
        this.#emphasizeNode(d);
        const pctLabel = d.percentage != null ? ` &middot; ${d.percentage}%` : "";
        this.#showTooltip(
          `${d.name}<br><span class="font-mono">${this.#money(d.value)}</span>${pctLabel}`,
          event
        );
      })
      .on("mouseleave", () => {
        this.#hideTooltip();
        this.#resetEmphasis();
      });

    // Interactive drill-down: clicking a category node (or the central Cash Flow
    // node) highlights its flows and loads the matching transactions into a frame.
    if (this.interactive) {
      node
        .filter((d) => d.category_name || d.classification)
        .style("cursor", "pointer")
        .on("click", (event, d) => this.#onNodeClick(d));
    }

    const stimulusControllerInstance = this;
    node
      .append("text")
      .attr("x", (d) => (d.x0 < width / 2 ? d.x1 + 6 : d.x0 - 6))
      .attr("y", (d) => (d.y1 + d.y0) / 2)
      .attr("dy", "-0.2em")
      .attr("text-anchor", (d) => (d.x0 < width / 2 ? "start" : "end"))
      .attr("class", "text-xs font-medium text-primary fill-current")
      .each(function (d) {
        const textElement = d3.select(this);
        textElement.selectAll("tspan").remove();

        // Node Name on the first line
        textElement.append("tspan")
          .text(d.name);

        // Financial details on the second line
        const financialDetailsTspan = textElement.append("tspan")
          .attr("x", textElement.attr("x"))
          .attr("dy", "1.2em")
          .attr("class", "font-mono text-secondary")
          .style("font-size", "0.65rem"); // Explicitly set smaller font size

        financialDetailsTspan.append("tspan")
          .text(stimulusControllerInstance.currencySymbolValue + Number.parseFloat(d.value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
      });

    // Re-apply a sticky selection that survived a resize-triggered redraw.
    if (this.selection) this.#resetEmphasis();
  }

  get interactive() {
    return this.transactionsUrlValue.length > 0 && this.frameValue.length > 0;
  }

  // Select the income aggregate on first load so income transactions show.
  #applyDefaultSelection() {
    if (!this.interactive || !this.defaultClassificationValue || this.selection) return;
    const cls = this.defaultClassificationValue;
    const central = this.nodeSel?.data().find((n) => n.classification === cls);
    if (!central) return;
    this.#selectClassification(cls, central.index, { scroll: false });
  }

  #onNodeClick(node) {
    if (node.category_name) {
      this.#selectCategory(node);
    } else if (node.classification) {
      this.#selectClassification(node.classification, node.index);
    }
  }

  #selectCategory(node) {
    // Toggle selection off when the already-selected category is clicked again.
    if (this.selection?.type === "node" && this.selection.index === node.index) {
      this.#clearSelection();
      return;
    }

    this.selection = { type: "node", index: node.index };
    this.#emphasizeNode(node);

    const params = new URLSearchParams();
    params.set("category", node.category_name);
    if (this.periodValue) params.set("cashflow_period", this.periodValue);
    this.#loadFrame(params, { scroll: true });
  }

  #selectClassification(classification, nodeIndex, { scroll = true } = {}) {
    // Toggle selection off when the already-selected classification is re-clicked.
    if (this.selection?.type === "classification" && this.selection.value === classification) {
      this.#clearSelection();
      return;
    }

    this.selection = { type: "classification", value: classification, index: nodeIndex };
    this.#emphasizeClassification(classification);

    const params = new URLSearchParams();
    params.set("classification", classification);
    if (this.periodValue) params.set("cashflow_period", this.periodValue);
    this.#loadFrame(params, { scroll });
  }

  #clearSelection() {
    this.selection = null;
    this.#resetEmphasis();
    const openFrame = document.getElementById(this.frameValue);
    if (openFrame) openFrame.innerHTML = "";
  }

  #loadFrame(params, { scroll }) {
    const frame = document.getElementById(this.frameValue);
    if (!frame) return;
    frame.setAttribute("src", `${this.transactionsUrlValue}?${params.toString()}`);
    if (scroll) frame.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  // Emphasize every flow touching a node (and the node itself); fade the rest.
  #emphasizeNode(node) {
    this.#applyEmphasis(
      (link) => link.source.index === node.index || link.target.index === node.index,
      (n) => n.index === node.index
    );
  }

  // Emphasize every flow belonging to a classification (income or expense) plus
  // the central Cash Flow node and the matching side's category nodes.
  #emphasizeClassification(classification) {
    const linkActive = classification === "income"
      ? (l) => l.source.node_type === "income"
      : (l) => l.target.node_type === "expense";
    const nodeActive = (n) => n.node_type === classification || n.node_type === "cash_flow";
    this.#applyEmphasis(linkActive, nodeActive);
  }

  // Emphasize a single flow and the two nodes it connects.
  #emphasizeLink(link) {
    this.#applyEmphasis(
      (l) => l.index === link.index,
      (n) => n.index === link.source.index || n.index === link.target.index
    );
  }

  #applyEmphasis(linkActive, nodeActive) {
    this.linkPaths?.attr("stroke-opacity", (l) => (linkActive(l) ? 1 : 0.08));
    this.nodeSel?.attr("opacity", (n) => (nodeActive(n) ? 1 : 0.25));
  }

  // Restore full opacity, or fall back to the sticky selection if one is set.
  #resetEmphasis() {
    if (this.selection?.type === "node") {
      const selected = this.nodeSel?.data().find((n) => n.index === this.selection.index);
      if (selected) {
        this.#emphasizeNode(selected);
        return;
      }
    } else if (this.selection?.type === "classification") {
      this.#emphasizeClassification(this.selection.value);
      return;
    }
    this.linkPaths?.attr("stroke-opacity", 1);
    this.nodeSel?.attr("opacity", 1);
  }
}