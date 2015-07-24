class CommonMark::InlineParser
  def initialize(options)
    @subject = ""
    @delimiters = nil # used by handleDelim method
    @pos = 0
    @refmap = {} of String => CommonSpec::Ref
    @options = options || {} of String => String
  end
end
