require 'optparse'
require File.dirname(__FILE__) + "/graph"
STDOUT.sync = true

args = {
  :budget => 3,
  :in => nil,
  :out => nil,
  :bias => 0.0,
}

op = OptionParser.new do |opts|
  opts.banner =<<EOF
usage: ruby select_random_peer.rb -b <# per-node edges> --bias <owner bias> --in <input graph nodes> --out <output file>

EOF
  opts.on('-b', '--budget B', 'per-node edge budget (must > 0, default: 3)') {|a| args[:budget] = a.to_i }
  opts.on('--bias OWNER_BIAS',
          'probability of preferring same-owner peers (0.0 implies uniformly random selection)') do |a|
    args[:bias] = a.to_f
  end
  opts.on('--in FILE', 'input graph nodes (required)') {|a| args[:in] = a.to_s.strip }
  opts.on('--out FILE', 'output graph nodes + selected edges (must differ from input file)') do |a|
    args[:out] = a.to_s.strip
  end
  opts.on('-?', '--help', 'this help message' ) { warn opts; exit }
end
op.parse!

abort op.help  if (args[:budget] <= 0 ||
                   args[:bias] < 0.0 || args[:bias] > 1.0 ||
                   args[:out].to_s.empty? || args[:out] == args[:in])
begin
  json_data = File.read(args[:in].to_s)
  g = Graph.from_json(json_data, args[:budget], args[:budget])
rescue Exception => e
  abort "Couldn't build graph from input file #{args[:in].inspect} -- #{e.message}\n#{e.backtrace}"
end
puts "Loaded #{g} (per-node edge budget: #{args[:budget]})"

# Each node ranks a list of neighbors
g.nodes.each do |id, n|
  n.peer_ranking = BiasedOwnerRandomPeers.new(n, g.peer_list_for(n), args[:bias])
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
  [ "edge selection: random peer",
    "input graph: #{args[:in]}",
    "per-node budget: #{args[:budget]}",
    "same-owner bias: #{args[:bias]}",
  ].join("\n"))
g.write_file(args[:out])
puts "Done."
