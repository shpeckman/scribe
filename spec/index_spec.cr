# spec/index_spec.cr
require "./spec_helper"

private class Naive
  getter weights : Array(Int32)

  def initialize(@weights : Array(Int32))
  end

  def count : Int32
    @weights.size
  end

  def total : Int32
    @weights.sum
  end

  def prefix(line : Int32) : Int32
    @weights[0, line.clamp(0, @weights.size)].sum
  end

  def locate(value : Int32) : {Int32, Int32}
    return {Math.max(@weights.size - 1, 0), 0} if @weights.empty?

    rest = value.clamp(0, total)
    line = 0
    while line < @weights.size - 1 && rest >= @weights[line]
      rest -= @weights[line]
      line += 1
    end
    {line, rest}
  end

  def set(line : Int32, weight : Int32) : Nil
    @weights[line] = weight if 0 <= line < @weights.size
  end

  def insert(line : Int32, values : Array(Int32)) : Nil
    values.each_with_index { |value, index| @weights.insert(line.clamp(0, @weights.size) + index, value) }
  end

  def drop(line : Int32, count : Int32) : Nil
    return if @weights.empty?

    line  = line.clamp(0, @weights.size - 1)
    taken = Math.min(count, @weights.size - line)
    taken.times { @weights.delete_at(line) }
  end
end

describe Scribe::Index do
  it "answers prefix, locate and totals for a small table" do
    index = Scribe::Index.new([3, 1, 4, 1, 5])
    index.count.should eq(5)
    index.total.should eq(14)
    index.prefix(0).should eq(0)
    index.prefix(2).should eq(4)
    index.prefix(5).should eq(14)
    index[2].should eq(4)
    index.locate(0).should eq({0, 0})
    index.locate(3).should eq({1, 0})
    index.locate(4).should eq({2, 0})
    index.locate(6).should eq({2, 2})
    index.to_a.should eq([3, 1, 4, 1, 5])
  end

  it "starts empty and takes its first lines" do
    index = Scribe::Index.new
    index.count.should eq(0)
    index.total.should eq(0)
    index.insert(0, [2, 2])
    index.count.should eq(2)
    index.total.should eq(4)
    index.prefix(1).should eq(2)
  end

  it "updates a weight in place" do
    index = Scribe::Index.new([1, 2, 3])
    index.set(1, 10)
    index.total.should eq(14)
    index.prefix(2).should eq(11)
    index.set(9, 5)
    index.total.should eq(14)
  end

  it "grows past a block boundary and keeps every answer" do
    size  = Scribe::Index::LIMIT * 3
    plain = Array.new(size) { |value| (value % 7) + 1 }
    index = Scribe::Index.new(plain)
    naive = Naive.new(plain.dup)

    [0, 1, size // 2, size - 1, size].each do |line|
      index.prefix(line).should eq(naive.prefix(line))
    end
    index.total.should eq(naive.total)
    index.locate(naive.total // 2).should eq(naive.locate(naive.total // 2))
  end

  it "agrees with a naive table over thousands of random edits" do
    random = Random.new(20261014)
    plain  = Array.new(400) { random.rand(1..9) }
    index  = Scribe::Index.new(plain)
    naive  = Naive.new(plain.dup)

    3000.times do |step|
      case random.rand(4)
      when 0
        line   = random.rand(naive.count + 1)
        values = Array.new(random.rand(1..5)) { random.rand(1..9) }
        index.insert(line, values)
        naive.insert(line, values)
      when 1
        next if naive.count == 0

        line = random.rand(naive.count)
        gone = random.rand(1..4)
        index.drop(line, gone)
        naive.drop(line, gone)
      when 2
        next if naive.count == 0

        line = random.rand(naive.count)
        index.set(line, random.rand(1..20))
        naive.set(line, random.rand(1..20))
        naive.set(line, index[line])
      else
        line = random.rand(naive.count + 1)
        index.prefix(line).should eq(naive.prefix(line)), "prefix diverged at step #{step}"
      end

      index.count.should eq(naive.count), "count diverged at step #{step}"
      index.total.should eq(naive.total), "total diverged at step #{step}"
    end

    index.to_a.should eq(naive.weights)
    (0..naive.count).each { |line| index.prefix(line).should eq(naive.prefix(line)) }
    (0..naive.total).each { |value| index.locate(value).should eq(naive.locate(value)) }
  end

  it "replaces a run of lines, growing and shrinking" do
    index = Scribe::Index.new([1, 2, 3, 4])
    index.replace(1, 2, [9])
    index.to_a.should eq([1, 9, 4])
    index.replace(0, 0, [5, 5, 5])
    index.to_a.should eq([5, 5, 5, 9, 4])
    index.replace(0, 4, [7])
    index.to_a.should eq([7])
    index.total.should eq(7)
  end

  it "drops everything and comes back" do
    index = Scribe::Index.new([1, 2, 3])
    index.drop(0, 9)
    index.count.should eq(0)
    index.total.should eq(0)
    index.insert(0, [4])
    index.count.should eq(1)
    index.prefix(1).should eq(4)
  end
end
