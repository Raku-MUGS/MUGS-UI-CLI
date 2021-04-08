# ABSTRACT: Provide a generic input field with a basic editing keymap

use MUGS::Core;

use Term::termios;
use Text::MiscUtils::Layout;


#| Edit actions called from MUGS::UI::CLI::Input
role MUGS::UI::Input::Buffer {
    has UInt:D $.insert-pos = 0;
    has Str:D  $.buffer     = '';


    # NOTE: Return values below indicate whether $!buffer may have been changed

    ### Refresh requests
    method edit-refresh(   --> False) {}
    method edit-refresh-all(--> True) {}


    ### Cursor movement
    method edit-move-to-start(--> False) {
        $!insert-pos = 0;
    }

    method edit-move-back(--> False) {
        --$!insert-pos if $!insert-pos;
    }

    method edit-move-forward(--> False) {
        ++$!insert-pos if $!insert-pos < $!buffer.chars;
    }

    method edit-move-to-end(--> False) {
        $!insert-pos = $!buffer.chars;
    }


    ### Delete
    method edit-delete-char-back(--> True) {
        substr-rw($!buffer, --$!insert-pos, 1) = ''
            if 0 < $!insert-pos <= $!buffer.chars;
    }

    method edit-delete-char-forward(--> True) {
        substr-rw($!buffer, $!insert-pos, 1) = ''
            if 0 <= $!insert-pos < $!buffer.chars;
    }

    method edit-delete-word-back(--> True) {
        if 0 < $!insert-pos <= $!buffer.chars {
            my $cut = $!insert-pos - 1;
            --$cut while $cut >= 0 && substr($!buffer, $cut, 1) ~~ /\s/;
            --$cut while $cut >= 0 && substr($!buffer, $cut, 1) ~~ /\S/;
            $cut++;

            substr-rw($!buffer, $cut, $!insert-pos - $cut) = '';
            $!insert-pos = $cut;
        }
    }

    method edit-delete-word-forward(--> True) {
        my $chars = $!buffer.chars;
        if 0 <= $!insert-pos < $chars {
            my $cut = $!insert-pos;
            ++$cut while $cut < $chars && substr($!buffer, $cut, 1) ~~ /\s/;
            ++$cut while $cut < $chars && substr($!buffer, $cut, 1) ~~ /\S/;
            $cut--;

            substr-rw($!buffer, $!insert-pos, $cut, $cut - $!insert-pos) = '';
        }
    }

    method edit-delete-to-start(--> True) {
        substr-rw($!buffer, 0, $!insert-pos) = '';
        $!insert-pos = 0;
    }

    method edit-delete-to-end(--> True) {
        substr-rw($!buffer, $!insert-pos) = ''
            if 0 <= $!insert-pos < $!buffer.chars;
    }

    method edit-delete-line(--> True) {
        $!buffer = '';
        $!insert-pos = 0;
    }


    ### Insert/Swap
    method edit-insert-string(Str:D $string --> True) {
        # The complexity below is because the inserted string might start with
        # combining characters, and thus due to NFG renormalization insert-pos
        # should move less than the full length of the inserted string.

        my $before    = $!buffer.chars;
        substr-rw($!buffer, $!insert-pos, 0) = $string;
        $!insert-pos += $!buffer.chars - $before;
    }

    method edit-swap-chars(--> True) {
        if 0 < $!insert-pos && 1 < $!buffer.chars {
            my $at-end   = $!insert-pos == $!buffer.chars;
            my $swap-pos = $!insert-pos - 1 - $at-end;
            my $char1    = substr($!buffer, $swap-pos,     1);
            my $char2    = substr($!buffer, $swap-pos + 1, 1);
            substr-rw($!buffer, $swap-pos, 2) = $char2 ~ $char1;

            ++$!insert-pos unless $at-end;
        }
    }


    ### History
    method edit-history-prev(--> True) {
    }

    method edit-history-next(--> True) {
    }


    ### Special
    method edit-abort-modal(--> True) {
    }

    method edit-tab(--> True) {
    }

    method edit-escape(--> True) {
    }
}


# Invariants maintained:
# * Buffer is always in NFG Str form (tested in Raku for edge cases like
#   inserting a combining mark between characters, and it Just Works.)
# * Insert position is always kept visible on screen, scrolling extra-long
#   lines if necessary.
# * Insert position is always at the start of a glyph position, never halfway
#   into an existing glyph, even with mixed-width strings.
# * Output is always bounded by cursor-start and cursor-end
# * Output always is connected at the start end of the field


