require "./node"
require "./inline_parser"

class CommonMark::Ref

  getter destination
  getter title

  def initialize(@destination, @title)
  end
end

class CommonMark::Document
  def initialize
    CommonMark::Node.new "Document", [[1, 1], [0, 0]]
  end
end

class CommonMark::Blocks::Document
  def continue(parser, container)
    0
  end

  def finalize_block(parser, block)
  end

  def can_contain?(t)
    t != "Item"
  end

  def accepts_lines
    false
  end
end

class CommonMark::Blocks::List
  def continue(parser, container)
    0
  end

  def finalize_block(parser, block)
    while item = block.first_child
      # check for non-final list item ending with blank line:
      if ends_with_blank_line(item) && item.next_node
        block.list_tight = false
        break
      end
      # recurse into children of list item, to see if there are
      # spaces between any of them:
      while subitem = item.first_child
        if ends_with_blank_line(subitem) && (item.next_node || subitem.next_node)
          block.list_tight = false
          break
        end
        subitem = subitem.next_node
      end
      item = item.next_node
    end
  end

  def can_contain?(t)
    t == "Item"
  end

  def accepts_lines
    false
  end
end

class CommonMark::Blocks::BlockQuote
  def continue(parser, container)
    ln = parser.current_line
    if !parser.indented && peek(ln, parser.next_nonspace) == C_GREATERTHAN
      parser.advance_next_nonspace
      parser.advance_offset 1, false
      if peek(ln, parser.offset) == C_SPACE
        parser.offset += 1
      end
    else
      return 1
    end
    0
  end

  def finalize_block(parser, block)
  end

  def can_contain?(t)
    t != "Item"
  end

  def accepts_lines
    false
  end
end

class CommonMark::Blocks::Item
  def continue(parser, container)
    if parser.blank
      parser.advance_next_nonspace
    elsif parser.indent >= container.list_marker_offset + container.list_padding
      parser.advance_offset container.list_marker_offset + container.list_padding, true
    else
      return 1
    end
    0
  end

  def finalize_block(parser, block)
  end

  def can_contain?(t)
    t != "Item"
  end

  def accepts_lines
    false
  end
end

class CommonMark::Blocks::Header
  def continue(parser, container)
    # a header can never container > 1 line, so fail to match:
    return 1;
  end

  def finalize_block(parser, block)
  end

  def can_contain?(t)
    false
  end

  def accepts_lines
    false
  end
end

class CommonMark::Blocks::HorizontalRule
  def continue(parser, container)
    # an hrule can never container > 1 line, so fail to match:
    return 1;
  end

  def finalize_block(parser, block)
  end

  def can_contain?(t)
    false
  end

  def accepts_lines
    false
  end
end

class CommonMark::Blocks::CodeBlock
  def continue(parser, container)
    ln = parser.current_line
    indent = parser.indent
    if container.fenced? # fenced
      var match = (indent <= 3 &&
          ln.charAt(parser.next_nonspace) === container.fence_char &&
          ln.slice(parser.next_nonspace).match(reClosingCodeFence))
      if match && match[0].length >= container.fence_length
        # closing fence - we're at end of line, so we can return
        parser.finalize_block container, parser.lineNumber
        return 2
      else
        # skip optional spaces of fence offset
        var i = container._fenceOffset;
        while i > 0 && peek(ln, parser.offset) == C_SPACE
          parser.advance_offset 1, false
          i -= 1
        end
      end
    else # indented
      if indent >= CODE_INDENT
        parser.advance_offset CODE_INDENT, true
      elsif parser.blank
        parser.advance_next_nonspace
      else
        return 1
      end
    end
    0
  end

  def finalize_block(parser, block)
    if block.fenced? # fenced
      # first line becomes info string
      content = block.string_content
      newline_pos = content.index '\n'
      first_line = content.slice 0, newline_pos
      rest = content.slice newline_pos + 1
      block.info = unescape_string first_line.strip
      block.literal = rest
    else # indented
      block.literal = block.string_content.gsub(/(\n *)+$/, '\n')
    end
    # TODO: check
    # block.string_content = nil # allow GC
  end

  def can_contain?(t)
    false
  end

  def accepts_lines
    true
  end
end

class CommonMark::Blocks::HtmlBlock
  def continue(parser, container)
    parser.blank && (container.html_block_type == 6 || container.html_block_type == 7) ? 1 : 0
  end

  def finalize_block(parser, block)
    block.literal = block.string_content.gsub(/(\n *)+$/, "")
    # TODO: check
    # block.string_content = null; # allow GC
  end

  def can_contain?(t)
    false
  end

  def accepts_lines
    true
  end
end

