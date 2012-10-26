var json_blob = null;
var matrixdata = null;
var data_source = $.url().param('data');
console.log("data source: " + data_source);

d3.json(data_source, function(json_data) {
  if (json_data === null) {
    $("#graph_info").html("<font color='red'>Could not load data :(</font><br/>"
                        + "Double check the path.");
    return;
  }
  if (json_data.active_links) {
    $("#graph_info").html("<font color='red'>Invalid data file :(</font><br/>"
                        + "Perhaps you meant to <a href='graphvis.html?data="
                        + data_source + "'>graphvis</a> this data?");
    return;
  }
  if (json_data.metadata === null || json_data.metadata === undefined) {
    $("#graph_info").html("<font color='red'>Invalid data file :(</font><br/>"
                        + "I have no idea what you just gave me.");
    return;
  }
  var json_blob = json_data;
  var src_graph = json_blob.metadata.input_graph;
  $("#graph_info").html("<p>Generated from: <a href='graphvis.html?data=" +
                        src_graph + "'>" + src_graph + "</a></p>");

  for (var graphname in json_blob.standalone_graphs) {
    var sg = json_blob.standalone_graphs[graphname];
    scatter_plot("overview", sg.title, sg.values);
  }
  var matrix_graphs = json_blob['matrix_graphs'];
  matrixdata = matrix_graphs;
  var normalize_axes = ($.url().param('normalize_axes') === "1");

  for (var m in matrix_graphs) {
    var g = matrix_graphs[m];
    console.log("matrix: " + m);
    matrix_plot("matrix", g.data, g.row_keys, g.col_keys, normalize_axes);
  }
});

// data: [{x: xcoord, y: ycoord}, ...]
function scatter_plot(elem_id, title, data) {
  var height = 400,
      width = 600,
      padding = 80;
  var svg = d3.select("#" + elem_id).append("svg")
      .attr("width", width + padding)
      .attr("height", height + padding);

  // Title
  svg.append("text")
    .attr("x", padding / 2)
    .attr("y", padding / 3)
    .text(title);

  // compute scales
  var xcoord = function(d) { return d.x; };
  var ycoord = function(d) { return d.y; };
  var xdomain = [d3.min(data, xcoord), d3.max(data, xcoord)],
      ydomain = [d3.min(data, ycoord), d3.max(data, ycoord)],
      xrange = [padding / 2, width - padding / 2],
      yrange = [padding / 2, height - padding / 2];

  var xscale = d3.scale.linear()
    .domain(xdomain)
    .range(xrange);
  var yscale = d3.scale.linear()
    .domain(ydomain)
    .range(yrange.slice().reverse());

  var xAxis = d3.svg.axis()
      .scale(xscale)
      .orient("bottom");
  svg.append("g")
      .attr("class", "x axis")
      .attr("transform", "translate(0," + (height - padding / 2) + ")")
      .call(xAxis);

  var yAxis = d3.svg.axis()
      .scale(yscale)
      .orient("left");
  svg.append("g")
      .attr("class", "y axis")
      .attr("transform", "translate(" + (padding / 2 ) + ",0)")
      .call(yAxis);

  svg.selectAll("circle")
      .data(data)
    .enter().append("circle")
      .attr("class", "scatter-pt")
      .attr("cx", function(d) { return xscale(d.x); })
      .attr("cy", function(d) { return yscale(d.y); })
      .attr("r", 3);
}

