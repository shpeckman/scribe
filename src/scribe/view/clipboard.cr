# src/scribe/view/clipboard.cr
module Scribe
  class View
    def auto_copy : Nil
      copy(@document.selection_clipboard || @document.clipboard) if @copy_on_select && @carets.any? { |caret| !caret.empty? }
    end

    private def copy(target : Clipboard = @document.clipboard) : Nil
      return unless @document.copyable?

      texts = selected_texts
      target.write(texts.join('\n')) unless texts.empty?
    end

    private def cut : Nil
      return if !@document.copyable? || @carets.all?(&.empty?)

      copy
      @document.apply(self, History::Kind::Other) { |caret, _index| caret.empty? ? nil : Stroke.new(caret.range, "") }
    end

    private def paste_clipboard : Nil
      @document.clipboard.read do |text|
        text.try { |found| paste(found) }
        nil
      end
    end
  end
end
