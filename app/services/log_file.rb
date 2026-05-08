# frozen_string_literal: true

module YouFM
  module Services
    class LogFile
      class Tee
        def initialize(target, log_file)
          @target = target
          @log_file = log_file
        end

        def write(message)
          write_to_target(message)
          log_file.append_async(message)
          message.to_s.bytesize
        end

        def <<(message)
          write(message)
          self
        end

        def flush
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

        attr_reader :target, :log_file

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
      TAIL_CHUNK_SIZE = 4096

      class << self
        def install!
          return if @installed

          log_file = new
          $stdout = Tee.new($stdout, log_file)
          $stderr = Tee.new($stderr, log_file)
          @installed = true
        end

        def append(message)
          new.append(message)
        end

        def tail(lines: DEFAULT_TAIL_LINES)
          new.tail(lines:)
        end

        def path
          new.path
        end
      end

      def initialize(path: self.class.default_path)
        @path = path
        @queue = Queue.new
        @worker_mutex = Mutex.new
        @worker = nil
      end

      attr_reader :path

      def append_async(message)
        start_worker
        queue << message.to_s
      rescue StandardError
        nil
      end

      def append(message)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'ab') do |file|
          file.write(message.to_s)
          file.flush
        end
      rescue StandardError
        nil
      end

      def tail(lines: DEFAULT_TAIL_LINES)
        return [] unless File.file?(path)

        tail_data(lines:).lines(chomp: true).last(lines)
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

      def self.default_path
        root = ENV.fetch('XDG_STATE_HOME', File.join(Dir.home, '.local', 'state'))
        File.join(root, 'youfm', 'youfm.log')
      end

      private

      attr_reader :queue, :worker_mutex

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
            append(message)
          end
        rescue StandardError
          nil
        end
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