class MUGS::UI::CLI::Input::Buffer
 does MUGS::UI::Input::Buffer {
    has UInt:D $.cursor-start is required;
    has UInt:D $.cursor-end   is required;
    has UInt:D $.field-width   = $!cursor-end - $!cursor-start;
    has UInt:D $.cursor-pos    = $!cursor-start;
    has UInt:D $.scroll-pos    = 0;
    has Str    $.mask;

    has %!char-width-cache;
    has @!char-widths;
    has @!char-widths-prefix-sum;


    ### INTERNALS

    method char-width(Str:D $chr) {
        %!char-width-cache{$chr} //= duospace-width($chr);
    }

    method recompute-widths() {
        @!char-widths = $!mask.defined ?? self.char-width($.mask) xx $!buffer.chars
                                       !! $!buffer.comb.map({ self.char-width($_) });
        @!char-widths-prefix-sum = [\+] @!char-widths;
        @!char-widths-prefix-sum.unshift(0);
    }

    method subbuffer-width(UInt:D $start, UInt:D $after) {
        # XXXX: For RTL, auto-swap $start and $after?
        die "Nonsensical subbuffer {$start}..^{$after} for buffer of length { $!buffer.chars }."
            unless 0 <= $start <= $after < @!char-widths-prefix-sum;
        @!char-widths-prefix-sum[$after] - @!char-widths-prefix-sum[$start]
    }

    method cursor-move-command(Int:D $distance --> Str:D) {
        $distance == 0 ?? ''                 !!
        $distance  > 0 ?? "\e[{ $distance}C" !!
                          "\e[{-$distance}D" ;
    }

    #| Completely redraw the input field, scrolling so that insert-pos is visible
    method refresh(Bool:D $edited = False) {
        # If an edit just happened, recompute character widths
        self.recompute-widths if $edited;

        # We'll always start printing at the start end of the field, so begin
        # the refresh string with a jump to cursor-start, and all field width
        # available to draw in.
        my $refresh = self.cursor-move-command($!cursor-start - $!cursor-pos);
        my $avail   = $!field-width;
        my $chars   = $!buffer.chars;

        # If moved beyond field edge on start end, fix scroll position so
        # insert position is just visible.
        $!scroll-pos = $!insert-pos if $!scroll-pos > $!insert-pos;

        # If insert-pos is off the far end, scroll it into view
        my $insert-before-end = $!insert-pos < $chars;
        while self.subbuffer-width($!scroll-pos, $!insert-pos)
            > $avail - ?$!scroll-pos - $insert-before-end {
            ++$!scroll-pos;
        }

        # If non-zero scroll, add a scroll marker and decrement available space
        if $!scroll-pos {
            $refresh ~= '⯇‭';
            --$avail;
        }

        # Figure out how much buffer we can display; we know that we have room
        # for at least the insert-pos (the previous loop did that), so start
        # with that to jump-start the process.
        my $last = $!insert-pos;
        ++$last while $last < $chars
                && self.subbuffer-width($!scroll-pos, $last) < $avail - ($last < $chars);

        # Check if we overshot by one because final character was wide
        --$last if self.subbuffer-width($!scroll-pos, $last) > $avail - ($last < $chars);

        # Add the determined subbuffer substring, possibly masked
        my $buffer = $!mask.defined ?? $!mask x $!buffer.chars !! $!buffer;
        $refresh ~= substr($buffer, $!scroll-pos, $last - $!scroll-pos);

        # Add a scroll marker or end padding if necessary
        my $scroll    = $last < $chars;
        my $width     = self.subbuffer-width($!scroll-pos, $last);
        my $pad-width = $avail - $width - $scroll;
        $refresh     ~= ' ' x $pad-width;
        $refresh     ~= '⯈‭' if $scroll;

        # We have now filled the whole buffer and can figure out where the
        # cursor should be (at the insert point, which we know to be visible by
        # now), so add a jump from the end to the cursor point and return the result
        $!cursor-pos = $!cursor-start + ?$!scroll-pos
                     + self.subbuffer-width($!scroll-pos, $!insert-pos);
        $refresh ~= self.cursor-move-command($!cursor-pos - $!cursor-end);

        $refresh;
    }
}

class MUGS::UI::CLI::Input {
    has IO::Handle:D $.input  = $*IN;
    has IO::Handle:D $.output = $*OUT;
    has              %.keymap = self.default-keymap;
    has              $!saved-termios;

