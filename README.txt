Edge budget crisis exploration
------------------------------

PROBLEM STATEMENT: Given an undirected graph G=(V,E) choose a subset of edges from E to connect its vertices.  Each vertex/node has the following attributes:
1) 1 owner
2) an edge budget (e.g. limit # of peer connections)
3) a set of interests

We want a relatively sparse graph that establishes connectivity between nodes with the same owners, and nodes with similar interest.

The goal of this project is to explore and characterize approaches to this problem, and to learn random stuff :)

# required gems
distribution (0.7.0)  # statistical distributions library
json (1.7.5)          # json parsing

TOUR OF FILES
-------------

tools/
1) make_graph_nodes.rb - generate a random graph with N nodes, O owners, I interests
2) select_{knn, random_peer}.rb - 2 dead simple algorithms for edge selection on the graph from (1)
3) analyze_graph.rb - collect stats on simulated random link failure on the graph from (2)

graph.rb - most of the mechanism lives here - graph, nodes, edge selection
util.rb - utility methods for random property generation

./
graphvis.html - draw the graph generated in (1) and/or (2)
  - mechanics in js/graphvis.js
    e.g. graphvis.html?data=sample_data/empty.json.knn_3_3
plot.html - plot stats collected in (3)
  - mechanics in js/plot.js
    e.g. plot.html?data=sample_data/empty.json.knn_3_3.stats


Edge selection schemes
----------------------

- Greedy shared interest neighbors: nodes greedily select similar neighbors first.
  Each node can have a maximum of B peers, but may only proactively choose up to
  M peers.  If a node already has B peers, it rejects connection requests from
  nodes with lower similarity than any existing peer.  If the requesting peer
  has higher similarity than one more more existig peers, the receiving node
  evicts one of these less-similar peers at random to make room for the new
  peer.

- Vaguely biased random peer: nodes select a same-owner peer with probability P,
  otherwise select a different-owner peer at random.
