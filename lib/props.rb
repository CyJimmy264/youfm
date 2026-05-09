# frozen_string_literal: true

module Props
  def props(*required, **optional)
    names = required + optional.keys
    attr_reader(*names)

    define_method(:initialize) do |**kwargs|
      missing = required.reject { |key| kwargs.key?(key) }
      raise ArgumentError, "Missing keywords: #{missing.join(', ')}" unless missing.empty?

      unknown = kwargs.keys - names
      raise ArgumentError, "Unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      values = optional.merge(kwargs)
      names.each { |prop| instance_variable_set("@#{prop}", values[prop]) }

      super() if defined?(super)
    end
  end
end
