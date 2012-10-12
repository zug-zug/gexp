require 'rubygems'
require 'set'
require 'test/unit/assertions'
require 'json'
require File.dirname(__FILE__) + "/util"
include Test::Unit::Assertions

# Node have id, owner, interests, and peers
# Nodes choose peers based on the ranking/selection policy specified in @peer_ranking
# In some peer selection algorithms, we may want to distinguish peers selected
# by a node (proactively) from peers whose connection requests the node accepted
# (reactively); @chosen_peers_limit and @total_peers_limit address these two
# thresholds.
class Node
  attr_reader :id, :owner, :peers
  attr_accessor :interests, :peer_ranking
  DEFAULT_CHOSEN_PEERS_LIMIT = 6 # arbitrary default overriden by user-specified budget
  DEFAULT_TOTAL_PEERS_LIMIT = 6
  @@id = 0

  def self.from_h(h)
    h['chosen_peers_limit'] ||= DEFAULT_CHOSEN_PEERS_LIMIT
    h['total_peers_limit'] ||= DEFAULT_TOTAL_PEERS_LIMIT
    n = self.new(h['owner'], h['id'], h['chosen_peers_limit'], h['total_peers_limit'])
    n.interests = Set.new(h['interests'])
    n
  end

  def chosen_peers
    @peers.values.select {|p| p[:chosen]}.map {|p| p[:node]}
  end

  def initialize(owner, id=nil, n_chosen_peers=DEFAULT_CHOSEN_PEERS_LIMIT, n_total_peers=DEFAULT_TOTAL_PEERS_LIMIT)
    assert(n_chosen_peers > 0)
    assert(n_total_peers > 0)
    assert(n_chosen_peers <= n_total_peers)
    assert(n_chosen_peers > 0)
    @owner = owner
    @interests = Set.new
    @peers = {}
    @peer_ranking = nil
    @peer_rank_iter = nil
    @chosen_peers_limit = n_chosen_peers
    @total_peers_limit = n_total_peers

    assert(self.owner)
    @id = if id.nil?
            @@id
          else
            @@id = [id,@@id].max
            id
          end
    @@id += 1
  end

  def peer_ranking=(ranker)
    @peer_ranking = ranker
    @peer_rank_iter = ranker.iter
  end

  def next_peer
    return nil if done_choosing?
    @peer_rank_iter.next_peer
  end

  def done_choosing?
    (self.chosen_peers.size >= @chosen_peers_limit ||
     self.peers_list_full? ||
     !@peer_rank_iter.has_next?)
  end

  def peers_list_full?
    @peers.size >= @total_peers_limit
  end

  def notify_discard(id)
    @peers.delete(id)
  end

  def choose_peer(p)
    add_peer(p, true)
    puts "n #{self.id}: chose peer #{p.id}"
  end

  # if peers list is not full, just accept the connection
  # Otherwise, evict depending on what kind of ranker we're running :\
  def accept?(incoming_peer)
    assert(incoming_peer.is_a?(Node),
           "Expecting Node, got #{incoming_peer.class.to_s}")
    if !peers_list_full?
      add_peer(incoming_peer)
      return true
    end

    if @peer_ranking.is_a?(SharedInterestPeers)
      new_peer_sim = @peer_ranking.similarity(incoming_peer)
      distant_peers = @peers.values.select do |p| 
        existing_peer_sim = @peer_ranking.similarity(p[:node])
        (existing_peer_sim != SharedInterestPeers::SAME_OWNER_BUCKET &&
         (new_peer_sim == SharedInterestPeers::SAME_OWNER_BUCKET ||
          existing_peer_sim < new_peer_sim))
      end.map! {|p| p[:node]}

      return false if distant_peers.empty?

      discarded_peer = distant_peers.choice
      puts "n #{self.id}: discard peer #{discarded_peer.id} for #{incoming_peer.id}"
      @peers.delete(discarded_peer.id)
      discarded_peer.notify_discard(self.id)
      add_peer(incoming_peer)
      return true
    end
    # default random neighbors: reject incoming connection if we're full
    return false
  end

  def has_peer?(p)
    @peers.has_key?(p.id)
  end

  def connected_new(p)
    if has_peer?(p)
      choose_peer(p)
      return true
    end
    if p.accept?(self)
      choose_peer(p)
      return true
    end
    false
  end
  
  def inspect
    to_json
  end

  # NB: do not dump peer limits, since edge selection dictates them and they
  # don't change across nodes (yet)
  def hash_dump
    h = {:id => id, :owner => owner, :interests => interests.sort}
  end

  def to_json
    JSON.generate(self.hash_dump)
  end

