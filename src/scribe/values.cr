# src/scribe/values.cr
module Scribe
  record Position, line : Int32, column : Int32

  record Cell, column : Int32, row : Int32

  record Edit, range : Range(Int32, Int32), text : String

  record Point, line : Int32, column : Int32

  enum Units
    Bytes
    Utf16
    CodePoints
    Clusters

    def width(char : Char) : Int32
      case self
      in Bytes      then char.bytesize
      in Utf16      then char.ord > 0xFFFF ? 2 : 1
      in CodePoints then 1
      in Clusters   then 1
      end
    end
  end

  enum Gravity
    Left
    Right
  end

  enum LineEnding
    LF
    CRLF
    CR

    def sequence : String
      case self
      in LF   then "\n"
      in CRLF then "\r\n"
      in CR   then "\r"
      end
    end

    def self.detect(text : String) : LineEnding
      return LF unless text.includes?('\r')

      pairs   = text.scan("\r\n").size
      singles = text.count('\r') - pairs
      feeds   = text.count('\n') - pairs
      return CRLF if pairs >= singles && pairs >= feeds
      singles > feeds ? CR : LF
    end

    def self.normalize(text : String) : String
      return text unless text.includes?('\r')

      text.gsub("\r\n", "\n").tr("\r", "\n")
    end
  end

  record Stroke, range : Range(Int32, Int32), text : String, anchor : Int32? = nil, head : Int32? = nil
end
