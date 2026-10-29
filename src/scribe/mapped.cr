# src/scribe/mapped.cr
module Scribe
  class Mapped
    class Error < Exception
    end

    getter path     : String
    getter bytesize : Int32
    getter? open    : Bool
    getter? writable : Bool

    @address : Pointer(Void)

    def self.open(path : String, writable : Bool = false, & : Mapped -> T) : T forall T
      found = new(path, writable: writable)
      begin
        yield found
      ensure
        found.close
      end
    end

    def initialize(@path : String, @writable : Bool = false)
      {% unless flag?(:unix) %}
        raise Error.new("Scribe::Mapped needs a POSIX system")
      {% end %}

      size = File.size(@path)
      raise Error.new("#{@path} is larger than this build can map") if size > Int32::MAX

      @bytesize = size.to_i32
      @open     = true

      if @bytesize == 0
        @address = Pointer(Void).null
        return
      end

      file = File.open(@path, @writable ? "r+" : "r")
      begin
        protection = @writable ? LibC::PROT_READ | LibC::PROT_WRITE : LibC::PROT_READ
        flags      = @writable ? LibC::MAP_SHARED : LibC::MAP_PRIVATE
        found      = LibC.mmap(Pointer(Void).null, @bytesize, protection, flags, file.fd, 0)
        raise Error.new("could not map #{@path}") if found == LibC::MAP_FAILED

        @address = found
      ensure
        file.close
      end
    end

    def bytes : Bytes
      raise Error.new("#{@path} is no longer mapped") unless @open
      return Bytes.empty if @bytesize == 0

      Bytes.new(@address.as(UInt8*), @bytesize, read_only: !@writable)
    end

    def sequential : Nil
      return unless @open && @bytesize > 0

      LibC.madvise(@address, @bytesize, LibC::MADV_SEQUENTIAL)
    end

    def close : Nil
      return unless @open

      @open = false
      LibC.munmap(@address, @bytesize) if @bytesize > 0
      @address = Pointer(Void).null
    end

    def finalize
      close
    end
  end
end