private
  def add_peer(p, chosen=false)
    @peers[p.id] = {:node => p, :chosen => chosen}
  end
end

# Graph: stores nodes and links, and computes properties about them.
# Utility methods for experiment
# - apsp (all-pairs shorest paths)
# - shutdown of links/nodes
# - populate with random nodes
# - find a path between two nodes
class Graph
  attr_reader :nodes, :links, :failed_links, :adj_list, :nodes_by_owner, :nodes_by_interest
  attr_accessor :notes
  def initialize
    @nodes = {}
    @links = Set.new
    @adj_list = Hash.new {|h,k| h[k] = Set.new}
    @nodes_by_owner = Hash.new {|h,k| h[k] = Set.new}
    @nodes_by_interest = Hash.new {|h,k| h[k] = Set.new}
    @failed_links = Set.new
    # failed nodes implies failed links, but track separately for experiments
    @failed_nodes = Set.new
    @notes = []
  end

  # generate a random new graph:
  # v vertices
  # o owners w/ distribution odist
  # i interests w/ distribution idist
  # NB: assume it is not important to randomize peer limit values
  def self.rand_new(v, o, odist, itotal, idist, chosen_peers_lim=nil, total_peers_lim=nil)
    g = self.new
    v.times.map do |i|
      g.add_node( Node.from_h({ 'owner' => Util::Gen.rand_owner(o, odist),
                                'interests' => Util::Gen.rand_interests(itotal, idist),
                                'chosen_peers_limit' => chosen_peers_lim,
                                'total_peers_limit' => total_peers_lim,
                              }))
    end
    g
  end

  # NB: assume it is not important to randomize peer limit values
  def self.from_json(json, chosen_peers_lim=nil, total_peers_lim=nil)
    g = self.new
    data = JSON.parse(json)
    data['nodes'].each do |nid, node_h|
      node_h.merge!({'chosen_peers_limit' => chosen_peers_lim,
                     'total_peers_limit' => total_peers_lim})
      g.add_node(Node.from_h(node_h))
    end
    data['active_links'].each {|l| g.add_link(l['v0'],l['v1'], true) }
    # ghetto, but no time to implement a real trace :p
    data['notes'].each {|e| g.notes << e}
    g
  end

  def add_node(n)
    @nodes[n.id] = n
    @nodes_by_owner[n.owner] << n
    n.interests.each {|i| @nodes_by_interest[i] << n}
  end

  def add_link(vid0, vid1, build_adj_list=false)
    assert(vid0 != vid1, "No self loops allowed.")
    key = [vid0, vid1].sort
    key.each {|id| assert(@nodes.has_key?(id), "No node with id=#{id} for e:(#{vid0} -> #{vid1})") }
    @links << key
    if build_adj_list
      @adj_list[vid0] << vid1
      @adj_list[vid1] << vid0
    end
  end

  # ditched interest-anonmyzing "NodePeer." A Node obj only cares about its own
  # interests
  def peer_list_for(n)
    assert(nodes.has_key?(n.id), "No vertex w/ id #{n.id}")
    nodes.values.select {|p| p.id != n.id}
  end

  def direct_neighbors(nid)
    return @adj_list[nid] if @failed_nodes.empty? && @failed_links.empty?
    return Set.new if @failed_nodes.include?(nid)
    @adj_list[nid].select do |id|
      !@failed_nodes.include?(id) && !@failed_links.include?([nid,id].sort)
    end
  end

  def find_path(v0, v1)
    seen = Set.new([v0])
    parent = {}
    path = []
    q = [v0]
    start = Time.now
    while !q.empty? do
      head = q.shift
      if head == v1
        path << head
        while (parent[head] != v0) do
          path << parent[head]
          head = parent[head]
        end
        path << v0
        path.reverse!
        return path
      end
      direct_neighbors(head).each do |id|
        if !seen.include?(id)
          parent[id] = head
          q << id
          seen << id
        end
      end
    end
    return path
  end

  def live_nodes
    Set.new(@nodes.keys) - @failed_nodes
  end

  def clear_failures
    @failed_nodes.clear
    @failed_links.clear
  end

  def shutdown_node(v0)
    @adj_list[v0].each {|v1| shutdown_link(v0, v1)}
    @failed_nodes << v0
  end

  def shutdown_random_nodes(pct)
    return @failed_nodes if pct <= 0
    nodes_to_shutdown = Util.rand_elts_excluding(@nodes.keys, @failed_nodes.to_a, pct)
    nodes_to_shutdown.each {|n| shutdown_node(n)}
  end

  def shutdown_link(vid0, vid1)
    key = [vid0, vid1].sort!
    @failed_links << key
  end

  def shutdown_random_links(pct)
    return @failed_nodes if pct <= 0
    links_to_shutdown = Util.rand_elts_excluding(@links.to_a, @failed_links.to_a, pct)
    links_to_shutdown.each {|v0, v1| shutdown_link(v0, v1)}
    @failed_links
  end

  def note(msg)
    @notes << msg
  end

  def to_s
    inspect
  end

  def inspect
    ["graph: #{nodes.size} nodes",
     "#{@failed_nodes.size} failed_nodes",
     "#{@nodes_by_owner.keys.size} owners",
     "#{@links.size} links",
     "#{@failed_links.size} failed_links",
    ].join(", ")
  end

  def hash_dump
    t = { :nodes => {},
          :active_links => @links.to_a.map! {|v0, v1| {:v0 => v0, :v1 => v1} },
          :path_matrix => self.apsp.h,
          :notes => @notes,
        }
    @nodes.each {|k,v| t[:nodes][k] = v.hash_dump}
    t
  end

  def to_json
    h = self.hash_dump
    puts "Writing #{@nodes.size} nodes, #{h[:active_links].size} links, #{@nodes_by_owner.size} owners"
    JSON.generate(h)
  end

  def write_file(x)
    puts "-> #{x}"
    File.open(x, 'w') {|f| f.puts self.to_json }
  end

  class PathMatrix
    attr_accessor :h
    def initialize
      @h = {}
    end
    def [](row, col)
      return nil if @h[row].nil?
      @h[row][col]
    end
    def []=(row, col, val)
      if @h[row].nil?
        @h[row] = {}
      end
      @h[row][col] = val
    end
    def get_paths_of_len(len)
      assert(len > 0)
      @h.map do |src, row|
        row.keys.select {|neighbor| row[neighbor] == len}.map! {|dst| [src,dst] }
      end.flatten!(1)
    end
    def path_len_frequencies
      counts = Hash.new {|h,k| h[k] = 0}
      @h.values.each do |row|
        row.values.each {|len| counts[len]  += 1}
      end
      counts
    end
    def max
      @h.values.map {|row| row.values }.flatten.max
    end
    def to_json
      JSON.generate(@h)
    end
    def inspect
      entries = @h.values.inject(0) {|sum, row| sum += row.size}
      "PathMatrix: #{entries} entries"
    end
  end

  class UndirectedPathMatrix
    attr_reader :pm
    def initialize
      @pm = PathMatrix.new
    end

    def [](row, col)
      row, col = [row, col].sort!
      @pm[row,col]
    end

    def []=(row,col,val)
      assert(row != col)
      row, col = [row, col].sort!
      @pm[row,col] = val
    end

    def self.from_hash(h)
      upm = self.new
      h.each do |nid, peers|
        n = nid.to_i
        peers.each {|p, len| upm[n, p.to_i] = len}
      end
      upm
    end

    def inspect
      @pm.inspect
    end
    private
    # ghetto delegation
    def method_missing(m, *args, &block)
      @pm.send(m, *args, &block)
    end
  end

  def apsp(verbose=true) # All-pairs shorest-paths: O(N^3) Floyd-Warshall
    pm = UndirectedPathMatrix.new
    puts "Computing all-pairs shortest paths..." if verbose
    (@links - @failed_links).each {|v0, v1| pm[v0,v1] = pm[v1,v0] = 1}
    total = @nodes.size
    count = 0
    (0...total).each do |k|
      (0...total).each do |i|
        next if !pm[i,k]
        (0...total).each do |j|
          count += 1
          if pm[k,j]
            d = pm[i,k] + pm[k,j]
            if (pm[i,j].nil? || (d < pm[i,j])) && (i != j)
              pm[i,j] = d
            end
          end
          print '.' if (count % 10000 == 0) if verbose
        end
      end
    end
    pm
  end
