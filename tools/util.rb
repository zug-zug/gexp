require 'rubygems'
require 'distribution'
require 'test/unit/assertions'
module Util
  module Gen
    VALID_DISTRIBUTIONS = ['uniform', 'normal']
    # Strive to assign a random integral value in [0, total - 1]
    def self.rand_idx(total, dist='uniform')
      return 0 if total <= 1
      case dist
      when 'uniform'
        rand(total)
      when 'normal'
        # zero-indexed, thus subtract 1 from the total
        Distribution::Binomial.p_value(rand, total - 1, 0.5)
      else
        assert(false, "unknown distribution: #{dist}")
      end
    end

    def self.rand_owner(ototal, odist='uniform')
      assert(ototal > 0, "total # owners should be > 0")
      self.rand_idx(ototal, odist)
    end

    # Lots of possibilities:
    # - The right way? Each interest has distribution, among v nodes
    # - For now, do the lazy thing:
    #   Each node has random i interests of itotal interest
    def self.rand_interests(itotal, idist='normal')
      assert(itotal >= 0, "total # interests should be >= 0")
      return [] if itotal == 0
      # ugly: rand_idx(n) returns [0, n-1], but we want a set size here,
      # so generate results [0, n].
      size = self.rand_idx(itotal + 1, idist)
      return [] if size == 0
      (0...itotal).to_a.shuffle.slice(0,size)
    end
  end

  def self.rand_pairs_from(src_array, npairs)
    assert(src_array.is_a?(Array))
    return [] if npairs <= 0
    npairs = [npairs, (src_array.size * (src_array.size - 1) / 2)].min
    src_array.combination(2).to_a.shuffle!.slice(0, npairs)
  end

  # Choose elements at random from 'src' that are not already in 'exclude'
  # such that |exclude| + |chosen| = pct*|src|
  def self.rand_elts_excluding(src, exclude, pct)
    assert(src.is_a?(Array) && exclude.is_a?(Array)) # I miss static typing :p
    assert(pct > 0 && pct < 1)
    candidates = (src - exclude).shuffle!
    chosen_size = [ pct*src.size - exclude.size, 0].max
    candidates.slice(0, chosen_size)
  end
end
