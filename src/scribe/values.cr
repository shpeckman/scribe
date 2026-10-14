# src/scribe/values.cr
module Scribe
  record Position, line : Int32, column : Int32

  record Cell, column : Int32, row : Int32

  record Edit, range : Range(Int32, Int32), text : String

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
end
