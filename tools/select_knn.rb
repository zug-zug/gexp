require 'optparse'
require File.dirname(__FILE__) + "/graph"
STDOUT.sync = true

args = {
  :budget => 6,
  :maxchosen => 6,
  :in => nil,
  :out => nil,
}

op = OptionParser.new do |opts|
  opts.banner =<<EOF
usage: ruby select_knn.rb -b <# per-node edges> -m <# proactive neighbor choices> --in <input graph nodes> --out <output file>

EOF
  opts.on('-b', '--budget B', 'per-node edge budget (must > 0, default: 6)') {|a| args[:budget] = a.to_i }
  opts.on('-m', '--maxchosen M', '# of proactive peer selections per node (<= budget, default: 6)') do |a|
    args[:maxchosen] = a.to_i
  end
  opts.on('--in FILE', 'input graph nodes (required)') {|a| args[:in] = a.to_s.strip }
  opts.on('--out FILE', 'output graph nodes + selected edges (must differ from input file)') do |a|
    args[:out] = a.to_s.strip
  end
  opts.on('-?', '--help', 'this help message' ) { warn opts; exit }
end
op.parse!

abort op.help if args[:budget] <= 0 || args[:maxchosen] <= 0 ||
                 args[:budget] < args[:maxchosen] ||
                 args[:out].to_s.empty? || args[:out] == args[:in]
begin
  json_data = File.read(args[:in].to_s)
  g = Graph.from_json(json_data, args[:maxchosen], args[:budget])
rescue Exception => e
  abort "Couldn't build graph from input file #{args[:in].inspect} -- #{e.message}\n#{e.backtrace}"
end
puts "Loaded #{g} (per-node edge budget: #{args[:budget]})"

# Each node ranks a list of neighbors
g.nodes.each do |id, n|
  n.peer_ranking = SharedInterestPeers.new(n, g.peer_list_for(n))
end

nids = g.nodes.keys

# Nodes choose peers in random order
while g.nodes.any? {|id,n| !n.done_choosing?} do
  nids.shuffle!.each do |id|
    n = g.nodes[id]
    p = n.next_peer
    while(p && !n.connected_new(p))
      p = n.next_peer
    end
  end
end

g.nodes.each {|id, n| n.peers.each {|peer_id,p| g.add_link(n.id,p[:node].id)}}
g.note(
  [ "edge selection: knn",
    "input graph: #{args[:in]}",
    "per-node budget: #{args[:budget]}",
    "max-chosen: #{args[:maxchosen]}",
  ].join("\n"))

g.write_file(args[:out])
puts "Done."
