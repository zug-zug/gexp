var w = 800,
    h = 800,
    fill = d3.scale.category20(),
    nodes = [],
    links = [],
    all_nodes = {},
    owners = {},
    ocount = 0,
    glinks = [],
    NODE_RADIUS = 9,
    foci_initialized = false,
    adj_list = {},
    lastResume = 0;

var interval = null;
var data_source = $.url().param('data');
console.log("data source: " + data_source);

if (data_source != undefined) {
  d3.json(data_source, function(gdata) {
    console.log(gdata);
    if (gdata === null) {
      $("#graph-notes").html("<font color='red'>Could not load data :(</font><br/>"
                             + "Double check the path.");
      return;
    }
    if (gdata.matrix_graphs) {
      $("#graph-notes").html("<font color='red'>Invalid data file :(</font><br/>"
                          + "Perhaps you meant to <a href='plot.html?data="
                          + data_source + "'>plot</a> this data?");
      return;
    }
    if (gdata.active_links === null || gdata.active_links === undefined) {
      $("#graph-notes").html("<font color='red'>Invalid data file :(</font><br/>"
                          + "I have no idea what you just gave me.");
      return;
    }
    var notes = ""
    $.each(gdata.notes, function(i, note) {
      notes += note + "\n";
    });
    $("#graph-notes").html("<pre>" + notes + "</pre>");
    for (var n in gdata.nodes) {
      var cur = gdata.nodes[n];
      all_nodes[cur.id] = $.extend(cur, { x: w/2, y: h/2});
      if (owners[cur.owner] === undefined) {
        owners[cur.owner] = all_nodes[n];
        ocount++;
      }
      nodes.push(all_nodes[n]);
    }
    console.log("owners: " + ocount);
    $("span#links-total").text(gdata.active_links.length);
    for (var n in gdata.active_links) {
      var l = gdata.active_links[n]
      var src = all_nodes[l.v0];
      var dst = all_nodes[l.v1];
      glinks.push({source: src, target: dst});
      if (adj_list[src.id] === undefined)
        adj_list[src.id] = [];
      if (adj_list[dst.id] === undefined)
        adj_list[dst.id] = [];
      adj_list[src.id].push(dst.id);
      adj_list[dst.id].push(src.id);
    }
    restart(true);

    if (glinks.length > 0)
      interval = setTimeout(animate_links, 10000);
  });
}

var currLinkIdx = 0;
function animate_links() {
  var chunk = 10;
  for(var i = chunk; i > 0 && (currLinkIdx < glinks.length); i--)
    links.push(glinks[currLinkIdx++]);
  restart(false);
  $("span#links-status").text(currLinkIdx);
  if (currLinkIdx < (glinks.length - 1))
    interval = setTimeout(animate_links, 1000);
  else
    clearInterval(interval);
}

var vis = d3.select("#graph").append("svg:svg")
    .attr("width", w)
    .attr("height", h);

var tooltip = Tooltip("vis-tooltip", 230, w);

vis.append("svg:rect")
    .attr("width", w)
    .attr("height", h)
    .attr("stroke", "#000");

var force = d3.layout.force()
    .distance(50)
    .nodes(nodes)
    .charge(-50)
    .links(links)
    .linkStrength(0)
    .size([w, h]);

force.on("tick", function(e) {
  vis.selectAll("line")
      .attr("x1", function(d) { return d.source.x; })
      .attr("y1", function(d) { return d.source.y; })
      .attr("x2", function(d) { return d.target.x; })
      .attr("y2", function(d) { return d.target.y; })
      .attr("class", function(d) { return (highlightLink(d) ? "highlighted-link" : "link"); });

  // Push different nodes in different directions for clustering.
  var k = 0.5 * e.alpha;
  var q = d3.geom.quadtree(nodes);
  nodes.forEach(function(o, i) {
    if (o.fixed)
      return;
    if (!foci_initialized && o.id === owners[o.owner].id)
      return;
    var fx = owners[o.owner].x;
    var fy = owners[o.owner].y;
    o.y += (fy - o.y) * k;
    o.x += (fx - o.x) * k;
    q.visit(collide(o));
  });

  vis.selectAll("circle")
      .attr("cx", function(d) { return d.x = nodeX(d); })
      .attr("cy", function(d) { return d.y = nodeY(d); })
      .attr("class", function(d) { return (highlightNode(d) ? "highlighted-node" : "node") });
});

