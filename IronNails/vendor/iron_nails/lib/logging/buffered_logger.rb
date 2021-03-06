# Inspired by the Buffered Logger from Ezra (Merb)
# Taken from active_support
module IronNails
  
  module Logging
    
    FRAMEWORK_LOGGING = true
    CONSOLE_LOGGING = true
    
    class BufferedLogger
      module Severity
        DEBUG   = 0
        INFO    = 1
        WARN    = 2
        ERROR   = 3
        FATAL   = 4
        UNKNOWN = 5
      end
      include Severity
      
      MAX_BUFFER_SIZE = 1000
      
      # Set to false to disable the silencer
      cattr_accessor :silencer
      self.silencer = true
      
      # Silences the logger for the duration of the block.
      def silence(temporary_level = ERROR)
        if silencer
          begin
            old_logger_level, self.level = level, temporary_level
            yield self
          ensure
            self.level = old_logger_level
          end
        else
          yield self
        end
      end
      
      attr_accessor :level
      attr_reader :auto_flushing
      attr_reader :buffer
      
      def initialize(log, level = DEBUG)
        @level         = level
        @buffer        = []
        @auto_flushing = 1
        @no_block = false
        
        if log.respond_to?(:write)
          @log = log
        elsif File.exist?(log)
          @log = File.open(log, (File::WRONLY | File::APPEND))
          @log.sync = true
        else
          FileUtils.mkdir_p(File.dirname(log))
          @log = File.open(log, (File::WRONLY | File::APPEND | File::CREAT))
          @log.sync = true
          @log.write("# Logfile created on %s" % [Time.now.to_s])
        end
      end
      
      def set_non_blocking_io
        if !RUBY_PLATFORM.match(/java|mswin/) && !(@log == STDOUT) && @log.respond_to?(:write_nonblock)
          @no_block = true
        end
      end
      
      def add(severity, message = nil, progname = nil, &block)
        from_framework = progname == IRONNAILS_FRAMEWORKNAME
        return if @level > severity || (from_framework && !IronNails::Logging::FRAMEWORK_LOGGING )
        message = (message || (block && block.call) || progname).to_s
        puts message if IronNails::Logging::CONSOLE_LOGGING
        # If a newline is necessary then create a new message ending with a newline.
        # Ensures that the original message is not mutated.
        message = "IRONNAILS: #{Severity.constants[severity]}: #{message}" if from_framework
        message = "[#{Time.now.strftime("%d/%m/%Y %H:%M:%S.#{Time.now.usec}")}] #{message}\n" unless message[-1] == ?\n
        buffer << message
        auto_flush
        message
      end
      
      for severity in Severity.constants
        class_eval <<-EOT, __FILE__, __LINE__
        def #{severity.downcase}(message = nil, progname = nil, &block)
          add(#{severity}, message, progname, &block)
        end

        def #{severity.downcase}?
          #{severity} >= @level
        end
      EOT
      end
      
      # Set the auto-flush period. Set to true to flush after every log message,
      # to an integer to flush every N messages, or to false, nil, or zero to
      # never auto-flush. If you turn auto-flushing off, be sure to regularly
      # flush the log yourself -- it will eat up memory until you do.
      def auto_flushing=(period)
        @auto_flushing =
        case period
        when true;                1
        when false, nil, 0;       MAX_BUFFER_SIZE
        when Integer;             period
        else raise ArgumentError, "Unrecognized auto_flushing period: #{period.inspect}"
        end
      end
      
      def flush
        unless buffer.empty?
          if @no_block
            @log.write_nonblock(buffer.slice!(0..-1).join)
          else
            @log.write(buffer.slice!(0..-1).join)
          end
        end
      end
      
      def close
        flush
        @log.close if @log.respond_to?(:close)
        @log = nil
      end
      
      protected
        def auto_flush
          flush if buffer.size >= @auto_flushing
        end
    end
    
  end
  
end