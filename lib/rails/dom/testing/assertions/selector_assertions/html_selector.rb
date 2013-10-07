require_relative 'substitution_context'

class HTMLSelector #:nodoc:
  NO_STRIP = %w{pre script style textarea}
  attr_accessor :root, :selector, :equality_tests, :message

  alias :source :selector

  def initialize(selected, page, args)
    # Start with possible optional element followed by mandatory selector.
    @selector_is_second_argument = false
    @root = determine_root_from(args.first, page, selected)
    @selector = extract_selector(args)

    @equality_tests = equality_tests_from(args.shift)
    @message = args.shift

    if args.shift
      raise ArgumentError, "Not expecting that last argument, you either have too many arguments, or they're the wrong type"
    end
  end

  def select
    filter root.css(selector, context)
  end

  def filter(matches)
    match_with = equality_tests[:text] || equality_tests[:html]
    return matches if matches.empty? || !match_with

    content_mismatch = nil
    text_matches = equality_tests.has_key?(:text)
    regex_matching = match_with.is_a?(Regexp)

    remaining = matches.reject do |match|
      # Preserve markup with to_s for html elements
      content = text_matches ? match.text : match.children.to_s

      content.strip! unless NO_STRIP.include?(match.name)
      content.sub!(/\A\n/, '') if text_matches && match.name == "textarea"

      next if regex_matching ? (content =~ match_with) : (content == match_with)
      content_mismatch ||= sprintf("<%s> expected but was\n<%s>.", match_with, content)
      true
    end

    self.message ||= content_mismatch if remaining.empty?
    Nokogiri::XML::NodeSet.new(matches.document, remaining)
  end

  def determine_root_from(root_or_selector, page, previous_selection = nil)
    if root_or_selector == nil
      raise ArgumentError, "First argument is either selector or element to select, but nil found. Perhaps you called assert_select with an element that does not exist?"
    elsif root_or_selector.respond_to?(:css)
      @selector_is_second_argument = true
      root_or_selector
    elsif previous_selection
      if previous_selection.is_a?(Array)
        Nokogiri::XML::NodeSet.new(previous_selection[0].document, previous_selection)
      else
        previous_selection
      end
    else
      page
    end
  end

  def extract_selector(values)
    selector = @selector_is_second_argument ? values.shift(2).last : values.shift
    unless selector.is_a? String
      raise ArgumentError, "Expecting a selector as the first argument"
    end
    context.substitute!(selector, values)
  end

  def equality_tests_from(comparator)
      comparisons = {}
      case comparator
        when Hash
          comparisons = comparator
        when String, Regexp
          comparisons[:text] = comparator
        when Integer
          comparisons[:count] = comparator
        when Range
          comparisons[:minimum] = comparator.begin
          comparisons[:maximum] = comparator.end
        when FalseClass
          comparisons[:count] = 0
        when NilClass, TrueClass
          comparisons[:minimum] = 1
        else raise ArgumentError, "I don't understand what you're trying to match"
      end

      # By default we're looking for at least one match.
      if comparisons[:count]
        comparisons[:minimum] = comparisons[:maximum] = comparisons[:count]
      else
        comparisons[:minimum] ||= 1
      end
    comparisons
  end

  def context
    @context ||= SubstitutionContext.new
  end
end