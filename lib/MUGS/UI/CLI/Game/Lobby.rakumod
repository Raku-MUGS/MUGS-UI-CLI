# ABSTRACT: Simple CLI UI for game selection lobby

use MUGS::Core;
use MUGS::Client::Game::Lobby;
use MUGS::UI::CLI;

enum State < SelectType >;

my %prompts =
    SelectType => 'Select a game type';


#| CLI UI for game selection lobby
class MUGS::UI::CLI::Game::Lobby is MUGS::UI::CLI::Game {
    has State $.state = State(0);

    method game-type()     { 'lobby' }
    method prompt-string() { %prompts{$.state} ~ ' > ' }
    method is-lobby()      { True }

    method available-game-types(::?CLASS:D:) {
        my @available = $.client.available-game-types.grep: {
            MUGS::UI.ui-exists($.ui-type, .<game-type>)
        };
    }

    method show-available-game-types(::?CLASS:D:) {
        my @available = self.available-game-types.grep(*<game-type> ne 'lobby');

        put 'Known game types:';

        # XXXX: Factor out into a table maker or tree by genre
        my $max-type   = max 6, @available.map(*<game-type>.chars).max;
        my $max-genres = max 6, @available.map(*<genre-tags>.join(',').chars).max;
        my $format     = "    %-{$max-type}s  %-{$max-genres}s  %s\n";
        printf $format, 'TYPE', 'GENRES', 'DESCRIPTION';
        for @available.sort({.<genre-tags>, .<game-type>}) {
            printf $format, .<game-type>, .<genre-tags>.join(','), .<game-desc>;
        }
    }

    method show-initial-state(::?CLASS:D:) {
        self.show-available-game-types;
        put '';
    }

    method show-game-help(::?CLASS:D:) {
        put 'You are in the game lobby, and can choose a game to play.';
        put '';
        put self.general-help;

        self.show-available-game-types;
        put '';
    }

    method valid-turn($choice) {
        $choice.lc ∈ self.available-game-types.map(*<game-type>)
    }

    method submit-turn($choice) {
        my $game-type = $choice.lc;
        $.app-ui.put-sanitized($.app-ui.present-tense-message("Launching $game-type"));
        my $client = $.app-ui.new-game-client(:$game-type);
        $.app-ui.launch-game-ui(:$game-type, :$client);
    }
}


# Register this class as a valid game UI
MUGS::UI::CLI::Game::Lobby.register;