function collide(node) {
  var r = NODE_RADIUS + 16,
      nx1 = node.x - r,
      nx2 = node.x + r,
      ny1 = node.y - r,
      ny2 = node.y + r;
  return function(quad, x1, y1, x2, y2) {
    if (quad.point && (quad.point.id !== node.id)) {
      var x = node.x - quad.point.x,
          y = node.y - quad.point.y,
          l = Math.sqrt(x * x + y * y),
          r = 2 * NODE_RADIUS;
      if (l < r) {
        l = (l - r) / l * .8;
        node.px += x * l;
        node.py += y * l;
      }
    }
    return x1 > nx2
        || x2 < nx1
        || y1 > ny2
        || y2 < ny1;
  };
}

var INVALID_NODE = -1
var highlight_links_for = INVALID_NODE;
var selected_nodes = [];
function clearSelection() {
  highlight_links_for = INVALID_NODE;
  selected_nodes = [];
}
function showDetails(node, i) {
  clearSelection();
  content = '<p class="title">id: ' + node.id + '</p>' +
            '<hr class="tooltip-hr">' +
            '<p class="name">owner: ' + node.owner + '</p>' +
            '<p class="main">interests: ' + node.interests.join(", ") + '</p>';
  tooltip.showTooltip(content,d3.event);
  highlight_links_for = node.id;
  var peers = adj_list[node.id];
  if (peers === undefined)
    return;
  selected_nodes = $.merge([node.id], peers);
}

function hideDetails(node, i) {
  clearSelection();
  tooltip.hideTooltip();
}

function highlightLink(link) {
  if (highlight_links_for === link.source.id ||
      highlight_links_for === link.target.id)
    return true;
  return false;
}

function highlightNode(node) {
  if ($.inArray(node.id, selected_nodes) === -1)
    return false
  return true;
}

function nodeX(node) { return Math.max(NODE_RADIUS, Math.min(w - NODE_RADIUS, node.x)); }
function nodeY(node) { return Math.max(NODE_RADIUS, Math.min(h - NODE_RADIUS, node.y)); }
function restart(init) {

  vis.selectAll("line")
      .data(links)
    .enter().insert("svg:line", "circle")
      .attr("class", "link")
      .attr("x1", function(d) { return d.source.x; })
      .attr("y1", function(d) { return d.source.y; })
      .attr("x2", function(d) { return d.target.x; })
      .attr("y2", function(d) { return d.target.y; });

  visNodes = vis.selectAll("circle")
                .data(nodes);

  visNodes.enter().insert("svg:circle")
      .attr("class", "node")
      .attr("cx", function(d) { return d.x = nodeX(d); })
      .attr("cy", function(d) { return d.y = nodeY(d); })
      .attr("r", NODE_RADIUS - 2)
      .attr("fill", function(d) { return fill(d.owner % 20); })  // we cluster same-owner nodes, so can recycle colors
      .call(force.drag);

  visNodes.on("mouseover", function(node, i) {
      showDetails(node, i);
      var now = Date.now();
      if (force.alpha() === 0 && (now - lastResume > 10000)) {
        console.log("resuming simulation... alpha=" + force.alpha());
        force.resume();
        lastResume = now;
      }
  })
    .on("mouseout", hideDetails);

  force.start();
  if (init) {
    console.log("simulating focii...");
    for (var i = Math.max(1000, (nodes.length * nodes.length));
         i > 0; i--) {
      force.tick();
    }
    console.log("fixing node position");
    for (var n in owners) {
      v = owners[n]
      owners[n] = {x: v.x, y: v.y}
    }
    foci_initialized = true;
    toggleFixedPositions();
    $("#affix-nodes-button").on("click", toggleFixedPositions);
    $("#affix-nodes-button").attr("disabled", false);
  }
}

var fixedPosition = false;
function toggleFixedPositions() {
  fixedPosition = !fixedPosition;
  $.each(nodes, function(i, e) { e.fixed = fixedPosition; });
  $("#affix-nodes-button").text((fixedPosition ? "Unfreeze nodes" : "Freeze nodes"));
}
