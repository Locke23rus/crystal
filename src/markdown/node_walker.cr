require "./node"

class CommonMark::NodeWalker
  def initialize(root)
    @root = root
    @current = root
    @entering = true
  end

  def resume_at(node, entering)
    @current = node
    @entering = entering
  end

  def next
    return unless @current

    current = @current
    entering = @entering

    container = CommonMark::Node.container?(cur)

    if entering && container
      if current.first_child
        @current = current.first_child
        @entering = true
      else
        # stay on node but exit
        @entering = false
      end
    elsif current === root
      @current = nil
    elsif current.next.nil?
      @current = current.parent
      @entering = false
    else
      @current = current.next
      @entering = true
    end

    { entering, current }
  end
end
