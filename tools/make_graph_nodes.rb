require 'optparse'
require File.dirname(__FILE__) + "/graph"

args = {
  :n_nodes => 0,
  :n_owners => 0,
  :n_interests => 0,
  :idist => 'normal',
  :odist => 'uniform',
  :outfile => nil,
}

op = OptionParser.new do |opts|
  valid_dists = Util::Gen::VALID_DISTRIBUTIONS.join('|')
  opts.banner =<<EOF
usage: ruby generate_graph_nodes.rb -n <# nodes> -o <# owners> [--odist <#{valid_dists}>] -i <# interests> [--idist <#{valid_dists}>] --out <output file>

EOF
  opts.on('-n', '--nodes NODES', '# of nodes in graph') {|a| args[:n_nodes] = a.to_i }
  opts.on('-o', '--owners OWNERS', 'max # of owners spanning nodes') {|a| args[:n_owners] = a.to_i }
  opts.on('-i', '--interests INTERESTS', 'max # of possible interests' ) {|a| args[:n_interests] = a.to_i }
  opts.on('--odist OWNER_DIST', 'distribution of owner assignment (default: uniform)') do |a|
    args[:odist] = a.to_s.strip
  end
  opts.on('--idist INTEREST_DIST', 'distribution of interests (default: normal)') do |a|
    args[:idist] = a.to_s.strip
  end
  opts.on('--out FILE', 'file to output grpah nodes') {|a| args[:outfile] = a.to_s.strip }
  opts.on('-?', '--help', 'this help message' ) { warn opts; exit }
end
op.parse!
abort "nodes and owners must be non-zero" if args[:n_nodes] <= 0 || args[:n_owners] <= 0

g = Graph.rand_new(args[:n_nodes],
                   args[:n_owners],
                   args[:odist],
                   args[:n_interests],
                   args[:idist])
g.note(
  [ "generation params: #{args[:n_nodes]} nodes",
    "#{args[:n_owners]} owners (#{args[:odist]})",
    "#{args[:n_interests]} interests (#{args[:idist]})",
  ].join(', '))

if args[:outfile].to_s.empty?
  puts g.to_json
else
  g.write_file(args[:outfile])
end
