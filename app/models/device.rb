# frozen_string_literal: true

module YouFM
  module Models
    class Device
      extend Props

      props :id, :name, :type, :active, :restricted

      def display_label
        parts = [name, type]
        parts << 'active' if active
        parts << 'restricted' if restricted
        parts.compact.join(' · ')
      end
    end
  end
end
