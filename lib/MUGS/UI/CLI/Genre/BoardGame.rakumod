# ABSTRACT: General CLI genre for board games

use MUGS::Core;
use MUGS::Client::Genre::BoardGame;
use MUGS::UI::CLI;


#| CLI genre for board games
class MUGS::UI::CLI::Genre::BoardGame is MUGS::UI::CLI::Game {
    method winloss-status($response) {
        given $response.data<winloss> {
            when Win  { 'You have won!'  }
            when Tie  { "It's a draw."   }
            when Loss { 'You have lost.' }
            default   { '' }
        }
    }

    method show-game-state($response) {
        my $winloss = self.winloss-status($response);
        $.app-ui.put-colored($winloss, 'bold') if $winloss;

        self.show-board-state($response);

        return unless $response.data<gamestate> == InProgress;

        my %schema = next-character => Str;
        my $next-character = $response.validated-data(%schema)<next-character>;
        if $next-character eq self.client.character-name {
            $.app-ui.put-colored("It's your turn.", 'bold');
        }
        else {
            $.app-ui.put-sanitized("Waiting for '$next-character' to play their turn.");
        }
    }

    method show-initial-state(::?CLASS:D:) {
        await $.client.send-nop: { self.show-game-state($_) };
    }
}