end

# When choosing the next peer, choose a same-owner peer with probability
# 'owner_bias', otherwise choose a random different-owner peer.
# Uniform random peers -> owner_bias = 0.0
class BiasedOwnerRandomPeers
  def initialize(reference_node, peers, owner_bias=0.5)
    assert(owner_bias <= 1 && owner_bias >= 0, "owner bias must be in [0,1]")
    @node = reference_node
    @peers = {}
    @same_owner = []
    peers.each do |p|
      @peers[p.id] = p
      @same_owner << p.id if p.owner == @node.owner
    end
    @owner_bias = owner_bias
  end
  def iter(owner_bias=@owner_bias)
    Iterator.new(@peers, @same_owner, owner_bias)
  end

  class Iterator
    def initialize(peers_map, same_owner_nids, owner_bias)
      assert(owner_bias <= 1 && owner_bias >= 0, "owner bias must be in [0,1]")
      @data = peers_map
      @same_owners = same_owner_nids
      @owner_bias = owner_bias
      start
    end

    def has_next?
      !(@ids.empty? && @same_owner_candidates.empty?)
    end

    def start
      @ids = @data.keys
      @same_owner_candidates = []
      # becomes uniform random peers if zero owner bias
      if @owner_bias > 0
        @ids -= @same_owners
        @same_owner_candidates = @same_owners.clone
      end
    end

    def next_peer
      assert(@same_owner_candidates.empty?) if @owner_bias.zero?
      return nil if !has_next?
      src_ids = if @same_owner_candidates.empty?
                  @ids
                elsif @ids.empty? || (rand < @owner_bias)
                  @same_owner_candidates
                else
                  @ids
                end
      peer_id = choose_from(src_ids)
      @data[peer_id]
    end
    private
    def choose_from(ids)
      peer_id = ids.choice
      ids.delete(peer_id)
    end
  end
