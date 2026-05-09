# frozen_string_literal: true

module YouFM
  module Services
    class LogFile
      class Tee
        def initialize(target, log_file)
          @target = target
          @log_file = log_file
          @buffer = +''
          @buffer_mutex = Mutex.new
        end

        def write(message)
          text = message.to_s
          write_to_target(message)
          write_to_log(text)
          text.bytesize
        end

        def <<(message)
          write(message)
          self
        end

        def flush
          flush_log_buffer
          log_file.flush
          target.flush if target.respond_to?(:flush)
        end

        def tty?
          target.respond_to?(:tty?) && target.tty?
        end

        def isatty # rubocop:disable Naming/PredicateMethod
          tty?
        end

        private

        attr_reader :target, :log_file, :buffer, :buffer_mutex

        def write_to_log(text)
          buffer_mutex.synchronize do
            buffer << text
            lines = complete_lines_from_buffer
            lines.each { |line| log_file.append_async(line) }
          end
        end

        def flush_log_buffer
          buffer_mutex.synchronize do
            return if buffer.empty?

            log_file.append_async(buffer)
            buffer.clear
          end
        end

        def complete_lines_from_buffer
          lines = []
          while (newline_index = buffer.index("\n"))
            lines << buffer.slice!(0..newline_index)
          end

          lines
        end

        def write_to_target(message)
          if target.respond_to?(:write_nonblock)
            target.write_nonblock(message.to_s)
          else
            target.write(message)
          end
        rescue IO::WaitWritable, Errno::EPIPE
          nil
        end
      end

      DEFAULT_TAIL_LINES = 50
      RECENT_LINE_LIMIT = 500
      TAIL_CHUNK_SIZE = 4096
      TIMESTAMP_PREFIX_PATTERN = /\[\d{4}-\d{2}-\d{2}T[^\]]+\] /
      TIMESTAMP_SPLIT_PATTERN = /(?=#{TIMESTAMP_PREFIX_PATTERN})/
      TIMESTAMP_ONLY_PATTERN = /\A\[\d{4}-\d{2}-\d{2}T[^\]]+\]\z/

      class << self
        def install!
          return if @installed

          log_file = instance
          $stdout = Tee.new($stdout, log_file)
          $stderr = Tee.new($stderr, log_file)
          @installed = true
        end

        def append(message)
          instance.append(message)
        end

        def append_async(message)
          instance.append_async(message)
        end

        def tail(lines: DEFAULT_TAIL_LINES)
          instance.tail(lines:)
        end

        def revision
          instance.revision
        end

        def wait_for_revision(revision, timeout:)
          instance.wait_for_revision(revision, timeout:)
        end

        def path
          instance.path
        end

        private

        def instance
          @instance ||= new
        end
      end

      def initialize(path: self.class.default_path)
        @path = path
        @queue = Queue.new
        @worker_mutex = Mutex.new
        @worker = nil
        @recent_mutex = Mutex.new
        @recent_condition = ConditionVariable.new
        @recent_lines = []
        @revision = 0
        seed_recent_from_file
      end

      attr_reader :path

      def append_async(message)
        return if blank_message?(message)

        remember(message)
        start_worker
        queue << normalized_message(message)
      rescue StandardError
        nil
      end

      def append(message)
        return if blank_message?(message)

        remember(message)
        append_to_file(message)
      rescue StandardError
        nil
      end

      def tail(lines: DEFAULT_TAIL_LINES)
        recent = recent_tail(lines:)
        return recent unless recent.empty?
        return [] unless File.file?(path)

        tail_lines = normalize_lines(tail_data(lines:)).last(lines)
        seed_recent(tail_lines)
        tail_lines
      rescue StandardError
        []
      end

      def flush
        barrier = Queue.new
        start_worker
        queue << barrier
        barrier.pop
      rescue StandardError
        nil
      end

      def revision
        recent_mutex.synchronize { @revision }
      end

      def wait_for_revision(revision, timeout:)
        deadline = monotonic_time + timeout
        recent_mutex.synchronize do
          while @revision <= revision
            remaining = deadline - monotonic_time
            break if remaining <= 0

            recent_condition.wait(recent_mutex, remaining)
          end

          @revision
        end
      end

      def self.default_path
        root = ENV.fetch('XDG_STATE_HOME', File.join(Dir.home, '.local', 'state'))
        File.join(root, 'youfm', 'youfm.log')
      end

      private

      attr_reader :queue, :worker_mutex, :recent_mutex, :recent_condition, :recent_lines

      def start_worker
        worker_mutex.synchronize do
          return if @worker&.alive?

          @worker = Thread.new do
            Thread.current.report_on_exception = false
            process_queue
          end
        end
      end

      def process_queue
        loop do
          message = queue.pop
          if message.is_a?(Queue)
            message << true
          else
            append_to_file(message)
          end
        rescue StandardError
          nil
        end
      end

      def remember(message)
        lines = normalize_lines(message)
        return if lines.empty?

        recent_mutex.synchronize do
          recent_lines.concat(lines)
          recent_lines.shift(recent_lines.length - RECENT_LINE_LIMIT) if recent_lines.length > RECENT_LINE_LIMIT
          @revision += 1
          recent_condition.broadcast
        end
      end

      def blank_message?(message)
        normalize_lines(message).empty?
      end

      def normalize_lines(message)
        lines = utf8_text(message).lines(chomp: true).flat_map { |line| line.split(TIMESTAMP_SPLIT_PATTERN) }
        lines.map(&:strip).reject { |line| line.empty? || TIMESTAMP_ONLY_PATTERN.match?(line) }
      end

      def utf8_text(message)
        text = message.to_s.dup.force_encoding(Encoding::UTF_8)
        return text if text.valid_encoding?

        text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
      end

      def normalized_message(message)
        lines = normalize_lines(message)
        return '' if lines.empty?

        "#{lines.join("\n")}\n"
      end

      def append_to_file(message)
        message = normalized_message(message)
        return if message.empty?

        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'ab') do |file|
          file.write(message)
        end
      end

      def recent_tail(lines:)
        recent_mutex.synchronize { recent_lines.last(lines) }
      end

      def seed_recent(lines)
        return if lines.empty?

        recent_mutex.synchronize do
          return unless recent_lines.empty?

          recent_lines.concat(lines.last(RECENT_LINE_LIMIT))
        end
      end

      def seed_recent_from_file
        return unless File.file?(path)

        seed_recent(normalize_lines(tail_data(lines: RECENT_LINE_LIMIT)).last(RECENT_LINE_LIMIT))
      rescue StandardError
        nil
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def tail_data(lines:)
        File.open(path, 'rb') do |file|
          position = file.size
          buffer = +''
          newline_count = 0

          while position.positive? && newline_count <= lines
            read_size = [TAIL_CHUNK_SIZE, position].min
            position -= read_size
            file.seek(position)
            chunk = file.read(read_size).to_s
            newline_count += chunk.count("\n")
            buffer.prepend(chunk)
          end

          buffer
        end
      end
    end
  end
end
