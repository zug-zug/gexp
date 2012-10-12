require File.dirname(__FILE__) + "/graph"
STDOUT.sync = true

def usage
  abort(<<EOF)
usage: ruby select_knn.rb budget <# per-node edges> maxchosen <# proactive neighbor choices> in <input graph nodes> out <output file>

maxchosen : # of peer selections made by a node (must <= budget, default: 3)

budget    : per-node edge budget (must > 0, default: 3)
in        : input graph nodes (required)
out       : output graph nodes + selected edges (must differ from input file)
EOF
end

usage if ARGV.empty? || ARGV.include?('--help') || ARGV.include?('-?')

args = {
  :budget => 3,
  :maxchosen => 3,
  :in => nil,
  :out => nil,
}

i = 0
while i < ARGV.size
  arg = ARGV[i]
  case arg
  when 'budget'
    i += 1
    args[:budget] = ARGV[i].to_i
  when 'maxchosen'
    i += 1
    args[:maxchosen] = ARGV[i].to_i
  when 'in'
    i += 1
    args[:in] = ARGV[i].to_s.strip    
  when 'out'
    i += 1
    args[:out] = ARGV[i].to_s.strip
  else
    abort "Invalid arg: #{arg.inspect}" 
  end
  i += 1
end

usage if (args[:budget] <= 0 || args[:maxchosen] <= 0 ||
          args[:budget] < args[:maxchosen] ||
          args[:out].to_s.empty? || args[:out] == args[:in])
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