class CommonMark::Blocks::Paragraph
  def continue(parser, container)
    parser.blank ? 1 : 0
  end

  def finalize_block(parser, block)
    var pos;
    has_reference_defs = false

    # try parsing the beginning as link reference definitions:
    while peek(block.string_content, 0) == C_OPEN_BRACKET &&
           (pos = parser.inline_parser.parse_reference(block.string_content, parser.refmap))
        block.string_content = block.string_content.slice(pos)
        has_reference_defs = true
    end
    if has_reference_defs && is_blank(block.string_content)
        block.unlink
    end
  end

  def can_contain?(t)
    false
  end

  def accepts_lines
    true
  end
end

class CommonMark::BlockStarts::BlockQuote
  def self.match(parser, container)
    if !parser.indented && peek(parser.current_line, parser.next_nonspace) == C_GREATERTHAN
      parser.advance_next_nonspace
      parser.advance_offset 1, false
      # optional following space
      if peek(parser.current_line, parser.offset) == C_SPACE
        parser.advance_offset 1, false
      end
      parser.close_unmatched_blocks
      parser.add_child "BlockQuote", parser.next_nonspace
      1
    else
      0
    end
  end
end

class CommonMark::BlockStarts::ATXHeader
  def self.match(parser, container)
    if !parser.indented && (match = parser.current_line.slice(parser.next_nonspace).match(reATXHeaderMarker))
        parser.advance_next_nonspace
        parser.advance_offset match[0].length, false
        parser.close_unmatched_blocks
        container = parser.add_child "Header", parser.next_nonspace
        container.level = match[0].strip.length # number of #s
        # remove trailing ###s:
        container.string_content =
            parser.current_line.slice(parser.offset).gsub(/^ *#+ *$/, "").gsub(/ +#+ *$/, "")
        parser.advance_offset parser.current_line.length - parser.offset
      2
    else
      0
    end
  end
end

class CommonMark::BlockStarts::FencedCodeBlock
  def self.match(parser, container)
    if !parser.indented && (match = parser.current_line.slice(parser.nextNonspace).match(reCodeFence))
      fence_length = match[0].length
      parser.close_unmatched_blocks
      container = parser.add_child "CodeBlock", parser.next_nonspace
      container.fenced = true
      container.fence_length = fence_length
      container.fence_char = match[0][0]
      container.fence_offset = parser.indent
      parser.advance_next_nonspace
      parser.advance_offset fence_length, false
      2
    else
      0
    end
  end
end

class CommonMark::BlockStarts::HTMLBlock
  def self.match(parser, container)
    if !parser.indented && peek(parser.current_line, parser.next_nonspace) == C_LESSTHAN
      s = parser.current_line.slice parser.next_nonspace
      1.upto 7 do |block_type|
        if reHtmlBlockOpen[block_type].test(s) && (block_type < 7 || container.type != "Paragraph")
          parser.close_unmatched_blocks
          # We don't adjust parser.offset;
          # spaces are part of the HTML block:
          b = parser.add_child "HtmlBlock", parser.offset
          b.html_block_type = block_type
          return 2
        end
      end
    end

    0
  end
end

class CommonMark::BlockStarts::SetextHeader
  def self.match(parser, container)
      if (!parser.indented &&
          container.type == "Paragraph" &&
          (container.string_content.index('\n') == container.string_content.length - 1) &&
                 ((match = parser.current_line.slice(parser.next_nonspace).match(reSetextHeaderLine))))

          parser.close_unmatched_blocks
          header = CommonMark::Node.new "Header", container.sourcepos
          header.level = match[0][0] == '=' ? 1 : 2
          header.string_content = container.string_content
          container.insert_after header
          container.unlink
          parser.tip = header
          parser.advance_offset parser.current_line.length - parser.offset, false
          return 2
    else
      0
    end
  end
end

class CommonMark::BlockStarts::HorizontalRule
  def self.match(parser, container)
    if !parser.indented && reHrule.test(parser.current_line.slice(parser.next_nonspace))
      parser.close_unmatched_blocks
      parser.add_child "HorizontalRule", parser.next_nonspace
      parser.advance_offset parser.current_line.length - parser.offset, false
      2
    else
      0
    end
  end
end

class CommonMark::BlockStarts::ListItem
  def self.match(parser, container)
    if (data = parse_list_marker(parser.current_line, parser.next_nonspace, parser.indent))
      parser.close_unmatched_blocks
      if parser.indented && parser.tip.type != "List"
          return 0
      end
      parser.advance_next_nonspace
      # recalculate data.padding, taking into account tabs:
      i = parser.column
      parser.advance_offset data.padding, false
      data.padding = parser.column - i

      # add the list if needed
      if parser.tip.type != "List" || !(lists_match(container.list_data, data))
        container = parser.add_child "List", parser.next_nonspace
        container.list_data = data
      end

      # add the list item
      container = parser.add_child "Item", parser.next_nonspace
      container.list_data = data
      1
    else
      0
    end
  end
end

class CommonMark::BlockStarts::IndentedCodeBlock
  def self.match(parser, container)
    if parser.indented && parser.tip.type != "Paragraph" && !parser.blank
      # indented code
      parser.advance_offset CODE_INDENT, true
      parser.close_unmatched_blocks
      parser.add_child "CodeBlock", parser.offset
      2
    else
        0
    end
  end
end

class CommonMark::Parser

  RE_LINE_ENDING = /\r\n|\n|\r/
  C_NEWLINE = '\n'

  getter doc
  getter options

  def initialize(options)
    @doc = CommonMark::Document.new
    @tip = @doc
    @oldtip = @doc
    @current_line = ""
    @line_number = 0
    @offset = 0
    @column = 0
    @next_nonspace = 0
    @next_nonspace_column = 0
    @indent = 0,
    @indented = false
    @blank = false,
    @all_closed = true
    @last_matched_container = @doc
    @last_line_length = 0
    @refmap = {} of String => CommonSpec::Ref
    @inlineParser = CommonMark::InlineParser.new(options)
    @options = options || {} of String => String
  end

  def is_line_end_char?(c)
    c == '\n' || c == '\r'
  end

  def parse(input)
    @doc = CommonMark::Document.new
    @tip = doc
    @refmap = {} of String => CommonSpec::Ref
    @line_number = 0
    @last_line_length = 0
    @offset = 0
    @column = 0
    @last_matched_container = doc
    @current_line = ""
    # if (this.options.time) { console.time("preparing input"); }
    lines = input.split RE_LINE_ENDING
    len = lines.length
    if input.ends_with? C_NEWLINE
        # ignore last blank line created by final newline
        len -= 1;
    end
    # if (this.options.time) { console.timeEnd("preparing input"); }
    # if (this.options.time) { console.time("block parsing"); }
    lines.each do |line|
      incorporate_line line
    end
    while tip
      finalize_block tip, len
    end
    # if (this.options.time) { console.timeEnd("block parsing"); }
    # if (this.options.time) { console.time("inline parsing"); }
    process_inlines doc
    # if (this.options.time) { console.timeEnd("inline parsing"); }
    doc
  end

  # 'finalize_block' is run when the block is closed.
  # 'continue' is run to check whether the block is continuing
  # at a certain line and offset (e.g. whether a block quote
  # contains a `>`.  It returns 0 for matched, 1 for not matched,
  # and 2 for "we've dealt with this line completely, go to next."
  def blocks
    {
      "Document" => CommonMark::Blocks::Document.new,
      "List" => CommonMark::Blocks::List.new,
      "BlockQuote" => CommonMark::Blocks::BlockQuote.new,
      "Item" => CommonMark::Blocks::Item.new,
      "Header" => CommonMark::Blocks::Header.new,
      "HorizontalRule" => CommonMark::Blocks::HorizontalRule.new,
      "CodeBlock" => CommonMark::Blocks::CodeBlock.new,
      "HtmlBlock" => CommonMark::Blocks::HtmlBlock.new,
      "Paragraph" => CommonMark::Blocks::Paragraph.new
    }
  end

  # block start functions.  Return values:
  # 0 = no match
  # 1 = matched container, keep going
  # 2 = matched leaf, no more block starts
  def block_starts
    [
      CommonMark::BlockStarts::BlockQuote,
      CommonMark::BlockStarts::ATXHeader,
      CommonMark::BlockStarts::FencedCodeBlock,
      CommonMark::BlockStarts::HTMLBlock,
      CommonMark::BlockStarts::SetextHeader,
      CommonMark::BlockStarts::HorizontalRule,
      CommonMark::BlockStarts::ListItem,
      CommonMark::BlockStarts::IndentedCodeBlock
    ]
  end

  def advance_offset(count, columns)
    i = 0
    cols = 0
    while columns ? (cols < count) : (i < count)
      if current_line[this.offset + i] == "\t"
        cols += (4 - (this.column % 4))
      else
        cols += 1
      end
      i += 1
    end
    @offset += i
    @column += cols
  end

  def advance_next_nonspace
    @offset = next_nonspace
    @column = next_nonspace_column
  end

  def find_next_nonspace
    i = offset
    cols = column
    c = nil

    while i < current_line.length
      c = current_line[i]
      if c == " "
        i += 1
        cols += 1
      elsif c == "\t"
        i += 1
        cols += (4 - (cols % 4))
      else
        break
      end
    end

    @blank = c == '\n' || c == '\r' || c.nil?
    @next_nonspace = i
    @next_nonspace_column = cols
    @indent = next_nonspace_column - column
    @indented = indent >= CODE_INDENT
  end

  # Analyze a line of text and update the document appropriately.
  # We parse markdown text by calling this on each line of input,
  # then finalizing the document.
  def incorporate_line(ln)
    all_matched = true
    t = nil

    container = doc
    @oldtip = tip
    @offset = 0
    @line_number += 1

    # FIXME: replace NUL characters for security
    # if (ln.indexOf('\u0000') !== -1) {
    #     ln = ln.replace(/\0/g, '\uFFFD');
    # }

    @current_line = ln

    # For each containing block, try to parse the associated line start.
    # Bail out on failure: container will point to the last matching block.
    # Set all_matched to false if not all containers match.
    last_child = nil
    while (last_child = container.last_child) && last_child.open
      container = last_child

      find_next_nonspace

      # FIXME!
      case blocks[container.type].continue self, container
      when 0 # we've matched, keep going
      when 1 # we've failed to match a block
        all_matched = false
      when 2 # we've hit end of line for fenced code close and can return
        @last_line_length = ln.length
        return
      else
        raise "continue returned illegal value, must be 0, 1, or 2"
      end

      unless all_matched
        container = container.parent # back up to last matching block
        break
      end
    end

    @all_closed = container == oldtip
    @last_matched_container = container

    # Check to see if we've hit 2nd blank line; if so break out of list:
    if blank && container.last_line_blank
      break_out_of_lists container
    end

    matched_leaf = container.type != "Paragraph" && blocks[container.type].accepts_lines
    starts = block_starts
    starts_len = starts.length
    # Unless last matched container is a code block, try new container starts,
    # adding children to the last matched container:
    while !matchedLeaf
      find_next_nonspace

      # this is a little performance optimization:
      # FIXME!
      if !indented && !reMaybeSpecial.test(ln.slice(next_nonspace))
        advance_next_nonspace
        break
      end

      i = 0
      while i < starts_len
        res = starts[i].match(self, container)
        if res == 1
          container = tip
          break
        elsif res == 2
          container = tip
          matched_leaf = true
          break
        else
          i += 1
        end
      end

      if i == starts_len # nothing matched
        advance_next_nonspace
        break
      end
    end

    # What remains at the offset is a text line.  Add the text to the
    # appropriate container.

   # First check for a lazy paragraph continuation:
    if !all_closed && !blank && tip.type == "Paragraph"
      # lazy paragraph continuation
      add_line
    else # not a lazy continuation
      # finalize any blocks not matched
      close_unmatched_blocks
      if blank && container.last_child
        container.last_child.last_line_blank = true
      end

      t = container.type

      # Block quote lines are never blank as they start with >
      # and we don't count blanks in fenced code for purposes of tight/loose
      # lists or breaking out of lists.  We also don't set _lastLineBlank
      # on an empty list item, or if we just closed a fenced block.
      last_line_blank = blank &&
          !(t == "BlockQuote" ||
            (t == "CodeBlock" && container.is_fenced) ||
            (t == "Item" &&
             !container.first_child &&
             container.sourcepos[0][0] === line_number));

      # propagate last_line_blank up through parents:
      cont = container
      while cont
        cont.last_line_blank = last_line_blank
        cont = cont.parent
      end

      if blocks[t].accepts_lines
        add_line
        # if HtmlBlock, check for end condition
        if (t == "HtmlBlock" &&
            container.html_block_type >= 1 &&
            container.html_block_type <= 5 &&
            reHtmlBlockClose[container.html_block_type].test(current_line.slice(offset)))
            finalize_block container, line_number
        end
      elsif offset < ln.length && !blank
        # create paragraph container for line
        container = add_child "Paragraph", offset
        advance_next_nonspace
        add_line
      end
    end
    @last_line_length = ln.length
  end

  # Finalize a block.  Close it and do any necessary postprocessing,
  # e.g. creating string_content from strings, setting the 'tight'
  # or 'loose' status of a list, and parsing the beginnings
  # of paragraphs for reference definitions.  Reset the tip to the
  # parent of the closed block.
  def finalize_block(block, line_number)
    above = block.parent
    block.open = false
    block.sourcepos[1] = [line_number, last_line_length]

    blocks[block.type].finalize_block self, block

    @tip = above
  end

  # Walk through a block & children recursively, parsing string content
  # into inline content where appropriate.
  def process_inlines(block)
    walker = block.walker
    inline_parser.refmap = refmap
    inline_parser.options = options
    while event = walker.next
      entering, node = event
      if !entering && (node.type == "Paragraph" || node.type === "Header")
        inline_parser.parse node
      end
    end
  end
end
