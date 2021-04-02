# ABSTRACT: General CLI genre for M,N,K games (https://en.wikipedia.org/wiki/M,n,k-game)

use MUGS::Core;
use MUGS::Client::Genre::MNKGame;
use MUGS::UI::CLI::Genre::BoardGame;


#| CLI genre for M,N,K games
class MUGS::UI::CLI::Genre::MNKGame is MUGS::UI::CLI::Genre::BoardGame {
    method game-help() {
        q:to/HELP/.trim-trailing;
            Enter a board location to play in, by column and row.  For example,
            `a1` would play in the lower left corner.  Play several in a row
            horizontally, vertically, or diagonally to win.
            HELP
    }

    method show-board-state($response) {
        return if $.client.gamestate == NotStarted;

        my $board = $response.data<board>;
        my $name  = $.client.character-name;

        # XXXX: Check board is valid and non-degenerate

        my $board-height   = $board.elems;
        my $board-width    = $board[0].elems;
        my $wide-board     = $board-width > 26;
        my $max-row-string = $board-height.chars;
        my $max-col-string = $wide-board ?? $board-width.chars !! 1;

        for $board.pairs.reverse -> (:key($y), :value(@row)) {
            my $row = @row.map(-> $cell {
                $cell ?? ($cell eq $name ?? 'X' !! 'O') !! ' '
            }).join(' | ');
            printf "%{$max-row-string}d %s\n", $y+1, $row;
        }

        my $indent = ' ' x ($max-row-string + 1);
        if $wide-board {
            put $indent ~ (1..$board-width).fmt('%4d').join;
        }
        else {
            put $indent ~ (1..$board-width).map({($_ + 96).chr ~ '   '}).join;
        }
    }
}
