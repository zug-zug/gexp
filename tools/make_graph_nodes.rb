require File.dirname(__FILE__) + "/graph"

def usage
  valid_dists = Gen::VALID_DISTRIBUTIONS.join('|')
  abort(<<EOF)
usage: ruby generate_graph_nodes.rb n <# nodes> o <# owners> odist <#{valid_dists}> i <# interests> idist <#{valid_dists}> out <output file>

n     :  # of nodes in graph
o     :  # of owners spanning nodes
i     :  # of total possible interests
odist :  distribution of owner assignment  (default: uniform)
idist :  distribution of interests         (default: normal)
out   :  file to output graph nodes
EOF
end

usage if ARGV.empty? || ARGV.include?('--help') || ARGV.include?('-?')

args = {
  :n_nodes => 0,
  :n_owners => 0,
  :n_interests => 0,
  :idist => 'normal',
  :odist => 'uniform',
  :outfile => nil,
}

i = 0
while i < ARGV.size
  arg = ARGV[i]
  case arg
  when 'n'
    i += 1
    args[:n_nodes] = ARGV[i].to_i
  when 'o'
    i += 1
    args[:n_owners] = ARGV[i].to_i
  when 'i'
    i += 1
    args[:n_interests] = ARGV[i].to_i
  when 'odist'
    i += 1
    args[:odist] = ARGV[i].to_s.strip
  when 'idist'
    i += 1
    args[:idist] = ARGV[i].to_s.strip
  when 'out'
    i += 1
    args[:outfile] = ARGV[i].to_s.strip
  else
    abort "Invalid arg(s)"
  end
  i += 1
end

usage if args[:n_nodes] <= 0 || args[:n_owners] <= 0

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
