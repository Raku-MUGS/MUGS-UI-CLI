# ABSTRACT: CLI for IF adventure games

use MUGS::Core;
use MUGS::Client::Game::Adventure;
use MUGS::UI::CLI::Genre::IF;


#| CLI for an IF adventure game
class MUGS::UI::CLI::Game::Adventure is MUGS::UI::CLI::Genre::IF {
    method game-type() { 'adventure' }

    method game-help() {
        q:to/HELP/.trim-trailing;
            You are in a simple adventure game.  Choose your actions with
            simple commands, such as `go west`, `take key`, or even
            `unlock the door with the iron key`.
            HELP
    }
}


# Register this class as a valid game UI
MUGS::UI::CLI::Game::Adventure.register;
