# frozen_string_literal: true

module RuboCop
  module Cop
    module Qt
      # Enforces Ruby-style Qt property setters over set_* bridge methods.
      #
      # @example
      #   # bad
      #   widget.set_tool_tip('Hello')
      #
      #   # good
      #   widget.tool_tip = 'Hello'
      class PreferRubyStyleSetter < Base
        extend AutoCorrector

        MSG = 'Prefer Ruby-style Qt setter `%<replacement>s` over `%<original>s`.'

        def on_send(node)
          return unless qt_setter_call?(node)

          method_name = node.method_name.to_s
          replacement = replacement_source(node)
          add_offense(
            node.loc.selector,
            message: format(MSG, replacement: replacement, original: method_name)
          ) do |corrector|
            corrector.replace(node.source_range, replacement)
          end
        end

        private

        def qt_setter_call?(node)
          return false unless node.receiver

          node.arguments.one? &&
            node.method_name.to_s.start_with?('set_') &&
            !node.setter_method?
        end

        def replacement_source(node)
          attribute_name = node.method_name.to_s.delete_prefix('set_')
          receiver = node.receiver.source
          argument = node.first_argument.source
          "#{receiver}.#{attribute_name} = #{argument}"
        end
      end
    end
  end
end
