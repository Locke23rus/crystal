require "./node_walker"

class CommonMark::Node
  CONTAINERS = ["Document", "BlockQuote", "List", "Item", "Paragraph", "Header", "Emph", "Strong", "Link", "Image"]

  getter type
  property first_child
  property last_child
  property next_node
  property prev_node
  property parent
  getter sourcepos
  property literal
  property destination
  property title
  property info
  property level
  property list_type
  property list_tight
  property list_start
  property list_delimiter

  def self.container?(node)
    node.is_a?(CommonMark::Node) && node.container?
  end

  def initialize(@type, @sourcepos)
  end

  def container?
    CONTAINERS.include?(type)
  end

  def append_child(child)
    child.unlink
    child.parent = self
    if last_child
      last_child.next_node = child
      child.prev_node = last_child
      @last_child = child
    else
      @first_child = child
      @last_child = child
    end
  end

  def prepend_child(child)
    child.unlink
    child.parent = self
    if first_child
      first_child.prev_node = child
      child.next_node = first_child
      @first_child = child
    else
      @first_child = child
      @last_child = child
    end
  end

  def unlink
    if prev_node
      prev_node.next_node = next_node
    elsif parent
      parent.first_child = next_node
    end
    if next_node
      next_node.prev_node = prev_node
    elsif parent
      parent.last_child = prev_node
    end
    @parent = nil
    @next_node = nil
    @prev_node = nil
  end

  def insert_before(sibling)
      sibling.unlink
      sibling.prev_node = prev_node
      if sibling.prev_node
        sibling.prev_node.next_node = sibling
      end
      sibling.next_node = self
      @prev_node = sibling
      sibling.parent = parent
      unless sibling.prev_node
        sibling.parent.first_child = sibling
      end
  end

  def insert_after(sibling)
    sibling.unlink
    sibling.next_node = next_node
    if sibling.next_node
      sibling.next_node.prev_node = sibling
    end
    sibling.prev_node = self
    @next_node = sibling
    sibling.parent = parent
    unless sibling.next_node
      sibling.parent.last_child = sibling
    end
  end

  def walker
    CommonMakr::NodeWalker.new self
  end
end
