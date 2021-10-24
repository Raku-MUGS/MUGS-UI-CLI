# ABSTRACT: General CLI for simple guessing games

use MUGS::Core;
use MUGS::Client::Genre::Guessing;
use MUGS::UI::CLI;


#| CLI for guessing games
class MUGS::UI::CLI::Genre::Guessing is MUGS::UI::CLI::Game {
    method prompt-string()           { 'Next guess >' }
    method guess-status($response)   { ... }
    method game-status($response)    { '' }
    method winloss-status($response) {
        my $winloss = $.client.my-winloss($response);
        my $round   = $response.data<round-result> // Undecided;

           $winloss == Win       ?? 'You win!' !!
           $round   == Win       ?? 'You win this round!  On to the next.' !!
           $round   == Loss
        && $winloss == Undecided ?? 'You ran out of time!  Try again next round.' !! ''
    }

    method show-turn-success($response) {
        say self.guess-status($response);
        callsame;
    }

    method show-game-state($response) {
        my $winloss = self.winloss-status($response);
        say $winloss if $winloss;

        say self.game-status($response);

        if $response.data<tried> && !$response.data<winloss> {
            my @previous  = $response.data<tried>.sort;
               @previous .= map({"'$_'"}) if $.screen-reader;
            say "Previous guesses: { @previous.join(' ') }";
        }
    }

    method show-initial-state(::?CLASS:D:) {
        await $.client.send-nop: { self.show-game-state($_) };
    }
}
