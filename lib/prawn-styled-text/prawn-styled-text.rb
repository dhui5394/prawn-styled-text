require 'oga'
require_relative 'callbacks'
require_relative 'prawn-document'

module PrawnStyledText
  BLOCK_TAGS = [ :br, :div, :h1, :h2, :h3, :h4, :h5, :h6, :hr, :li, :p, :ul ]
  DEF_BG_MARK = 'ffff00'
  DEF_HEADING_T = 16
  DEF_HEADING_H = 8
  DEF_MARGIN_UL = 15
  DEF_SYMBOL_UL = "\x95 "
  HEADINGS = { h1: 32, h2: 24, h3: 20, h4: 16, h5: 14, h6: 13 }
  RENAME = { 'font-family': :font, 'font-size': :size, 'font-style': :styles, 'letter-spacing': :character_spacing }

  @@margin_ul = 0
  @@symbol_ul = ''
  @@dynamic_br_tags = false
  @previous_styled_sibling_element_types = []
  @current_styled_traversal_level = 0

  def self.adjust_values( pdf, values )
    ret = {}
    values.each do |k, v|
      key = k.to_sym
      key = RENAME[key] if RENAME.include?( key )
      ret[key] = case key
        when :character_spacing
          v.to_f
        when :color
          v.delete '#'
        when :font
          matches = v.match /'([^']*)'|"([^"]*)"|(.*)/
          matches[3] || matches[2] || matches[1] || ''
        when :height
          i = v.to_i
          v.include?( '%' ) ? ( i * pdf.bounds.height * 0.01 ) : i
        when :size
          v.to_i
        when :styles
          v.split( ',' ).map { |s| s.strip.to_sym }
        when :width
          i = v.to_i
          v.include?( '%' ) ? ( i * pdf.bounds.width * 0.01 ) : i
        else
          v
        end
    end
    ret
  end

  def self.closing_tag( pdf, data )
    context = { tag: data[:name], options: {} }
    context[:flush] ||= true if BLOCK_TAGS.include? data[:name]
    # Evalutate tag
    case data[:name]
    when :br # new line
      context[:text] ||= [ { text: line_break_should_include_newline_character? ? "\n" : "" } ]
    when :img # image
      context[:flush] ||= true
      context[:src] = data[:node].get 'src'
    when :ul
      @@margin_ul = 0
    end
    # Evalutate attributes
    attributes = data[:node].get 'style'
    context[:options] = adjust_values( pdf, attributes.scan( /\s*([^:]+):\s*([^;]+)[;]*/ ) ) if attributes
    context
  end

  def self.opening_tag( pdf, data )
    context = { tag: data[:name], options: {} }
    context[:flush] ||= true if BLOCK_TAGS.include? data[:name]
    # Evalutate attributes
    attributes = data[:node].get 'style'
    context[:options].merge!( adjust_values( pdf, attributes.scan( /\s*([^:]+):\s*([^;]+)[;]*/ ) ) ) if attributes
    if data[:name] == :ul
      @@margin_ul += ( context[:options][:'margin-left'] ? context[:options][:'margin-left'].to_i : DEF_MARGIN_UL )
      @@symbol_ul = if context[:options][:'list-symbol']
          matches = context[:options][:'list-symbol'].match /'([^']*)'|"([^"]*)"|(.*)/
          matches[3] || matches[2] || matches[1] || ''
        else
          DEF_SYMBOL_UL
        end
    end
    context
  end

  def self.text_node( pdf, data )
    context = { pre: '', options: {} }
    styles = []
    font_size = pdf.font_size
    data.each do |part|
      # Evalutate tag
      tag = part[:name]
      case tag
      when :a # link
        link = part[:node].get 'href'
        context[:options][:link] = link if link
      when :b, :strong # bold
        styles.push :bold
      when :del, :s
        @@strike_through ||= StrikeThroughCallback.new( pdf )
        context[:options][:callback] = @@strike_through
      when :h1, :h2, :h3, :h4, :h5, :h6
        context[:options][:size] = HEADINGS[tag]
        context[:options][:'margin-top'] = DEF_HEADING_T
        context[:options][:'line-height'] = DEF_HEADING_H
      when :i, :em # italic
        styles.push :italic
      when :li # list item
        context[:options][:'margin-left'] = @@margin_ul
        context[:pre] = @@symbol_ul.force_encoding( 'windows-1252' ).encode( 'UTF-8' )
      when :mark
        @@highlight ||= HighlightCallback.new( pdf )
        @@highlight.set_color nil
        context[:options][:callback] = @@highlight
      when :small
        context[:options][:size] = font_size * 0.66
      when :u, :ins # underline
        styles.push :underline
      end
      context[:options][:styles] = styles if styles.any?
      # Evalutate attributes
      attributes = part[:node].get 'style'
      if attributes
        values = adjust_values( pdf, attributes.scan( /\s*([^:]+):\s*([^;]+)[;]*/ ) )
        @@highlight.set_color( values[:background].delete( '#' ) ) if tag == :mark && values[:background]
        context[:options].merge! values
      end
      font_size = context[:options][:size] if font_size
    end
    context
  end

  def self.traverse( nodes, context = [], &block )
    @current_styled_traversal_level += 1

    nodes.each do |node|
      if node.is_a? Oga::XML::Text
        yield :text_node, node.text.delete( "\n\r" ), context

        if node.text.strip.length.positive?
          @previous_styled_sibling_element_types[@current_styled_traversal_level] = "text"
        end
      elsif node.is_a? Oga::XML::Element
        element = { name: node.name.to_sym, node: node }
        yield :opening_tag, element[:name], element
        context.push( element )
        traverse( node.children, context, &block ) if node.children.count > 0
        yield :closing_tag, element[:name], context.pop

        @previous_styled_sibling_element_types[@current_styled_traversal_level] = element[:name]
      end
    end

    # as we step back up the tree, reset stale branches
    @previous_styled_sibling_element_types[@current_styled_traversal_level] = nil
    @current_styled_traversal_level -= 1
  end

  class << self
    private

    def previous_styled_element_was_block_level?
      BLOCK_TAGS.include?(@previous_styled_sibling_element_types[@current_styled_traversal_level])
    end

    def first_element_at_current_node_depth?
      @previous_styled_sibling_element_types[@current_styled_traversal_level].nil?
    end

    def line_break_should_include_newline_character?
      return true unless @@dynamic_br_tags

      previous_styled_element_was_block_level? || first_element_at_current_node_depth?
    end
  end
end
