require 'optparse'
require 'pathname'
require File.dirname(__FILE__) + "/graph"

STDOUT.sync = true

args = {
  :in => nil,
  :out => nil,
  :samples => 1000,
  :linkfail_inc => 0.05,
}

op = OptionParser.new do |opts|
  opts.banner =<<EOF
usage: ruby analyze_graph.rb -n <# samples> -f <% incremental failure> --in <input graph> --out <output file>

EOF
  opts.on('-n', '--samples N', 'number of node pairs to sample (max: (|V| choose 2))') do |a|
    args[:samples] = a.to_i
  end
  opts.on('-f', '--linkfail-inc F',
          "incremental % of random link failure (range: (0.0, 0.5] default: 0.1)") do |a|
    args[:linkfail_inc] = a.to_f
  end
  opts.on('--in FILE', 'input graph nodes (required)') {|a| args[:in] = a.to_s.strip }
  opts.on('--out FILE', 'output stats (must differ from input file)') do |a|
    args[:out] = a.to_s.strip
  end
  opts.on('-?', '--help', 'this help message' ) { warn opts; exit }
end
op.parse!

abort op.help if args[:out].to_s.empty? || args[:out] == args[:in]

t0 = Time.now
begin
  json_data = File.read(args[:in].to_s)
  data = JSON.parse(json_data)  # wastefully parse twice
  g = Graph.from_json(json_data)
rescue Exception => e
  abort "Couldn't build graph from input file #{args[:in].inspect} -- #{e.message}\n#{e.backtrace}"
end

LINKFAIL_CAP = 0.5
abort "link failure increment must be in (0.0, 0.5]" if (args[:linkfail_inc] > LINKFAIL_CAP) ||
                                                        (args[:linkfail_inc] <= 0.0)

owner_groups = g.nodes_by_owner.inject({}) do |memo, (oid, nodes)|
  memo[oid] = nodes.map {|n| n.id}
  memo
end
interest_groups = g.nodes_by_interest.inject({}) do |memo, (iid, nodes)|
  memo[iid] = nodes.map {|n| n.id}
  memo
end
node_pairs = Util.rand_pairs_from(g.live_nodes.to_a, args[:samples])

topdir_path = File.expand_path(File.dirname(__FILE__) + "/../")
infile_path = File.expand_path(args[:in])
Pathname
# XXX: not yet worth generalizing me
stats = {
  :metadata => {
    :input_graph => Pathname.new(infile_path).relative_path_from(Pathname.new(topdir_path))
  },
  # matrix graphs: generate a matrix of graphs in which we vary one metric (e.g.
  # % of failed random links) and measure various properties (e.g. diameter,
  # path len).
  :matrix_graphs => Hash.new do |h, metric|
    h[metric] = {
      :row_keys => [],  # values for variable metric
      :col_keys => [:path_len_histogram, :diameter_by_owner, :diameter_by_interest],
      :data => Hash.new {|h,k| h[k] = {}},
      # NB: Don't currently display path matrix info, but maybe useful in
      # future? For now, key: row_keys, val: path matrix associated w/ the row_key
      :path_matrices => {}
    }
  end,
  # standalone_graphs: just a normal scatter plot for some property
  # (e.g. % link failure vs. connectivity)
  :standalone_graphs => Hash.new {|h,property| h[property] = {:values => [], :title => ""}},
}

upm = Graph::UndirectedPathMatrix.from_hash(data['path_matrix'])
puts "Loaded path_matrix from #{args[:in]}: #{upm.inspect}"
(0.0..LINKFAIL_CAP).step(args[:linkfail_inc]).each do |link_fail_pct|
  link_fail_str = "#{link_fail_pct * 100}%"
  tag = "<links_down: #{link_fail_str}>"
  g.clear_failures
  g.shutdown_random_links(link_fail_pct)
  if (link_fail_pct != 0.0)
    print "#{tag} computing path matrix..."
    pmstart = Time.now
    upm = g.apsp(false)
    puts "#{Time.now - pmstart} secs"
  end

  success = 0
  start = Time.now
  node_pairs.each do |v0, v1|
    if !upm[v0,v1].nil?
      success += 1
    end
  end

  stats[:matrix_graphs][:link_failure][:path_matrices][link_fail_pct] = upm.h
  stats[:matrix_graphs][:link_failure][:row_keys] <<  link_fail_pct.to_s
  mgraphs = stats[:matrix_graphs][:link_failure][:data]
  sgraphs = stats[:standalone_graphs]
  # XXX: no time for box-whisker plot of path len. diameter should do for intuition
  [[owner_groups,    :diameter_by_owner],
   [interest_groups, :diameter_by_interest]].each do |group, statskey|
    start = Time.now
    mgraphs[link_fail_pct][statskey] = {
      :title => "CDF: #{statskey}, #{link_fail_str} link failure",
      :values => [],
    }
    group.each do |prop_id, nids|
      # XXX: only reachable nodes have diameter
      per_property_diameter = nids.combination(2).map {|v0, v1| upm[v0,v1]}.compact.max
      if per_property_diameter
        mgraphs[link_fail_pct][statskey][:values] << {:x => prop_id, :y => per_property_diameter}
      end
    end
    # inefficient hack: make into a cdf
    mgraphs[link_fail_pct][statskey][:values].sort! {|a,b| a[:y] <=> b[:y]}
    mgraphs[link_fail_pct][statskey][:values].each_with_index {|e, i| e[:x] = i}
    puts "#{tag}: #{statskey} took #{Time.now - start} secs"
  end

  pct_connected = "%.04f" % (success.to_f / args[:samples])
  puts "% links down: #{link_fail_pct * 100}, % connectivity: #{pct_connected},  time #{Time.now - start} secs"
  mgraphs[link_fail_pct][:path_len_histogram] = {
    :title => "Histogram: shortest path length (#{link_fail_str} link failure)",
    :values => upm.path_len_frequencies.to_a.sort.map {|x,y| {:x => x, :y => y}}
  }
  sgraphs[:sampled_connectivity][:values] << {:x => link_fail_pct, :y => pct_connected.to_f}
  sgraphs[:diameter][:values] << {:x => link_fail_pct, :y => upm.max}
  #stats[:path_matrices][link_fail_pct] = upm.h
end

stats[:standalone_graphs][:sampled_connectivity][:title] = "% failed links vs. node connectivity (N=#{args[:samples]})"
stats[:standalone_graphs][:diameter][:title] = "% failed links vs. graph diameter"

File.open(args[:out], "w") {|f| f.puts(JSON.generate(stats))}
puts "Wrote stats to #{args[:out]}"
puts "Total time: #{Time.now - t0} secs"
