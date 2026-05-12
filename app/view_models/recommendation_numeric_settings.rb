# frozen_string_literal: true

module YouFM
  module ViewModels
    class RecommendationNumericSettings
      DEFAULT_MINIMUM_RECOMMENDED_QUEUE_SIZE = 1
      DEFAULT_MAXIMUM_RECOMMENDED_QUEUE_SIZE = 25

      def initialize(recommendation_coordinator:, update_status:)
        @recommendation_coordinator = recommendation_coordinator
        @update_status = update_status
        @minimum_recommended_queue_size = DEFAULT_MINIMUM_RECOMMENDED_QUEUE_SIZE
        @maximum_recommended_queue_size = DEFAULT_MAXIMUM_RECOMMENDED_QUEUE_SIZE
      end

      attr_reader :minimum_recommended_queue_size, :maximum_recommended_queue_size

      def similar_artist_pool_limit
        recommendation_coordinator.similar_artist_pool_limit
      end

      def apply_similar_artist_pool_limit(value)
        parsed = normalize_positive_integer(value)
        return nil unless parsed

        recommendation_coordinator.similar_artist_pool_limit = parsed
        parsed
      end

      def update_similar_artist_pool_limit(value)
        parsed = apply_similar_artist_pool_limit(value)
        return update_status.call('Similar artist pool limit must be a positive integer') unless parsed

        update_status.call("Similar artist pool limit set to #{parsed}")
        parsed
      end

      def apply_minimum_recommended_queue_size(value)
        parsed = normalize_positive_integer(value)
        return nil unless parsed

        @minimum_recommended_queue_size = parsed
      end

      def update_minimum_recommended_queue_size(value)
        parsed = apply_minimum_recommended_queue_size(value)
        return update_status.call('Minimum recommended queue size must be a positive integer') unless parsed

        update_status.call("Minimum recommended queue size set to #{parsed}")
        parsed
      end

      def apply_maximum_recommended_queue_size(value)
        parsed = normalize_positive_integer(value)
        return nil unless parsed

        @maximum_recommended_queue_size = parsed
      end

      def update_maximum_recommended_queue_size(value)
        parsed = apply_maximum_recommended_queue_size(value)
        return update_status.call('Maximum recommended queue size must be a positive integer') unless parsed

        update_status.call("Maximum recommended queue size set to #{parsed}")
        parsed
      end

      private

      attr_reader :recommendation_coordinator, :update_status

      def normalize_positive_integer(value)
        parsed = Integer(value, exception: false)
        return nil if parsed.nil? || parsed <= 0

        parsed
      end
    end
  end
end
