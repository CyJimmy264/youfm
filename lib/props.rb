# frozen_string_literal: true

module Props
  # Объявляет список _свойств_ для класса, автоматически создавая:
  #   * attr_reader для каждого свойства
  #   * initialize c keyword-аргументами и дефолтами
  #   * проверку на отсутствие обязательных ключей и наличие неизвестных
  #
  # Пример:
  #
  #   class MyClass
  #     extend Props
  #
  #     props :foo, bar: false
  #
  #     def call
  #       foo if bar
  #     end
  #   end
  #
  # В этом примере метод `initialize` будет иметь сигнатуру:
  #   initialize(foo:, bar: false)
  #
  # И автоматически создаст геттеры:
  #   #foo
  #   #bar
  #
  # Пример использования:
  #  obj = MyClass.new(foo: 123, bar: true) # => #<MyClass:0x @bar=true, @foo=123>
  #  obj.foo  # => 123
  #  obj.bar  # => true
  #  obj.call # => 123
  #
  #  MyClass.new(foo: 123).call            # => nil
  #  MyClass.new(foo: 123, bar: true).call # => 123
  #
  #
  # @param [Array<Symbol>] required список обязательных keyword-аргументов
  # @param [Hash{Symbol=>Object}] optional хэш с именами и дефолтными значениями
  #
  # @raise [ArgumentError] если отсутствует обязательный аргумент
  # @raise [ArgumentError] если передан неизвестный аргумент
  #
  # @return [void]
  def props(*required, **optional) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    names = required + optional.keys
    attr_reader(*names)

    define_method(:initialize) do |**kwargs|
      missing = required.reject { |k| kwargs.key?(k) }
      raise ArgumentError, "Missing keywords: #{missing.join(', ')}" unless missing.empty?

      unknown = kwargs.keys - names
      raise ArgumentError, "Unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      values = optional.merge(kwargs)
      names.each { |prop| instance_variable_set("@#{prop}", values[prop]) }

      super() if defined?(super)
    end
  end
end
