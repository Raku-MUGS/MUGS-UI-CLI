# ABSTRACT: General CLI for simple guessing games

use MUGS::Core;
use MUGS::Client::Genre::Guessing;
use MUGS::UI::CLI;


#| CLI for guessing games
class MUGS::UI::CLI::Genre::Guessing is MUGS::UI::CLI::Game {
    method prompt-string()           { 'Next guess > ' }
    method guess-status($response)   { ... }
    method game-status($response)    { '' }
    method winloss-status($response) {
        $response.data<winloss> == Win ?? 'You win!' !! ''
    }

    method show-guess-results($response) {
        say self.guess-status($response);
        self.show-game-state($response);
    }

    method show-game-state($response) {
        say self.game-status($response);

        if $response.data<tried> && !$response.data<winloss> {
            my @previous  = $response.data<tried>.sort;
               @previous .= map({"'$_'"}) if $.screen-reader;
            say "Previous guesses: { @previous.join(' ') }";
        }

        my $winloss = self.winloss-status($response);
        say $winloss if $winloss;
    }

    method show-initial-state(::?CLASS:D:) {
        await $.client.send-nop: { self.show-game-state($_) };
    }

    method valid-turn($guess) {
        $.client.valid-guess($guess)
    }

    method submit-turn($guess) {
        await $.client.send-guess: $guess, { self.show-guess-results($_) };
    }
}
