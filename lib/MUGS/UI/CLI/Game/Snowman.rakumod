# ABSTRACT: CLI for Snowman word guessing game

use MUGS::Core;
use MUGS::UI::CLI::Genre::Guessing;


#| CLI for Snowman word guessing game
class MUGS::UI::CLI::Game::Snowman is MUGS::UI::CLI::Genre::Guessing {
    method game-type()     { 'snowman' }
    method prompt-string() { 'Enter a letter in this word > ' }

    method guess-status($response) {
        "Guess {$response.data<turns>} was "
            ~ ($response.data<correct> ?? 'correct.'
                                       !! 'not in the word.')
    }

    method winloss-status($response) {
        given $response.data<winloss> {
            when Win  { "You win{', and just in time' if $response.data<misses> == 5}!" }
            when Loss { "Oh no, you didn't figure it out in time!" }
            default   {
                given $response.data<round-result> // Undecided {
                    when Win  { 'You win this round!  On to the next.' }
                    when Loss { 'You ran out of time!  Try again next round.' }
                    default   { '' }
                }
            }
        }
    }

    method game-status($response) {
        my @so-far  = $response.data<partial>.comb;
           @so-far .= map({ $_ eq '_' ?? "blank" !! "'$_'" }) if $.screen-reader;

        self.render-picture($response.data<misses>, ?$response.data<correct>)
        ~ "\nThe word is now: { @so-far.join(' ') }."
    }

    method describe-picture(UInt:D $misses, Bool:D $correct) {
        # Save annoying extra talking in screen reader mode if guess was correct
        return "Still $misses missed so far." if $correct;

        my @stages = self.stage-names.[^$misses].map('the ' ~ *);
        @stages[*-1] [R~]= 'and ' if @stages > 1;

        $misses == 0 ?? 'No misses yet, the picture is empty.'
                     !! "$misses missed; so far I've drawn @stages.join(', ')."
    }

    method render-picture(UInt:D $misses, Bool:D $correct) {
        return self.describe-picture($misses, $correct) if $.screen-reader;

        my @picture = self.picture-background;
        my @stages  = self.picture-stages;
        for ^($misses min +@stages) {
            my @stage := @stages[$_];
            for @stage -> $part {
                @picture[$part[1]].substr-rw($part[2], $part[0].chars) = $part[0];
            }
        }

        @picture.join("\n")
    }

    method game-help() {
        q:to/HELP/.trim-trailing;
            Enter a letter that you think might be in the word, and that you
            haven't guessed yet.  If you're right, every copy of that letter
            will be filled in, and you can guess again.  Make too many mistakes,
            and you lose!
            HELP
    }

    method picture-background() {
        '            ',
        '            ',
        '            ',
        '            ',
        '            ',
        '============'
    }

    method picture-stages() {
        # '     __     ',
        # '   _|__|_  W',
        # '    (**)   |',
        # '+--(  : )--+',
        # '  (   :  ) |',
        # '============'

        ((  '(   :  )', 4, 2), ),
        ((   '(  : )',  3, 3), ),
        ((    '(**)',   2, 4), ('__',  1, 5)),
        ((   '_|__|_',  1, 3), ('__',  0, 5)),
        (('+--',        3, 0), ('--+', 3, 9)),
        (('W', 1, 11), ('|', 2, 11), ('|', 4, 11)),
    }

    method stage-names() {
        « body shoulders head hat arms broom »
    }
}


# Register this class as a valid UI
MUGS::UI::CLI::Game::Snowman.register;
