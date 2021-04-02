# ABSTRACT: Simple CLI for tic-tac-toe

use MUGS::Core;
use MUGS::UI::CLI::Genre::MNKGame;


#| UI for tic-tac-toe
class MUGS::UI::CLI::Game::TicTacToe is MUGS::UI::CLI::Genre::MNKGame {
    method game-type() { 'tic-tac-toe' }
}


# Register this class as a valid game UI
MUGS::UI::CLI::Game::TicTacToe.register;