    #| Default key map (from input character ord to edit-* method)
    method default-keymap() {
          1 => 'move-to-start',       # CTRL-A
          2 => 'move-back',           # CTRL-B
          3 => 'abort-input',         # CTRL-C
          4 => 'abort-or-delete',     # CTRL-D (or delete-char-forward)
          5 => 'move-to-end',         # CTRL-E
          6 => 'move-forward',        # CTRL-F
          7 => 'abort-modal',         # CTRL-G
          8 => 'delete-char-back',    # CTRL-H
          9 => 'tab',                 # CTRL-I, TAB
         10 => 'finish',              # CTRL-J, LF
         11 => 'delete-to-end',       # CTRL-K
         12 => 'refresh-all',         # CTRL-L
         13 => 'finish',              # CTRL-M, CR
         14 => 'history-next',        # CTRL-N
         16 => 'history-prev',        # CTRL-P
         20 => 'swap-chars',          # CTRL-T
         21 => 'delete-line',         # CTRL-U
         23 => 'delete-word-back',    # CTRL-W
         27 => 'escape',              # ESC
        127 => 'delete-char-back',    # BACKSPACE
          ;
    }

    #| Bind a key (by ord) to an edit action (by short string name)
    method bind-key(UInt:D $ord, Str:D $action) {
        die "Unknown action '$action'"
            unless MUGS::UI::CLI::Input::Buffer.^can("edit-$action")
                || $action eq 'abort-or-delete'
                || $action eq 'abort-input'
                || $action eq 'finish';
        %!keymap{$ord} = $action;
    }

    #| Switch input to raw mode if it's a TTY, returning saved state
    method enter-raw-mode() {
        # If a TTY, convert to raw mode, saving current mode first
        if $!input.t {
            my $fd = $!input.native-descriptor;
            $!saved-termios = Term::termios.new(:$fd).getattr;
            Term::termios.new(:$fd).getattr.makeraw.setattr(:FLUSH);
        }
    }

    #| Switch input back to normal mode (iff it was switched to raw previously)
    method leave-raw-mode() {
        $!saved-termios.setattr(:DRAIN) if $!saved-termios;
        $!saved-termios = Any;
        $!output.put('');
    }

    #| Read a single raw character, decoding bytes, returning Str if input cut off;
    #| assumes input already in raw mode
    method read-raw-char(--> Str) {
        my $buf = Buf.new;

        # TimToady++ for suggesting this decode loop idiom
        repeat {
            my $b = $!input.read(1) or return Str;
            $buf.push($b);
        } until try my $c = $buf.decode;

        $c
    }

    #| Query the terminal and return the raw response string;
    #| assumes input set up so read-raw-char works
    method query-terminal(Str:D $request, Str:D $stopper) {
        # Send request to terminal
        $!output.print($request);
        $!output.flush;

        # Grab the response
        my $response = '';
        my $c;
        repeat {
            $c = self.read-raw-char // last;
            $response ~= $c;
        } while $c ne $stopper;

        $response
    }

    #| Detect cursor position, returning (row, col) or Empty if unable
    method detect-cursor-pos() {
        my $response = self.query-terminal("\e[6n", 'R');
        $response ~~ /^ "\e[" (\d+) ';' (\d+) 'R' $/ ?? (+$0, +$1) !! Empty
    }

    #| Detect terminal size, returning (rows, cols) or Empty if unable
    method detect-terminal-size() {
        my $response = self.query-terminal("\e[18t", 't');
        $response ~~ /^ "\e[8;" (\d+) ';' (\d+) 't' $/ ?? (+$0, +$1) !! Empty
    }

    #| Full input/edit loop; returns final user input or Str if aborted
    method input(Str :$mask, Bool:D :$history = False, Str:D :$context = 'default' --> Str) {
        # If not a terminal, just read a line from input and return it
        return $!input.get // Str unless $!input.t;

        # Switch terminal to raw mode while editing
              self.enter-raw-mode;
        LEAVE self.leave-raw-mode;

        # Detect current cursor position and terminal size
        my ($row,  $col ) = self.detect-cursor-pos // return Str;
        my ($rows, $cols) = self.detect-terminal-size;

        # Set up an editable input buffer
        my $buffer = MUGS::UI::CLI::Input::Buffer.new(:cursor-start($col),
                                                      :cursor-end($cols // 80),
                                                      :$mask);

        # DRY helper
        my sub do-edit($command, $insert?) {
            my $edited = $insert ?? $buffer.edit-insert-string($insert)
                                 !! $buffer."edit-$command"();
            $!output.print($buffer.refresh($edited));
            $!output.flush
        }

        # Read raw characters and dispatch either as actions or chars to insert
        loop {
            my $c = self.read-raw-char // last;

            with %!keymap{$c.ord} {
                when 'finish'          { last }
                when 'abort-input'     { return Str }
                when 'abort-or-delete' { return Str unless $buffer.buffer;
                                         do-edit('delete-char-forward') }
                default                { do-edit($_) }
            }
            else { do-edit('insert-string', $c) }
        }

        # Return final buffer
        $buffer.buffer
    }

    #| Print and flush prompt then enter input loop, optionally masking password
    method prompt(Str:D $prompt = '', Str :$mask --> Str) {
        $!output.print($prompt);
        $!output.flush;

        self.input(:$mask)
    }
}