function matrix_plot(elem_id, data, row_keys, col_keys, normalize_axes) {
  console.log("normalize axes: " + normalize_axes);
  var size = 400,
      padding = 100,
      rows = row_keys.length,
      cols = col_keys.length;

  // keyed by [row, col]
  var xScales = {};
  var yScales = {};
  var xAxes = {};
  var yAxes = {};
  var domains = {};
  var matrix = cross(row_keys, col_keys);

  var domainsByCol = {}; // keyed by col

  function cross(a, b) {
    var c = [], n = a.length, m = b.length, i, j;
    for (i = -1; ++i < n;)
      for (j = -1; ++j < m;)
        c.push({rowkey: a[i], row: i, colkey: b[j], col: j});
    return c;
  }

  // compute x and y domains for each cell
  matrix.forEach(function(cell) {
    var data_values = data[cell.rowkey][cell.colkey].values;
    var xcoord = function(d) { return d.x; };
    var ycoord = function(d) { return d.y; };
    var xdomain = [d3.min(data_values, xcoord), d3.max(data_values, xcoord)],
        ydomain = [d3.min(data_values, ycoord), d3.max(data_values, ycoord)];

    var key = [cell.row, cell.col];
    domains[key] = {
      xmin: xdomain[0], xmax: xdomain[1],
      ymin: ydomain[0], ymax: ydomain[1],
    };

    if (domainsByCol[cell.col] === undefined) {
      // initialize w/ deep copy of domain
      domainsByCol[cell.col] = $.extend(true, {}, domains[key]);
    } else {
      var d = domainsByCol[cell.col];
      for (var p in d) {
        if (!/min$/.test(p) && !/max$/.test(p))
          alert("Unexpected key in a domain object! (" + p + ")");
        var resolve = (/min$/.test(p) ? d3.min : d3.max);
        d[p] = resolve([d[p], domains[key][p]]);
      }
    }
  });

  // compute axes objects
  matrix.forEach(function(cell) {
    var range = [padding / 2, size - padding / 2],
        key = [cell.row, cell.col];

    var d = (normalize_axes
             ? domainsByCol[cell.col]
             : domains[key]);

    xScales[key] = d3.scale.linear()
    .domain([d.xmin, d.xmax])
    .range(range);

    yScales[key] = d3.scale.linear()
    .domain([d.ymin, d.ymax])
    .range(range.slice().reverse());

    xAxes[key] = d3.svg.axis().ticks(10);
    yAxes[key] = d3.svg.axis().ticks(10);
  });

  var svg = d3.select("#" + elem_id).append("svg")
      .attr("width", size * cols + padding)
      .attr("height", size * rows + padding);

  // X-axis.
  // - generate a set of X-axis for each cell in the matrix
  // - x/y offset by col/row index, respectively; similarly for y axis below
  svg.selectAll("g.x.axis")
      .data(matrix)
    .enter().insert("g")
      .attr("class", "x axis")
      .attr("transform", function(d, i) { return "translate(" + d.col * size + "," + ((d.row + 1) * size - padding /2)+ ")"; })
      .each(function(d) {
         d3.select(this).call(
            xAxes[[d.row, d.col]]
              .scale(xScales[[d.row, d.col]])
              .orient("bottom"));
       });

  svg.selectAll("g.y.axis")
      .data(matrix)
    .enter().append("g")
      .attr("class", "y axis")
      .attr("transform", function(d, i) { return "translate(" + (d.col * size + padding / 2) + "," + d.row * size + ")"; })
      .each(function(d) {
         d3.select(this).call(
            yAxes[[d.row, d.col]]
              .scale(yScales[[d.row, d.col]])
              .orient("left"));
       });

  var cell = svg.selectAll("g.cell")
      .data(matrix)
    .enter().append("g")
      .attr("class", "cell")
      .attr("transform", function(d) { return "translate(" + d.col * size + "," + d.row * size + ")"; })
      .each(plot);

  function plot(p) {
    var cell = d3.select(this);
    var data_values = data[p.rowkey][p.colkey].values;

    // Plot frame.
    cell.append("rect")
        .attr("class", "frame")
        .attr("x", padding / 2)
        .attr("y", padding / 2)
        .attr("width", size - padding)
        .attr("height", size - padding);

    // Title
    cell.append("text")
      .attr("x", padding / 2)
      .attr("y", padding / 3)
      .text(data[p.rowkey][p.colkey].title);

    // Plot dots.
    cell.selectAll("circle")
        .data(data_values)
      .enter().append("circle")
        .attr("class", "scatter-pt")
        .attr("cx", function(d) { return xScales[[p.row, p.col]](d.x); })
        .attr("cy", function(d) { return yScales[[p.row, p.col]](d.y); })
        .attr("r", 2);
  }
}
