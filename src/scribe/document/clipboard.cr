# src/scribe/document/clipboard.cr
module Scribe
  class Document
    def auto_copy : Nil
      copy if @copy_on_select && @carets.any? { |caret| !caret.empty? }
    end

    private def copy : Nil
      return unless @copyable

      texts = selected_texts
      @clipboard.write(texts.join('\n')) unless texts.empty?
    end

    private def cut : Nil
      return if !@copyable || @carets.all?(&.empty?)

      copy
      apply(History::Kind::Other) { |caret, _index| caret.empty? ? nil : Stroke.new(caret.range, "") }
    end

    private def paste_clipboard : Nil
      @clipboard.read do |text|
        text.try { |found| paste(found) }
        nil
      end
    end
  end
end