end

# Sort peers into similarity buckets, where similarity is defined as the
# number of shared interests between the reference node and a peer. Same-owner
# peers are always "most similar." Choose peers from the closest buckets first,
# and choose them at random within the bucket.
class SharedInterestPeers
  attr_reader :social_map
  SAME_OWNER_BUCKET = -1
  def initialize(reference_node, peers)
    @node = reference_node
    @social_map = Hash.new {|h,k| h[k] = []}
    peers.each do |p|
      key = similarity(p)
      @social_map[key] << p
    end
  end

  def iter
    Iterator.new(@social_map)
  end

  def similarity(p)
    assert(p.is_a?(Node),
           "Expecting Node, got #{p.class.to_s}: #{p.inspect}")
    assert(p.id != @node.id, "Peer should not be self")
    return SAME_OWNER_BUCKET if p.owner == @node.owner
    return (@node.interests ^ p.interests).size
  end

  class Iterator
    def initialize(buckets)
      @data = buckets
      # sort peer buckets by desc social similarity (same owner is always 'closest')
      @bucket_seq = @data.keys.sort do |a,b|
        if    a == SAME_OWNER_BUCKET; -1
        elsif b == SAME_OWNER_BUCKET;  1
        else
          b <=> a
        end
      end
      start
    end

    def has_next?
      !@curr_bucket.nil?
    end

    def start
      @bucket_seq_idx = 0
      @curr_bucket = bucket_from_seq
    end

    def next_peer
      return nil if !has_next?
      assert(!@curr_bucket.empty?)
      idx = rand(@curr_bucket.size)
      p = @curr_bucket.delete_at(idx)
      if @curr_bucket.empty?
        @bucket_seq_idx += 1
        @curr_bucket = bucket_from_seq
      end
      p
    end

  private
    def bucket_from_seq
      return nil if (@bucket_seq_idx >= @bucket_seq.size)
      b = @bucket_seq[ @bucket_seq_idx ]
      @data[b].clone
    end
  end
end
