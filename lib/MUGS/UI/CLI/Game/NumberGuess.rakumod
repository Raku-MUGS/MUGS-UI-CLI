# ABSTRACT: CLI for number-guess game

use MUGS::Core;
use MUGS::UI::CLI::Genre::Guessing;


#| CLI for number guessing game
class MUGS::UI::CLI::Game::NumberGuess is MUGS::UI::CLI::Genre::Guessing {
    method game-type() { 'number-guess' }

    method prompt-string(::?CLASS:D:) {
        my ($min, $max) = $.client.initial-state< min max >;
        "Enter a natural number between $min and $max >"
    }

    method guess-status($response) {
        my $result = $response.data<result>;
        "Guess {$response.data<turns>} was "
            ~ ($result == Less ?? 'too low.'  !!
               $result == More ?? 'too high.' !!
                                  'correct.')
    }

    method game-help() {
        q:to/HELP/.trim-trailing;
            Enter a number within the allowed range, and the server will tell
            you if you're too high, too low, or guessed correctly.
            HELP
    }
}


# Register this class as a valid game UI
MUGS::UI::CLI::Game::NumberGuess.register;
