# frozen_string_literal: true

module YouFM
  module Models
    class Device
      attr_reader :id, :name, :type, :active, :restricted

      def initialize(id:, name:, type:, active:, restricted:)
        @id = id
        @name = name
        @type = type
        @active = active
        @restricted = restricted
      end

      def display_label
        parts = [name, type]
        parts << 'active' if active
        parts << 'restricted' if restricted
        parts.compact.join(' · ')
      end
    end
  end
end
