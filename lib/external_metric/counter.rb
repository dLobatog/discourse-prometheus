# frozen_string_literal: true

module DiscoursePrometheus::ExternalMetric
  class Counter < Base
    attr_reader :data

    def initialize(name, help)
      super
      @data = {}
    end

    def type
      "counter"
    end

    def metric_text
      @data.map do |labels, value|
        "#{prefix(@name)}#{labels_text(labels)} #{value}"
      end.join("\n")
    end

    def observe(labels = {}, increment = 1)
      @data[labels] ||= 0
      @data[labels] += increment
    end
  end
end
