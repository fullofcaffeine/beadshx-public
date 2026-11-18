package beadshx.cli;

/**
	Upstream htmlTemplate, the page that `bd graph --html` prints, filled in as
	upstream's fmt.Fprintf does: `title` is already HTML-escaped, and `nodes` and
	`links` are JSON arrays. The page loads D3.js from its CDN when it opens.
**/
function graphHtmlPage(title:String, nodes:String, links:String):String {
	return '<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>'
		+ title
		+ '</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; background: #1a1a2e; color: #eee; overflow: hidden; }
#graph { width: 100vw; height: 100vh; display: block; }
.node rect { rx: 6; ry: 6; stroke-width: 1.5; cursor: pointer; }
.node text { font-size: 11px; pointer-events: none; }
.node .id-text { font-size: 9px; fill: #999; }
.link { fill: none; stroke-width: 1.5; marker-end: url(#arrow); }
.link.blocks { stroke: #666; }
.link.parent-child { stroke: #555; stroke-dasharray: 5,3; }
#tooltip { position: absolute; background: #16213e; border: 1px solid #444; border-radius: 6px; padding: 10px 14px; font-size: 12px; pointer-events: none; opacity: 0; transition: opacity 0.15s; max-width: 320px; z-index: 10; }
#tooltip .tt-id { color: #7ec8e3; font-weight: bold; }
#tooltip .tt-status { display: inline-block; padding: 1px 6px; border-radius: 3px; font-size: 10px; margin-left: 6px; }
#legend { position: absolute; top: 12px; right: 12px; background: rgba(22,33,62,0.9); border: 1px solid #333; border-radius: 8px; padding: 12px 16px; font-size: 11px; }
#legend h3 { font-size: 12px; margin-bottom: 6px; color: #7ec8e3; }
.legend-item { display: flex; align-items: center; gap: 6px; margin: 3px 0; }
.legend-swatch { width: 14px; height: 14px; border-radius: 3px; display: inline-block; }
#controls { position: absolute; bottom: 12px; left: 12px; background: rgba(22,33,62,0.9); border: 1px solid #333; border-radius: 8px; padding: 8px 12px; font-size: 11px; }
#controls button { background: #2a2a4a; color: #ccc; border: 1px solid #444; border-radius: 4px; padding: 4px 10px; cursor: pointer; margin: 0 2px; font-size: 11px; }
#controls button:hover { background: #3a3a5a; }
</style>
</head>
<body>
<div id="tooltip"></div>
<div id="legend">
  <h3>Status</h3>
  <div class="legend-item"><span class="legend-swatch" style="background:#4a9eff"></span> Open</div>
  <div class="legend-item"><span class="legend-swatch" style="background:#f0ad4e"></span> In Progress</div>
  <div class="legend-item"><span class="legend-swatch" style="background:#d9534f"></span> Blocked</div>
  <div class="legend-item"><span class="legend-swatch" style="background:#5cb85c"></span> Closed</div>
  <div class="legend-item"><span class="legend-swatch" style="background:#777"></span> Deferred</div>
  <h3 style="margin-top:8px">Edges</h3>
  <div class="legend-item"><svg width="30" height="10"><line x1="0" y1="5" x2="30" y2="5" stroke="#888" stroke-width="1.5"/></svg> blocks</div>
  <div class="legend-item"><svg width="30" height="10"><line x1="0" y1="5" x2="30" y2="5" stroke="#666" stroke-width="1.5" stroke-dasharray="5,3"/></svg> parent-child</div>
</div>
<div id="controls">
  <button onclick="fitToView()">Fit View</button>
  <button onclick="resetZoom()">Reset View</button>
  <button onclick="toggleLabels()">Toggle Labels</button>
  Drag nodes to rearrange. Scroll to zoom. Click for details.
</div>
<svg id="graph"></svg>
<script src="https://d3js.org/d3.v7.min.js"></script>
<script>
const nodes = '
		+ nodes
		+ ';
const links = '
		+ links
		+ ';
const statusColors = { open:"#4a9eff", in_progress:"#f0ad4e", blocked:"#d9534f", closed:"#5cb85c", deferred:"#777", hooked:"#9966cc" };
const width = window.innerWidth, height = window.innerHeight;
let showLabels = true;

const svg = d3.select("#graph");
const defs = svg.append("defs");
defs.append("marker").attr("id","arrow").attr("viewBox","0 -5 10 10").attr("refX",20).attr("refY",0)
  .attr("markerWidth",6).attr("markerHeight",6).attr("orient","auto")
  .append("path").attr("d","M0,-4L8,0L0,4").attr("fill","#666");

const g = svg.append("g");
const zoom = d3.zoom().scaleExtent([0.1, 4]).on("zoom", e => g.attr("transform", e.transform));
svg.call(zoom);

const simulation = d3.forceSimulation(nodes)
  .force("link", d3.forceLink(links).id(d => d.id).distance(140).strength(0.7))
  .force("charge", d3.forceManyBody().strength(-400))
  .force("x", d3.forceX(d => 150 + d.layer * 220).strength(0.3))
  .force("y", d3.forceY(height / 2).strength(0.05))
  .force("collision", d3.forceCollide(50));

const link = g.append("g").selectAll("line").data(links).join("line")
  .attr("class", d => "link " + d.type)
  .attr("stroke-dasharray", d => d.type === "parent-child" ? "5,3" : null);

const node = g.append("g").selectAll("g").data(nodes).join("g").attr("class","node")
  .call(d3.drag().on("start", dragStart).on("drag", dragged).on("end", dragEnd));

const nodeW = 130, nodeH = 40;
node.append("rect").attr("width", nodeW).attr("height", nodeH)
  .attr("x", -nodeW/2).attr("y", -nodeH/2)
  .attr("fill", d => statusColors[d.status] || "#555")
  .attr("stroke", d => d3.color(statusColors[d.status] || "#555").darker(0.5));

node.append("text").attr("class","title-text").attr("text-anchor","middle").attr("dy", -3)
  .text(d => d.title.length > 18 ? d.title.substring(0,17) + "\\u2026" : d.title);

node.append("text").attr("class","id-text").attr("text-anchor","middle").attr("dy", 12)
  .text(d => d.id + " P" + d.priority);

const tooltip = d3.select("#tooltip");
node.on("mouseover", (e, d) => {
  tooltip.selectAll("*").remove();
  tooltip.text("");
  const idSpan = tooltip.append("span").attr("class","tt-id").text(d.id);
  tooltip.append("span").attr("class","tt-status").style("background", statusColors[d.status]||"#555").text(d.status);
  tooltip.append("br");
  tooltip.append("strong").text(d.title);
  tooltip.append("br");
  tooltip.append("span").text("Priority: P" + d.priority + " | Type: " + d.type);
  if (d.assignee) { tooltip.append("br"); tooltip.append("span").text("Assignee: " + d.assignee); }
  tooltip.append("br");
  tooltip.append("span").text("Layer: " + d.layer);
  tooltip.style("opacity", 1).style("left", (e.pageX+12)+"px").style("top", (e.pageY-10)+"px");
}).on("mouseout", () => { tooltip.style("opacity", 0); tooltip.selectAll("*").remove(); });

simulation.on("tick", () => {
  link.attr("x1",d=>d.source.x).attr("y1",d=>d.source.y).attr("x2",d=>d.target.x).attr("y2",d=>d.target.y);
  node.attr("transform", d => "translate("+d.x+","+d.y+")");
});

function dragStart(e, d) { if (!e.active) simulation.alphaTarget(0.3).restart(); d.fx = d.x; d.fy = d.y; }
function dragged(e, d) { d.fx = e.x; d.fy = e.y; }
function dragEnd(e, d) { if (!e.active) simulation.alphaTarget(0); d.fx = null; d.fy = null; }
function fitToView() {
  if (!nodes.length) return;
  const padding = 40;
  let xMin = Infinity, xMax = -Infinity, yMin = Infinity, yMax = -Infinity;
  nodes.forEach(d => {
    if (typeof d.x !== "number" || typeof d.y !== "number") return;
    xMin = Math.min(xMin, d.x - nodeW/2);
    xMax = Math.max(xMax, d.x + nodeW/2);
    yMin = Math.min(yMin, d.y - nodeH/2);
    yMax = Math.max(yMax, d.y + nodeH/2);
  });
  if (!isFinite(xMin)) return;
  const bboxW = xMax - xMin + 2*padding;
  const bboxH = yMax - yMin + 2*padding;
  const scale = Math.min(width/bboxW, height/bboxH, 4);
  const tx = width/2 - scale * (xMin + xMax)/2;
  const ty = height/2 - scale * (yMin + yMax)/2;
  svg.transition().duration(500).call(zoom.transform, d3.zoomIdentity.translate(tx, ty).scale(scale));
}
function resetZoom() { fitToView(); }
function toggleLabels() { showLabels = !showLabels; node.selectAll("text").style("opacity", showLabels ? 1 : 0); }

setTimeout(fitToView, 1500);
</script>
</body>
</html>
';
}
